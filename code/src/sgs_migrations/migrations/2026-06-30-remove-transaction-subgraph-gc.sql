-- Revert the transaction_subgraph GC seeded by
-- 2026-06-16-add-transaction-subgraph-gc-schedule.sql. We now keep every
-- transaction's transaction_subgraphs rows indefinitely: they back the run
-- screen and (maybe soon?) security scans, so nothing reclaims them anymore.

-- Drop the singleton GC schedule. Its dispatch handler is gone, so leaving the
-- row would make the scheduler log UNKNOWN_KIND on every tick.
delete from schedules where kind = 'transaction_subgraph_gc';

-- Drop the partial index that existed only to serve the GC's conflict-overlap
-- probe (open transactions in the same tenant). The tenant transaction listing
-- rides the full transactions_tenant_id_created_at_idx instead, so this index is
-- now unused. DROP INDEX CONCURRENTLY must run outside a transaction -> ~mode:`Async.
drop index concurrently if exists transactions_open_tenant_created_at_idx;
