"""
=============================================================================
  Cloud Security Lab — Multi-Tenant Data Ingestion API
  Phase 2 Secured Application
=============================================================================

  This is the hardened version of the Phase 1 vulnerable lab application.
  The application keeps the same business purpose and public API, but removes
  the intentional vulnerabilities used in the attack paths.

  Main Phase 2 application hardening:
    - XML/SVG parsing disables DTD loading, external entity resolution, and
      parser network access to block XXE-to-SSRF.
    - No container credential URI is written to /tmp.
    - API responses no longer expose stack traces, parser internals, AWS ARNs,
      or parsed file preview content.
    - Lab-only vulnerable routes were removed:
        /admin/all-objects
        /files/<s3_key>
        /lab/secrets-dump
    - Tenant access remains enforced at the application layer using the
      authenticated tenant identity and S3 tenant prefixes.

=============================================================================
"""

import os
import io
import json
import uuid
import logging
from datetime import datetime, timezone
from functools import wraps
from cachetools import TTLCache

import boto3
import psycopg2
import psycopg2.extras
from botocore.exceptions import ClientError

# lxml is kept for compatibility with the existing namespace handling code,
# but the parser is configured in safe mode: no DTD loading, no external entity
# expansion, and no network access during XML parsing.
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
# Phase 2: tenant API keys are cached only briefly to reduce Secrets Manager
# calls while avoiding indefinite in-process retention.
# ---------------------------------------------------------------------------
_api_key_cache = TTLCache(maxsize=10, ttl=300)   # {secret_path: api_key_value}, 5-minute TTL


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
# XML / SVG parsing — secured against XXE / SSRF
# ---------------------------------------------------------------------------

def _parse_xml_metadata(xml_bytes: bytes) -> dict:
    """
    Parse XML or SVG and extract metadata fields.

    Phase 2 hardening:
    - DTD loading is disabled.
    - External entity expansion is disabled.
    - Parser network access is disabled.
    - Huge-tree mode is disabled to reduce parser abuse risk.

    This prevents malicious XML/SVG uploads from reading local files or
    contacting the ECS task credential endpoint at 169.254.170.2.
    """
    parser = etree.XMLParser(
        resolve_entities=False,
        no_network=True,
        load_dtd=False,
        dtd_validation=False,
        huge_tree=False,
    )

    try:
        root = etree.fromstring(xml_bytes, parser=parser)
    except etree.XMLSyntaxError as exc:
        logger.warning("Rejected invalid XML/SVG upload: %s", exc)
        raise ValueError("Invalid XML/SVG content") from exc

    metadata = {
        "record_count": 0,
        "schema_version": None,
        "root_tag": root.tag,
        "namespace": None,
    }

    schema_version = root.get("version") or root.get("schemaVersion")
    if schema_version:
        metadata["schema_version"] = schema_version[:64]

    for tag in ("record", "row", "item", "entry", "object", "element"):
        records = root.findall(f".//{tag}")
        if records:
            metadata["record_count"] = len(records)
            break

    if root.nsmap:
        metadata["namespace"] = list(root.nsmap.values())[0]

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

    Phase 2: uploads are always written under the authenticated tenant prefix.
    IAM and S3 bucket policy provide defense in depth, while tenant ownership
    is enforced by this application logic.
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

    Phase 2: callers use this helper only with the authenticated tenant prefix.
    The public routes never accept an arbitrary prefix from the user.
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
# Upload endpoint
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
      3. Safely parse XML/SVG metadata
      4. Store original file in S3 under the authenticated tenant prefix
      5. Write metadata to PostgreSQL
      6. Return a minimal JSON response with upload ID
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
            file_metadata = _parse_xml_metadata(file_bytes)
            logger.info(
                "Parsed %s for %s: %d records",
                filename, g.tenant_id, file_metadata.get("record_count", 0),
            )
        except ValueError:
            return jsonify({"error": "Invalid XML/SVG content"}), 422
        except Exception:
            logger.exception("Unexpected XML/SVG parse error")
            return jsonify({"error": "Invalid file content"}), 500
    else:
        file_metadata = {"record_count": 0, "schema_version": None}

    # Store in S3
    try:
        s3_key = _s3_upload(g.tenant_id, filename, file_bytes, content_type)
    except Exception:
        logger.exception("S3 upload failed")
        return jsonify({"error": "Storage error"}), 500

    # Write metadata to PostgreSQL
    try:
        upload_id = _db_insert_metadata(
            g.tenant_id, filename, s3_key, file_metadata,
        )
    except Exception:
        logger.exception("DB write failed")
        return jsonify({"error": "Database error"}), 500

    return jsonify({
        "upload_id":      upload_id,
        "tenant_id":      g.tenant_id,
        "filename":       filename,
        "s3_key":         s3_key,
        "record_count":   file_metadata.get("record_count", 0),
        "schema_version": file_metadata.get("schema_version"),
        "status":         "processed",
    }), 201


# ---------------------------------------------------------------------------
# List uploads for a tenant
# ---------------------------------------------------------------------------

@app.route("/uploads", methods=["GET"])
@require_api_key
def list_uploads():
    """
    GET /uploads
    Returns metadata for all uploads belonging to the authenticated tenant.
    Also returns the S3 object list for that tenant's prefix.

    Phase 2: results are scoped to the authenticated tenant only.
    """
    try:
        db_rows    = _db_list_uploads(g.tenant_id)
        s3_objects = _s3_list_objects(f"{g.tenant_id}/")
    except Exception:
        logger.exception("Failed to list uploads for tenant %s", g.tenant_id)
        return jsonify({"error": "Unable to list uploads"}), 500

    return jsonify({
        "tenant_id":    g.tenant_id,
        "uploads":      db_rows,
        "s3_objects":   s3_objects,
        "upload_count": len(db_rows),
    }), 200


# ---------------------------------------------------------------------------
# Database initialization
# ---------------------------------------------------------------------------

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