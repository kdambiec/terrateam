-- Tenant transaction listing (GET /api/v1/tenants/{id}/tx, select_tx_page.sql)
-- filters tenant_id and pages newest-first by created_at. The existing
-- transactions_open_tenant_created_at_idx is PARTIAL (open transactions only),
-- so the all-states listing fell back to a Seq Scan + Sort. A full
-- (tenant_id, created_at desc) index serves it as an Index Scan + Limit.
--
-- transaction_logs intentionally gets no new index here: WHERE tx_id = <one tx>
-- lookups (select_tx_log_page.sql, tx-metrics impact) already ride the leading
-- column of transaction_logs_tx_id_action_object_type_idx, verified by EXPLAIN.
--
-- CREATE INDEX CONCURRENTLY must run outside a transaction; registered with
-- ~mode:`Async in sgs_migrations.ml. IF NOT EXISTS keeps it idempotent.
CREATE INDEX CONCURRENTLY IF NOT EXISTS transactions_tenant_id_created_at_idx
  ON transactions (tenant_id, created_at DESC)
