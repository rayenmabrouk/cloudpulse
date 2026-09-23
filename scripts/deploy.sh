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
# Preferred: Amazon ECR credential helper - fetches short-lived registry credentials
# from the instance role on demand, so no token is written to /root/.docker/config.json.
# Fallback: classic docker login if the helper package is unavailable.
if command -v docker-credential-ecr-login >/dev/null 2>&1 \
   || dnf install -y -q amazon-ecr-credential-helper >/dev/null 2>&1; then
  mkdir -p /root/.docker
  echo "{\"credHelpers\":{\"${REGISTRY}\":\"ecr-login\"}}" > /root/.docker/config.json
  log "ECR auth: credential helper (no stored token)"
else
  aws ecr get-login-password --region "${REGION}" \
    | docker login --username AWS --password-stdin "${REGISTRY}" >/dev/null 2>&1
  log "ECR auth: docker login fallback"
fi
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

# Daily purge of expired snippets (dpaste's cleanup_snippets command).
# systemd timer because Amazon Linux 2023 ships without cron.
ensure_cleanup_timer() {
  cat > /etc/systemd/system/cloudpulse-cleanup.service <<EOF
[Unit]
Description=CloudPulse - purge expired dpaste snippets
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/docker exec ${CONTAINER} python manage.py cleanup_snippets
EOF
  cat > /etc/systemd/system/cloudpulse-cleanup.timer <<EOF
[Unit]
Description=Run CloudPulse snippet cleanup daily

[Timer]
OnCalendar=daily
RandomizedDelaySec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now cloudpulse-cleanup.timer >/dev/null 2>&1
  log "Cleanup timer active"
}

start_container "${IMAGE}"
if healthy; then
  log "Healthy: ${IMAGE}"
  echo "${IMAGE}" > "${STATE_DIR}/current_image"
  ensure_proxy
  ensure_cleanup_timer
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