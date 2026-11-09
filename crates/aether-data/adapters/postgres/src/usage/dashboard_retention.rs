use crate::error::SqlxResultExt;
use crate::DataLayerError;
use chrono::{DateTime, Timelike, Utc};

use super::SqlxUsageReadRepository;

/// Moves expired wide dashboard buckets into the narrow lifetime activity
/// projection and removes data that is no longer needed by the dashboard.
/// Every invocation is bounded; it never scans or rewrites usage history.
impl SqlxUsageReadRepository {
    pub async fn maintain_dashboard_projection(
        &self,
        now: DateTime<Utc>,
        batch_size: i64,
    ) -> Result<bool, DataLayerError> {
        let batch_size = batch_size.clamp(1, 5_000);
        let cutoff = (now - chrono::Duration::days(35))
            .with_second(0)
            .and_then(|value| value.with_nanosecond(0))
            .expect("valid minute");
        let mut tx = self.pool.begin().await.map_postgres_err()?;
        sqlx::query("SET LOCAL statement_timeout='5s'")
            .execute(&mut *tx)
            .await
            .map_postgres_err()?;
        sqlx::query("SET LOCAL lock_timeout='2s'")
            .execute(&mut *tx)
            .await
            .map_postgres_err()?;

        // Always acquire aggregate shards before minute rows, like the deferred
        // correction trigger. Cutoff decisions can straddle a minute boundary;
        // relying on old/new buckets alone is insufficient to prevent inversion.
        // Skip busy shards and keep these locks only for the short compaction tx.
        let shards: Vec<i16> = sqlx::query_scalar(
            "SELECT shard FROM dashboard_stats_total ORDER BY shard FOR UPDATE SKIP LOCKED",
        )
        .fetch_all(&mut *tx)
        .await
        .map_postgres_err()?;
        let compacted = sqlx::query(
            r#"
            WITH selected AS MATERIALIZED (
              SELECT bucket_start, shard, metrics
              FROM dashboard_stats_minute WHERE bucket_start < $1 AND shard=ANY($3)
              ORDER BY bucket_start, shard LIMIT $2 FOR UPDATE SKIP LOCKED
            ), preserved AS (
              INSERT INTO dashboard_activity_minute(bucket_start,shard,request_count)
                SELECT bucket_start,shard,COALESCE((metrics->>'request_count')::bigint,0)
                FROM selected
              ON CONFLICT(bucket_start,shard) DO NOTHING
              RETURNING bucket_start
            )
            DELETE FROM dashboard_stats_minute wide USING selected
            WHERE wide.bucket_start=selected.bucket_start AND wide.shard=selected.shard
              AND (SELECT count(*) FROM preserved)>=0
        "#,
        )
        .bind(cutoff)
        .bind(batch_size)
        .bind(&shards)
        .execute(&mut *tx)
        .await
        .map_postgres_err()?;
        let mut changed = compacted.rows_affected() > 0;
        tx.commit().await.map_postgres_err()?;

        let mut tx = self.pool.begin().await.map_postgres_err()?;
        sqlx::query("SET LOCAL statement_timeout='5s'")
            .execute(&mut *tx)
            .await
            .map_postgres_err()?;
        sqlx::query("SET LOCAL lock_timeout='2s'")
            .execute(&mut *tx)
            .await
            .map_postgres_err()?;

        // Actor counts, user event deltas and per-minute metric details are
        // only used by the rolling dashboard window. Their retention is
        // intentionally the same as the wide metric buckets.
        for table in ["dashboard_actor_minute", "dashboard_user_events_minute"] {
            // PostgreSQL has no DELETE ... ORDER BY ... LIMIT syntax. Use a
            // bounded key subquery so each pass remains small.
            let statement = format!(
                "DELETE FROM {table} WHERE ctid IN (SELECT ctid FROM {table} WHERE bucket_start < $1 ORDER BY bucket_start LIMIT $2)"
            );
            let deleted = sqlx::query(&statement)
                .bind(cutoff)
                .bind(batch_size)
                .execute(&mut *tx)
                .await
                .map_postgres_err()?;
            changed |= deleted.rows_affected() > 0;
        }

        tx.commit().await.map_postgres_err()?;
        Ok(changed)
    }
}
