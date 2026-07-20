#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

MINIO_HOST="${MINIO_ROOT_USER:-minioadmin}"
MINIO_PASS="${MINIO_ROOT_PASSWORD:-minioadmin}"
MINIO_ALIAS="local"
MINIO_ENDPOINT="http://127.0.0.1:9006"

echo "==> Waiting for MinIO to be ready..."
until docker exec minioV2 mc ready local 2>/dev/null; do
    sleep 2
done
echo "==> MinIO is ready."

run_mc() {
    docker exec minioV2 mc "$@"
}

echo "==> Configuring mc alias..."
run_mc alias set "$MINIO_ALIAS" "$MINIO_ENDPOINT" "$MINIO_HOST" "$MINIO_PASS"

# --- Private bucket ---
PRIVATE_BUCKET="private"
echo "==> Creating bucket: $PRIVATE_BUCKET"
run_mc mb --ignore-existing "${MINIO_ALIAS}/${PRIVATE_BUCKET}"
run_mc anonymous set none "${MINIO_ALIAS}/${PRIVATE_BUCKET}"
run_mc version enable "${MINIO_ALIAS}/${PRIVATE_BUCKET}"

# --- Public bucket ---
PUBLIC_BUCKET="public"
echo "==> Creating bucket: $PUBLIC_BUCKET"
run_mc mb --ignore-existing "${MINIO_ALIAS}/${PUBLIC_BUCKET}"
run_mc anonymous set download "${MINIO_ALIAS}/${PUBLIC_BUCKET}"
run_mc version enable "${MINIO_ALIAS}/${PUBLIC_BUCKET}"

# Set CORS policy on public bucket for browser access
CORS_CONFIG=$(cat <<'CORSEOF'
<CORSConfiguration>
  <CORSRule>
    <AllowedOrigin>*</AllowedOrigin>
    <AllowedMethod>GET</AllowedMethod>
    <AllowedMethod>HEAD</AllowedMethod>
    <AllowedHeader>*</AllowedHeader>
    <MaxAgeSeconds>3600</MaxAgeSeconds>
  </CORSRule>
</CORSConfiguration>
CORSEOF
)

echo "$CORS_CONFIG" | docker exec -i minio mc cors set "${MINIO_ALIAS}/${PUBLIC_BUCKET}" /dev/stdin

echo ""
echo "==> Buckets initialized successfully:"
echo "    - ${PRIVATE_BUCKET} (private, versioned)"
echo "    - ${PUBLIC_BUCKET}  (public read, versioned, CORS enabled)"
echo ""
echo "    S3 API:   https://s3.v2.selys.app"
echo "    Console:  https://minio.v2.selys.app"
