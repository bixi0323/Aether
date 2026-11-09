-- no-transaction
-- Pool management summarizes usage by provider key inside the active quota
-- windows. Keep the window's count, token, and cost aggregates on one
-- provider-key index so these reads do not repeatedly touch the wide usage
-- heap.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_usage_provider_key_created_cover
ON public.usage (provider_api_key_id, created_at)
INCLUDE (id, request_id, total_tokens, total_cost_usd);
