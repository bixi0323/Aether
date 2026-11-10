# Pool management performance

Opening the pool management page is dominated by `GET
/api/admin/pool/:provider_id/keys`. For Codex providers, the gateway computes
cycle usage from `usage_billing_facts` for each key and window before returning
the key list; table size and the browser are not the bottleneck.

Observed on this deployment:

- The slow Codex provider had one key and 137,950 usage rows.
- The active weekly window contained about 12,000 rows.
- The endpoint took 7.4 seconds; a smaller Claude pool took 1.1 seconds.
- The host has one CPU, so concurrent API traffic also increases variance.

Mitigations:

- `idx_usage_provider_key_created_cover` makes the selective window scan an
  index-only aggregate instead of reading the wide `usage` heap. The migration
  is `20261022000000_add_usage_provider_key_window_covering_index.sql`.
- `VACUUM (ANALYZE)` on `usage` and `usage_settlement_snapshots` removes dead
  tuples that otherwise force random heap visibility checks during the view
  join. This is not a schema change and is safe to repeat.
- After both steps, the weekly aggregate measured about 0.9-1.2 seconds instead
  of 3-7 seconds. It is still computed live on every page request.

Periodic maintenance when the page becomes slow again:

```bash
docker exec aether-postgres psql -U postgres -d aether -c "VACUUM (ANALYZE) usage"
docker exec aether-postgres psql -U postgres -d aether -c "VACUUM (ANALYZE) usage_settlement_snapshots"
```

The next meaningful improvement requires an application change: serve a cached
or incrementally maintained per-key window summary and use it on the pool-list
read path. Index and vacuum tuning cannot make the existing per-request scan
constant-time.
