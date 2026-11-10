#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

cd /opt/aether
unset COMPOSE_FILE

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR=/root/aether-backups
BACKUP_FILE="${EXISTING_BACKUP:-$BACKUP_DIR/aether-pre-pr818-$RUN_ID.dump}"
STATUS_FILE="$BACKUP_DIR/pr818-deploy.status"
LOG_FILE="$BACKUP_DIR/pr818-deploy-$RUN_ID.log"
OLD_IMAGE='ghcr.io/bixi0323/aether@sha256:c07c0ebccabe646fa67880bf547235869dc31df6fcee476dc5d2b7b7911a53c1'
NEW_IMAGE='ghcr.io/bixi0323/aether:pr-818-5de69709132ca5391d285bceb54e99ed83b958ae'
COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.custom.yml)
SWITCHED=0
ROLLED_BACK=0

mkdir -p "$BACKUP_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

write_status() {
  printf '%s image=%s backup=%s finished=%s\n' \
    "$1" "$NEW_IMAGE" "$BACKUP_FILE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "$STATUS_FILE"
}

rollback_app() {
  if [ "$ROLLED_BACK" -eq 1 ]; then
    return
  fi
  ROLLED_BACK=1
  set +e
  echo "Rolling back to the previous application image"
  env -u COMPOSE_FILE docker compose -f docker-compose.yml \
    up -d --no-deps --force-recreate app
  local rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "Automatic application rollback failed; inspect docker logs aether-app"
  fi
}

on_error() {
  local rc=$?
  trap - ERR
  echo "Deployment failed at $(date -u +%Y-%m-%dT%H:%M:%SZ) with exit code $rc"
  if [ "$SWITCHED" -eq 1 ]; then
    rollback_app
  fi
  write_status FAILED
  exit "$rc"
}
trap on_error ERR

echo "Aether PR-818 deployment started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
write_status RUNNING

echo "Preflight checks"
test -f docker-compose.yml
test -f docker-compose.custom.yml
test -s .env
"${COMPOSE[@]}" config --quiet
docker inspect aether-postgres >/dev/null
docker image inspect "$OLD_IMAGE" >/dev/null
df -h /

AVAILABLE_KIB="$(df -Pk / | awk 'NR == 2 {print $4}')"
if [ "$AVAILABLE_KIB" -lt 3145728 ]; then
  echo "Less than 3 GiB is available on /; refusing to deploy"
  exit 1
fi

echo "Tagging the current image for application rollback"
docker tag "$OLD_IMAGE" aether:pre-pr818-20261105

if [ "${USE_EXISTING_BACKUP:-0}" = "1" ]; then
  echo "Using existing database backup: $BACKUP_FILE"
  test -s "$BACKUP_FILE"
else
  echo "Creating database backup: $BACKUP_FILE"
  docker exec aether-postgres \
    pg_dump -U postgres -d aether -Fc \
    > "$BACKUP_FILE.part"
  test -s "$BACKUP_FILE.part"
  mv "$BACKUP_FILE.part" "$BACKUP_FILE"
fi

echo "Validating database backup"
docker run --rm \
  -v "$BACKUP_DIR:/backups:ro" \
  postgres:17 \
  pg_restore -l "/backups/$(basename "$BACKUP_FILE")" \
  >/dev/null
sha256sum "$BACKUP_FILE"

echo "Pulling the new image"
docker pull "$NEW_IMAGE"
docker image inspect "$NEW_IMAGE" >/dev/null

echo "Running database migrations while the old application remains online"
"${COMPOSE[@]}" run --rm --no-deps -T app --migrate

echo "Replacing only the Aether application container"
SWITCHED=1
"${COMPOSE[@]}" up -d \
  --no-build \
  --no-deps \
  --force-recreate \
  --wait \
  --wait-timeout 180 \
  app

HEALTHY=0
for _ in $(seq 1 60); do
  if curl -fsS --max-time 5 http://127.0.0.1:8084/health >/dev/null; then
    HEALTHY=1
    break
  fi
  sleep 2
done

if [ "$HEALTHY" -ne 1 ]; then
  echo "New application did not pass the HTTP health check"
  rollback_app
  write_status FAILED
  exit 1
fi

docker inspect aether-app \
  --format 'image={{.Config.Image}} health={{.State.Health.Status}}'
docker logs --tail 100 aether-app

trap - ERR
write_status SUCCESS
echo "Aether PR-818 deployment completed successfully"
