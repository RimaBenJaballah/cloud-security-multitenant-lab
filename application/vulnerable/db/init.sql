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