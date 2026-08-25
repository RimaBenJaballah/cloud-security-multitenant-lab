# =============================================================================
#  Cloud Security Lab — Phase 2 Dockerfile
#  Flask Multi-Tenant Data Ingestion API
#  Listens on port 8080 (matches ALB target group and ECS task definition)
# =============================================================================

FROM python:3.11-slim

# System dependencies required by lxml, psycopg2-binary, and health checks
RUN apt-get update && apt-get install -y --no-install-recommends \
        libxml2-dev \
        libxslt-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Run as a non-root application user
RUN groupadd --gid 1001 appgroup \
 && useradd --uid 1001 --gid appgroup --no-create-home appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

USER appuser
EXPOSE 8080
ENV PYTHONUNBUFFERED=1

CMD ["gunicorn", \
     "--bind", "0.0.0.0:8080", \
     "--workers", "1", \
     "--timeout", "120", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "app:app"]
