-- Tag every FOCUS billing row with the source that produced it, and make that
-- the reload key.  The foundation reloaded a trailing window per
-- (tenant_id, provider); once a tenant can have several sources of the same
-- provider, that key would let one source's reload clobber another's rows in
-- the same window.  Keying the DELETE+INSERT on source_id instead gives each
-- source its own independently-reloadable slice (and enables per-source cost
-- attribution).  tenant_id / provider stay on focus_billing, denormalized, so
-- rollups still group by them without a join.
--
-- Nullable to stay backwards compatible (additive).  The worker is the sole
-- writer and always sets it; FOCUS is unreleased so there is no backfill.
alter table focus_billing
  add column source_id uuid references focus_billing_sources(id);

-- Serves the per-source trailing-window DELETE as a tight range scan.
create index focus_billing_source_window_idx
  on focus_billing (source_id, billing_period_start);
