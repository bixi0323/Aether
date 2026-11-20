#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${1:?usage: $0 <image>}"
CONTAINER_ID=""
VERIFY_DIR=""

cleanup() {
  if [ -n "$CONTAINER_ID" ]; then
    docker rm "$CONTAINER_ID" >/dev/null 2>&1 || true
  fi
  if [ -n "$VERIFY_DIR" ] && [ -d "$VERIFY_DIR" ]; then
    find "$VERIFY_DIR" -xdev -depth -delete
  fi
}
trap cleanup EXIT

CONTAINER_ID="$(docker create "$IMAGE")"
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aether-frontend-verify.XXXXXX")"
docker cp "$CONTAINER_ID:/srv/frontend" "$VERIFY_DIR/frontend"

require_marker() {
  local marker="$1"
  if ! grep -aRqF -- "$marker" "$VERIFY_DIR/frontend"; then
    printf 'Required frontend feature marker is missing from image %s: %s\n' \
      "$IMAGE" "$marker" >&2
    return 1
  fi
}

require_marker 'usage-api-key-analysis'
require_marker 'byApiKeyAnalysis'
require_marker '/api/admin/stats/leaderboard/api-keys'

printf 'Verified API key analytics in frontend assets of %s\n' "$IMAGE"
