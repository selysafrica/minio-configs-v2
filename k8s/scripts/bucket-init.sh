#!/bin/sh
set -eu

MINIO_URL="http://127.0.0.1:9005"
MINIO_ALIAS="local"

echo "==> Waiting for MinIO at $MINIO_URL ..."
until wget -qO- "$MINIO_URL/minio/health/live" >/dev/null 2>&1; do
    echo "    MinIO not ready, retrying..."
    sleep 3
done
echo "==> MinIO is ready."

echo "==> Configuring mc alias..."
mc alias set "$MINIO_ALIAS" "$MINIO_URL" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

echo "==> Creating private bucket..."
mc mb --ignore-existing "$MINIO_ALIAS/private"
mc anonymous set none "$MINIO_ALIAS/private"
mc version enable "$MINIO_ALIAS/private"

echo "==> Creating public bucket..."
mc mb --ignore-existing "$MINIO_ALIAS/public"
mc anonymous set download "$MINIO_ALIAS/public"
mc version enable "$MINIO_ALIAS/public"

echo "==> Setting CORS on public bucket..."
echo '<CORSConfiguration><CORSRule><AllowedOrigin>*</AllowedOrigin><AllowedMethod>GET</AllowedMethod><AllowedMethod>HEAD</AllowedMethod><AllowedHeader>*</AllowedHeader><MaxAgeSeconds>3600</MaxAgeSeconds></CORSRule></CORSConfiguration>' | mc cors set "$MINIO_ALIAS/public" /dev/stdin

echo ""
echo "==> Buckets initialized:"
echo "    - private (no anonymous access, versioned)"
echo "    - public  (anonymous download, versioned, CORS)"
