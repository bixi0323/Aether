-- no-transaction
-- Pool management computes per-key Codex cycle usage over a time window. The
-- window scan is selective by provider key and needs count, token and cost
-- values, so keep those values in one covering index and avoid touching the
-- wide usage heap for every request in the window.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_usage_provider_key_created_cover
ON usage (provider_api_key_id, created_at)
INCLUDE (id, request_id, total_tokens, total_cost_usd);
