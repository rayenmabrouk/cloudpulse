#!/bin/bash
# CloudPulse SQLite backup / restore - runs ON the EC2 instance as root.
# Shipped to /opt/cloudpulse/backup.sh by the CD pipeline; deploy.sh installs a
# daily systemd timer that runs "backup.sh backup".
#
#   backup.sh backup            online backup of the dpaste database -> S3
#   backup.sh list              list available backups
#   backup.sh restore <key>     replace the live database with a backup from S3
#
# The bucket name comes from SSM Parameter Store (/cloudpulse/backup/bucket,
# created by Terraform). Credentials come from the instance role.
set -euo pipefail

CONTAINER="dpaste"
DB_PATH="/data/dpaste.sqlite"   # matches DATABASE_URL baked into the image
VOLUME="dpaste_data"
PREFIX="sqlite"
BUCKET_PARAM="/cloudpulse/backup/bucket"
STATE_DIR="/opt/cloudpulse"

log() { echo "[backup $(date -u +%H:%M:%S)] $*"; }

# Region from IMDSv2 (IMDSv1 is disabled on the instance)
IMDS="http://169.254.169.254/latest"
TOKEN=$(curl -sf -X PUT "${IMDS}/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
REGION=$(curl -sf -H "X-aws-ec2-metadata-token: ${TOKEN}" "${IMDS}/meta-data/placement/region")
BUCKET=$(aws ssm get-parameter --region "${REGION}" --name "${BUCKET_PARAM}" \
  --query Parameter.Value --output text)

WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

backup() {
  local stamp key
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  key="${PREFIX}/dpaste-${stamp}.sqlite.gz"

  # SQLite online backup API: a consistent copy while dpaste keeps serving
  # (copying the file directly could capture a half-written page).
  docker exec "${CONTAINER}" python -c "
import sqlite3
src = sqlite3.connect('${DB_PATH}')
dst = sqlite3.connect('/data/.backup.sqlite')
src.backup(dst)
dst.close(); src.close()
"
  docker cp "${CONTAINER}:/data/.backup.sqlite" "${WORK}/dpaste.sqlite"
  docker exec "${CONTAINER}" rm -f /data/.backup.sqlite
  gzip -9 "${WORK}/dpaste.sqlite"

  # The bucket enforces TLS and encrypts at rest (SSE-S3)
  aws s3 cp --region "${REGION}" --only-show-errors \
    "${WORK}/dpaste.sqlite.gz" "s3://${BUCKET}/${key}"
  log "Uploaded s3://${BUCKET}/${key} ($(stat -c %s "${WORK}/dpaste.sqlite.gz") bytes)"
}

list() {
  aws s3 ls --region "${REGION}" "s3://${BUCKET}/${PREFIX}/"
}

restore() {
  local key="${1:?usage: backup.sh restore <key, e.g. sqlite/dpaste-20260924T030000Z.sqlite.gz>}"
  local image
  image=$(cat "${STATE_DIR}/current_image")

  aws s3 cp --region "${REGION}" --only-show-errors "s3://${BUCKET}/${key}" "${WORK}/restore.sqlite.gz"
  gunzip "${WORK}/restore.sqlite.gz"

  # Refuse to restore a corrupt file (throwaway container: no network, read-only;
  # root only because the mktemp work directory is root-owned 0700)
  docker run --rm --network none --read-only -u 0 -v "${WORK}:/restore:ro" \
    --entrypoint python "${image}" -c "
import sqlite3, sys
r = sqlite3.connect('file:/restore/restore.sqlite?mode=ro', uri=True).execute('PRAGMA integrity_check').fetchone()[0]
sys.exit(0 if r == 'ok' else 'integrity_check: ' + r)
"
  log "Integrity check passed"

  # Keep a copy of the current database before overwriting it
  backup

  docker stop "${CONTAINER}" >/dev/null
  # Copy into the volume with the app image itself (no extra image pulled),
  # as root only for this step, then hand the file back to the dpaste user.
  docker run --rm --network none -u 0 -v "${VOLUME}:/data" -v "${WORK}:/restore:ro" \
    --entrypoint sh "${image}" -c \
    "cp /restore/restore.sqlite ${DB_PATH} && chown dpaste:dpaste ${DB_PATH} && rm -f ${DB_PATH}-journal"
  docker start "${CONTAINER}" >/dev/null

  for _ in $(seq 1 30); do
    if curl -sf -o /dev/null "http://localhost:8000/"; then
      log "Restored ${key}; dpaste healthy"
      return 0
    fi
    sleep 2
  done
  log "dpaste NOT healthy after restore"
  return 1
}

case "${1:-backup}" in
  backup)  backup ;;
  list)    list ;;
  restore) shift; restore "$@" ;;
  *) echo "usage: backup.sh [backup|list|restore <key>]" >&2; exit 2 ;;
esac
