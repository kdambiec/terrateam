-- Per-state actuals (#830): GET /states/{state_id}/costs/actuals starts from
-- the state's attributed rows, but focus_billing_attribution only had its PK
-- (billing_id), so the lookup scanned the tenant's entire loaded bill on
-- every cost-analysis view.  Partial index: only attributed rows carry a
-- state_id (enforced by the status/state CHECK), and only they are queried
-- by state.  CONCURRENTLY because the table is live -- the FOCUS ETL's
-- trailing-window DELETE+INSERT and the post-sync recompute write to it; a
-- plain CREATE INDEX would block them for the build.
create index concurrently if not exists focus_billing_attribution_state_idx
  on focus_billing_attribution (state_id)
  where status = 'attributed';
