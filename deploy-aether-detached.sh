#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

PROJECT_DIR="${PROJECT_DIR:-/opt/aether}"
NEW_IMAGE="${NEW_IMAGE:?NEW_IMAGE is required}"
COMPOSE_BASE="${COMPOSE_BASE:-docker-compose.yml}"
COMPOSE_OVERRIDE="${COMPOSE_OVERRIDE:-docker-compose.custom.yml}"
BACKUP_DIR="${BACKUP_DIR:-/root/aether-backups}"
APP_CONTAINER="${APP_CONTAINER:-aether-app}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-aether-postgres}"
PGDUMP_USER="${PGDUMP_USER:-postgres}"
PGDUMP_DB="${PGDUMP_DB:-aether}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8084/health}"
MIN_FREE_KIB="${MIN_FREE_KIB:-3145728}"
UPDATE_ID="${UPDATE_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
BACKUP_FILE="${EXISTING_BACKUP:-$BACKUP_DIR/aether-pre-update-$UPDATE_ID.dump}"
STATUS_FILE="$BACKUP_DIR/aether-detached-deploy.status"
LOG_FILE="$BACKUP_DIR/aether-detached-deploy-$UPDATE_ID.log"
SWITCHED=0
ROLLED_BACK=0

cd "$PROJECT_DIR"
unset COMPOSE_FILE
mkdir -p "$BACKUP_DIR"

exec 9>/run/lock/aether-detached-deploy.lock
if ! flock -n 9; then
  echo "Another detached Aether deployment is already running"
  exit 1
fi

exec > >(tee -a "$LOG_FILE") 2>&1

write_status() {
  printf '%s new_image=%s old_image=%s backup=%s finished=%s\n' \
    "$1" "$NEW_IMAGE" "${OLD_IMAGE:-unknown}" "$BACKUP_FILE" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATUS_FILE"
}

deploy_compose() {
  AETHER_DEPLOY_IMAGE="$NEW_IMAGE" docker compose \
    -f "$COMPOSE_BASE" -f "$COMPOSE_OVERRIDE" "$@"
}

rollback_app() {
  if [ "$ROLLED_BACK" -eq 1 ]; then
    return
  fi
  ROLLED_BACK=1
  set +e
  echo "Rolling back application to $OLD_IMAGE"
  env -u COMPOSE_FILE APP_IMAGE="$OLD_IMAGE" AETHER_DEPLOY_IMAGE="$OLD_IMAGE" docker compose \
    -f "$COMPOSE_BASE" up -d --pull never --no-deps --force-recreate app
  local rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "Automatic application rollback failed; inspect docker logs $APP_CONTAINER"
  fi
}

on_error() {
  local rc=$?
  trap - ERR
  echo "Deployment failed at $(date -u +%Y-%m-%dT%H:%M:%SZ), exit code $rc"
  if [ "$SWITCHED" -eq 1 ]; then
    rollback_app
  fi
  write_status FAILED
  exit "$rc"
}
trap on_error ERR

echo "Detached Aether deployment started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Old image and backup will be recorded before any switch"

test -f "$COMPOSE_BASE"
test -f "$COMPOSE_OVERRIDE"
test -s .env
docker inspect "$APP_CONTAINER" >/dev/null
docker inspect "$POSTGRES_CONTAINER" >/dev/null
OLD_IMAGE="$(docker inspect "$APP_CONTAINER" --format '{{.Config.Image}}')"
test -n "$OLD_IMAGE"
write_status RUNNING

AETHER_DEPLOY_IMAGE="$NEW_IMAGE" docker compose \
  -f "$COMPOSE_BASE" -f "$COMPOSE_OVERRIDE" config --quiet

AVAILABLE_KIB="$(df -Pk / | awk 'NR == 2 {print $4}')"
if [ "$AVAILABLE_KIB" -lt "$MIN_FREE_KIB" ]; then
  echo "Less than $MIN_FREE_KIB KiB is available on /; refusing to deploy"
  exit 1
fi

ROLLBACK_TAG="aether:pre-update-$UPDATE_ID"
docker tag "$OLD_IMAGE" "$ROLLBACK_TAG"
echo "Tagged old image as $ROLLBACK_TAG"

if [ "${USE_EXISTING_BACKUP:-0}" = "1" ]; then
  echo "Using existing backup: $BACKUP_FILE"
  test -s "$BACKUP_FILE"
else
  echo "Creating database backup: $BACKUP_FILE"
  docker exec "$POSTGRES_CONTAINER" \
    pg_dump -U "$PGDUMP_USER" -d "$PGDUMP_DB" -Fc \
    > "$BACKUP_FILE.part"
  test -s "$BACKUP_FILE.part"
  mv "$BACKUP_FILE.part" "$BACKUP_FILE"
fi

echo "Validating database backup"
docker run --rm \
  --pull=never \
  -v "$BACKUP_DIR:/backups:ro" \
  postgres:17 \
  pg_restore -l "/backups/$(basename "$BACKUP_FILE")" >/dev/null
sha256sum "$BACKUP_FILE"

if [ "${PULL_IMAGE:-1}" = "1" ]; then
  echo "Pulling image: $NEW_IMAGE"
  docker pull "$NEW_IMAGE"
else
  echo "Using local image without pulling: $NEW_IMAGE"
fi
docker image inspect "$NEW_IMAGE" >/dev/null

echo "Running database migrations before switching the application"
deploy_compose run --rm --no-deps --pull never -T app --migrate

echo "Replacing application container"
SWITCHED=1
deploy_compose up -d \
  --pull never \
  --no-build \
  --no-deps \
  --force-recreate \
  --wait \
  --wait-timeout 180 \
  app

HEALTHY=0
for _ in $(seq 1 60); do
  if curl -fsS --max-time 5 "$HEALTH_URL" >/dev/null; then
    HEALTHY=1
    break
  fi
  sleep 2
done
if [ "$HEALTHY" -ne 1 ]; then
  echo "New application did not pass the HTTP health check"
  rollback_app
  SWITCHED=0
  write_status FAILED
  exit 1
fi

docker inspect "$APP_CONTAINER" \
  --format 'image={{.Config.Image}} health={{.State.Health.Status}}'
docker logs --tail 100 "$APP_CONTAINER"

trap - ERR
SWITCHED=0
write_status SUCCESS
echo "Detached Aether deployment completed successfully"
