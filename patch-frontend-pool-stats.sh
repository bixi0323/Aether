#!/usr/bin/env bash
# Re-apply the custom "pool stats: account totals on the left" patch to a
# built Aether frontend dist directory.
#
# Usage: ./patch-frontend-pool-stats.sh <frontend-dist-dir>
#
# Background: the stock frontend shows "-" in the left column of the pool
# "统计" cell whenever a provider has only one cycle window. This patch makes
# the left column always show the account cumulative values (requests / tokens
# / cost) and keeps the cycle value on the right, matching the pre-upgrade UI.
set -euo pipefail
DIR="${1:-/opt/aether/frontend-dist}"
[[ -f "$DIR/index.html" && -d "$DIR/assets" ]] \
  || { echo "frontend dist not found in $DIR" >&2; exit 1; }

chunk="$(find "$DIR/assets" -maxdepth 1 -type f -name 'PoolManagement-*.js' \
  ! -name '*-poolstats-*' -print -quit)"
[[ -n "$chunk" ]] || { echo "PoolManagement chunk not found in $DIR" >&2; exit 1; }
python3 - "$chunk" <<'PY'
import pathlib
import sys

p = pathlib.Path(sys.argv[1])
s = p.read_text()
old = 'const T=S(j,w),$=S(b,w),ge=!!j;'
new = 'const T=(s.accountMetrics&&s.accountMetrics.find(m=>m.key===w))||S(j,w),$=S(b,w),ge=!0;'
if new not in s and old in s:
    p.write_text(s.replace(old, new, 1))
    print('patched:', p)
elif new in s:
    print('patch already present:', p)
else:
    raise SystemExit('expected pattern not found; frontend build changed, review the patch')
PY

entry_name="$(python3 - "$DIR/index.html" <<'PY'
import pathlib
import re
import sys

html = pathlib.Path(sys.argv[1]).read_text()
match = re.search(
    r'<script\b[^>]*\btype="module"[^>]*\bsrc="/[^"/]+/(index-[^"/?]+\.js)',
    html,
)
if match is None:
    raise SystemExit('module entry not found in index.html')
print(match.group(1))
PY
)"
entry="$DIR/assets/$entry_name"
[[ -f "$entry" ]] || { echo "entry asset not found: $entry" >&2; exit 1; }

# Build every release under a new path. Rewriting only the entry filename is
# unsafe because lazy chunks still import the original entry path; changing the
# directory instead invalidates the complete module graph in browsers and CDNs.
version="$({
  sha256sum < "$entry"
  sha256sum < "$chunk"
  sed -E 's#/assets-poolstats-[0-9a-f]+/#/assets/#g' "$DIR/index.html"
} | sha256sum | cut -c1-12)"
bundle_name="assets-poolstats-$version"
bundle="$DIR/$bundle_name"

rm -rf "$bundle"
cp -a "$DIR/assets" "$bundle"

python3 - "$bundle" "$bundle_name" <<'PY'
import pathlib
import sys

bundle = pathlib.Path(sys.argv[1])
bundle_name = sys.argv[2]
for asset in bundle.glob('*.js'):
    text = asset.read_text()
    updated = text.replace('"assets/', f'"{bundle_name}/')
    if updated != text:
        asset.write_text(updated)
PY

python3 - "$DIR/index.html" "$bundle_name" "$entry_name" "$version" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
bundle_name, entry_name, version = sys.argv[2:]
html = path.read_text()
html = re.sub(
    r'(["\'])/(?:assets|assets-poolstats-[0-9a-f]+)/',
    rf'\1/{bundle_name}/',
    html,
)
# Lazy chunks import the entry by its exact path. Adding a query parameter here
# makes the browser instantiate a second copy of the entry module.
html = re.sub(
    rf'src="/{re.escape(bundle_name)}/{re.escape(entry_name)}(?:\?[^"]*)?"',
    f'src="/{bundle_name}/{entry_name}"',
    html,
    count=1,
)
path.write_text(html)
PY

find "$bundle" -type f -exec chmod 644 {} +
find "$bundle" -type d -exec chmod 755 {} +
node --input-type=module --check < "$entry" \
  && echo "syntax OK: $entry"
node --input-type=module --check < "$chunk" && echo "syntax OK: $chunk"
echo "published frontend bundle: $bundle"
