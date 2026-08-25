# =============================================================================
#  Cloud Security Lab — Dockerfile
#  Flask Multi-Tenant Data Ingestion API
#  Listens on port 8080 (matches ALB target group and ECS task definition)
# =============================================================================

FROM python:3.11-slim

# ---------------------------------------------------------------------------
# System dependencies required by lxml and psycopg2-binary
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        libxml2-dev \
        libxslt-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Application user — run as non-root inside the container
# (The ECS task role credential endpoint is still accessible regardless of
#  the OS user; running non-root does not mitigate the SSRF/XXE attack.)
# ---------------------------------------------------------------------------
RUN groupadd --gid 1001 appgroup \
 && useradd  --uid 1001 --gid appgroup --no-create-home appuser

WORKDIR /app

# ---------------------------------------------------------------------------
# Install Python dependencies
# ---------------------------------------------------------------------------
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ---------------------------------------------------------------------------
# Copy application source
# ---------------------------------------------------------------------------
COPY app.py .

# ---------------------------------------------------------------------------
# Runtime configuration
# ---------------------------------------------------------------------------
USER appuser
EXPOSE 8080
ENV PYTHONUNBUFFERED=1

# Gunicorn is used for ECS deployment (single worker matches task count=1)
# For local development, python app.py also works
CMD ["gunicorn", \
     "--bind", "0.0.0.0:8080", \
     "--workers", "1", \
     "--timeout", "120", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "app:app"]
