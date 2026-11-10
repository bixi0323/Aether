#!/usr/bin/env bash
# Refresh the host frontend dist from the running app image and re-apply the
# local pool-stats patch. Run this after every Aether image update.
#
# Usage: ./sync-frontend-from-image.sh [container-name]
set -euo pipefail
CONTAINER="${1:-aether-app}"
DIST="${AETHER_FRONTEND_DIST:-/opt/aether/frontend-dist}"
STAGE="${AETHER_FRONTEND_STAGE:-/opt/aether/frontend-dist.staged}"
if [[ -n "${AETHER_FRONTEND_IMAGE:-}" ]]; then
  IMAGE="${AETHER_FRONTEND_IMAGE}"
else
  IMAGE="$(docker inspect --format '{{.Config.Image}}' "$CONTAINER")"
fi
TMP_CONTAINER="aether-frontend-sync-$$"

cleanup() {
  docker rm -f "$TMP_CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE"
docker create --name "$TMP_CONTAINER" "$IMAGE" >/dev/null

# Images built by Dockerfile.app serve /srv/frontend, while older images use
# the release symlink. Read from a temporary image container so the bind mount
# on the running app cannot hide the upstream files.
COPIED=false
for STATIC_DIR in /srv/frontend /opt/aether/current/frontend; do
  if docker cp "$TMP_CONTAINER:$STATIC_DIR/." "$STAGE"/ 2>/dev/null; then
    COPIED=true
    break
  fi
done
if [ "$COPIED" != true ]; then
  echo "frontend directory not found in image $IMAGE" >&2
  exit 1
fi

"$(dirname "$0")/patch-frontend-pool-stats.sh" "$STAGE"
find "$STAGE" -type f -exec chmod 644 {} +
find "$STAGE" -type d -exec chmod 755 {} +
if [ -d "$DIST" ]; then
  mv "$DIST" "${DIST}.previous-$(date +%Y%m%dT%H%M%S)"
fi
mv "$STAGE" "$DIST"
echo "frontend dist refreshed at $DIST (previous kept alongside)"
echo "restart the app container to pick it up: docker restart $CONTAINER"
