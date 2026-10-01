-- Schema for the per-transaction (plan-time) security impact.
--
-- Indexes on the lifecycle foreign keys (first_seen_scan_id, resolved_scan_id)
-- of security_scan_findings. The planned-scan abort/GC cleanup deletes
-- security_scans rows and probes these columns to find which scans surviving
-- findings still anchor; both would seq-scan the findings table without an
-- index on the referencing side of the FK. Partial on IS NOT NULL (matching
-- the query); CONCURRENTLY so building them does not lock writes on a
-- populated findings table.
--
-- The impact diff's in-scope set (the planned scan's covered resources) is not
-- stored here: it is read live from transaction_subgraphs at diff time, which is
-- retained indefinitely (2026-06-30-remove-transaction-subgraph-gc.sql).
--
-- This migration runs ~mode:`Async: each statement executes outside a
-- transaction, which CREATE INDEX CONCURRENTLY requires.

create index concurrently if not exists security_scan_findings_first_seen_scan_id_idx
  on security_scan_findings (first_seen_scan_id) where first_seen_scan_id is not null;

create index concurrently if not exists security_scan_findings_resolved_scan_id_idx
  on security_scan_findings (resolved_scan_id) where resolved_scan_id is not null;
