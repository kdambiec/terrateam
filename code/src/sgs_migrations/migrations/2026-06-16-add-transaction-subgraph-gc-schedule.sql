-- Seed the singleton transaction-subgraph GC schedule.
-- Daily is plenty: reclamation is idempotent and only bounded by the
-- retention window (STATEGRAPH_TRANSACTION_SUBGRAPH_RETENTION_DAYS).
create index concurrently if not exists transactions_open_tenant_created_at_idx
  on transactions (tenant_id, created_at)
  where state not in ('committed', 'aborted', 'failed');

insert into schedules (schedule, kind)
  select 'daily', 'transaction_subgraph_gc'
  where not exists (select 1 from schedules where kind = 'transaction_subgraph_gc');
