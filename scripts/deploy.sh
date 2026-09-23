#!/bin/bash
# CloudPulse deploy script - runs ON the EC2 instance
# (manually over SSH for now, via SSM Run Command from the CD pipeline).
#  - Pulls a dpaste image tag from ECR and replaces the running container
#  - Health-checks it and rolls back to the previous image on failure
#  - Runs Caddy as the TLS-terminating reverse proxy: automatic HTTPS via
#    Let's Encrypt on <public-ip-with-dashes>.sslip.io
# Usage: sudo deploy.sh <image_tag>
set -euo pipefail

IMAGE_TAG="${1:?usage: deploy.sh <image_tag>}"
REGION="us-east-1"
REPO="cloudpulse"
CONTAINER="dpaste"
APP_PORT=8000
DATA_DIR="/data"
NETWORK="cloudpulse"
PROXY="caddy"
PROXY_IMAGE="caddy:2-alpine"
LOG_GROUP="/cloudpulse/dpaste"
SECRET_PARAM="/cloudpulse/django/secret_key"
STATE_DIR="/opt/cloudpulse"
ENV_FILE="${STATE_DIR}/app.env"
CADDYFILE="${STATE_DIR}/Caddyfile"

log() { echo "[deploy $(date -u +%H:%M:%S)] $*"; }

# --- Instance metadata via IMDSv2 (session token required; IMDSv1 disabled) ---
IMDS="http://169.254.169.254/latest"
TOKEN=$(curl -sf -X PUT "${IMDS}/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
meta() { curl -sf -H "X-aws-ec2-metadata-token: ${TOKEN}" "${IMDS}/$1"; }
ACCOUNT_ID=$(meta dynamic/instance-identity/document | grep -oP '"accountId"\s*:\s*"\K[0-9]+')
PUBLIC_IP=$(meta meta-data/public-ipv4)
APP_HOST="${PUBLIC_IP//./-}.sslip.io"

REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE="${REGISTRY}/${REPO}:${IMAGE_TAG}"
log "Deploying ${IMAGE} for https://${APP_HOST}"

# --- Pull image (instance role provides ECR read access; no stored credentials) ---
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}" >/dev/null 2>&1
docker pull -q "${IMAGE}" >/dev/null

# --- Runtime config: SECRET_KEY from SSM SecureString into a root-only env file ---
SECRET_KEY=$(aws ssm get-parameter --region "${REGION}" --name "${SECRET_PARAM}" \
  --with-decryption --query Parameter.Value --output text)
mkdir -p "${STATE_DIR}"
(
  umask 077
  cat > "${ENV_FILE}" <<EOF
SECRET_KEY=${SECRET_KEY}
DEBUG=False
ALLOWED_HOSTS=${APP_HOST},localhost,127.0.0.1
EOF
)

# --- Private Docker network shared by Caddy and dpaste ---
docker network inspect "${NETWORK}" >/dev/null 2>&1 || docker network create "${NETWORK}" >/dev/null

# awslogs driver options; $1 = stream prefix
set_log_opts() {
  LOG_OPTS=(--log-driver awslogs
    --log-opt "awslogs-region=${REGION}"
    --log-opt "awslogs-group=${LOG_GROUP}"
    --log-opt "awslogs-stream=$1-$(date -u +%Y%m%d-%H%M%S)")
}

PREVIOUS_IMAGE=$(docker inspect --format '{{.Config.Image}}' "${CONTAINER}" 2>/dev/null || true)

# dpaste listens only on the Docker network and on localhost (for health checks);
# it is NOT reachable from the internet directly.
start_container() {
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
  set_log_opts "${CONTAINER}"
  docker run -d --name "${CONTAINER}" --restart unless-stopped \
    --network "${NETWORK}" \
    -p "127.0.0.1:${APP_PORT}:8000" \
    --env-file "${ENV_FILE}" \
    -v "dpaste_data:${DATA_DIR}" \
    "${LOG_OPTS[@]}" \
    "$1" >/dev/null
}

healthy() {
  for _ in $(seq 1 30); do
    if curl -sf -o /dev/null "http://localhost:${APP_PORT}/"; then return 0; fi
    sleep 2
  done
  return 1
}

# Caddy: TLS termination + reverse proxy. Certificates persist in the caddy_data volume.
ensure_proxy() {
  cat > "${CADDYFILE}" <<EOF
${APP_HOST} {
    encode gzip
    reverse_proxy ${CONTAINER}:8000
    log {
        output stdout
        format json
    }
}
EOF
  if docker ps --format '{{.Names}}' | grep -qx "${PROXY}"; then
    docker exec "${PROXY}" caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1
    log "Caddy config reloaded"
  else
    docker rm -f "${PROXY}" >/dev/null 2>&1 || true
    set_log_opts "${PROXY}"
    docker pull -q "${PROXY_IMAGE}" >/dev/null
    docker run -d --name "${PROXY}" --restart unless-stopped \
      --network "${NETWORK}" \
      -p 80:80 -p 443:443 \
      -v "${CADDYFILE}:/etc/caddy/Caddyfile:ro" \
      -v caddy_data:/data -v caddy_config:/config \
      "${LOG_OPTS[@]}" \
      "${PROXY_IMAGE}" >/dev/null
    log "Caddy started"
  fi
}

start_container "${IMAGE}"
if healthy; then
  log "Healthy: ${IMAGE}"
  echo "${IMAGE}" > "${STATE_DIR}/current_image"
  ensure_proxy
  docker image prune -f >/dev/null
  log "Live at https://${APP_HOST}"
  exit 0
fi

log "Health check FAILED for ${IMAGE}. Last container logs:"
docker logs --tail 30 "${CONTAINER}" 2>&1 || true

if [ -n "${PREVIOUS_IMAGE}" ] && [ "${PREVIOUS_IMAGE}" != "${IMAGE}" ]; then
  log "Rolling back to ${PREVIOUS_IMAGE}"
  start_container "${PREVIOUS_IMAGE}"
  if healthy; then
    ensure_proxy
    log "Rollback healthy: ${PREVIOUS_IMAGE}"
  else
    log "Rollback ALSO unhealthy"
  fi
fi
exit 1