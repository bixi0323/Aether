# Frontend customization

`/opt/aether/frontend-dist` is mounted at `/srv/frontend` in the app container.
It contains the stock frontend from the running Aether image plus one local
patch applied by `patch-frontend-pool-stats.sh`.

Patch: the pool "统计" column keeps showing the account cumulative values
(requests / tokens / cost) in the left column, with the current cycle value on
the right. Stock behavior shows "-" on the left when a provider only exposes a
single cycle window.

The patch is published under a content-addressed directory such as
`/srv/frontend/assets-poolstats-64609fbe87b6/`, and `index.html` points at that
directory. This invalidates the complete lazy-loaded module graph without
renaming the entry file or requiring clients to clear their cache. Do not add a
query string to the entry URL: lazy chunks import the entry by its exact path,
so a query string creates a second entry module instance.

`./update.sh` now syncs and re-applies this patch automatically after pulling
the new image and before recreating the app container. The image is resolved
from the Compose configuration, not from the still-running old container. If
the sync or patch fails, the updater stops before replacing the healthy app.

For a manual refresh:
1. sync and re-patch the current image frontend: `./sync-frontend-from-image.sh`
2. restart the app container: `docker restart aether-app`

Set `AETHER_SYNC_LOCAL_FRONTEND=false` only when intentionally using the stock
frontend. A changed upstream minified layout makes the patch fail closed rather
than silently losing the account totals.

`sync-frontend-from-image.sh` reads the stock frontend from a temporary
container created from the app image. This avoids copying the bind-mounted host
directory back over itself.

The original pre-upgrade dist is kept at
`/opt/aether/frontend-dist.custom-0.7.19` and in
`/root/aether-backups/20261012T033755Z/frontend-dist.tar.gz`.
