-- Cost attribution (#868): join actual FOCUS spend to the resources we manage.
--
-- Both tables are DERIVED, recomputed state -- rebuilt from focus_billing +
-- instances by Sgs_focus_attribution after every successful FOCUS sync.  A
-- better matcher later means bumping matcher_version and recomputing, never
-- migrating or backfilling.

-- The managed-resource -> cloud-identifier index for one (tenant, provider):
-- every identifier form a managed instance exposes (AWS arn AND bare id, GCP
-- self_link AND id, Azure id), normalized by the matcher
-- (Sgs_focus_attribution_matcher), one row per identifier.  Deliberately
-- independent of the pricing pipeline's cost_snapshot_resources.cloud_resource_id:
-- attribution must not require a pricing run.  The PK dedupes identifiers shared
-- by several resources (e.g. aws_s3_bucket and aws_s3_bucket_policy expose the
-- same id); the rebuild inserts in deterministic order with ON CONFLICT DO
-- NOTHING, so the winner is stable.  state_id has no FK: rows are a recomputable
-- cache -- hard_delete_state.sql clears a deleted state's rows eagerly, and any
-- other staleness heals at the next recompute.
create table resource_cloud_ids (
  tenant_id        uuid not null,
  provider         text not null check (provider in ('aws', 'gcp', 'azure')),
  cloud_id         text not null,
  state_id         uuid not null,
  address          text not null,
  matcher_version  integer not null,
  computed_at      timestamp with time zone not null default (now()),
  primary key (tenant_id, provider, cloud_id),
  foreign key (tenant_id) references tenants(id)
);

-- One row per focus_billing line: which of the three buckets it landed in.
--   attributed  -- the line's ResourceId matched a managed resource (state_id,
--                  address say which)
--   unmanaged   -- the line names a real resource we do NOT manage (the
--                  sharpest signal we produce: spend outside the graph)
--   unallocated -- the line has nothing to match on (taxes, support, fees,
--                  account-level charges)
-- The CASCADE rides the ETL's idempotent trailing-window DELETE+INSERT: a
-- reload drops the window's attribution rows automatically and the post-sync
-- recompute rebuilds them.  The status/state CHECK pins each bucket to exactly
-- its shape.  state_id has no FK for the same recomputable-cache reason as
-- resource_cloud_ids; hard_delete_state.sql likewise clears a deleted state's
-- rows.
create table focus_billing_attribution (
  billing_id       bigint primary key references focus_billing(id) on delete cascade,
  status           text not null check (status in ('attributed', 'unmanaged', 'unallocated')),
  state_id         uuid,
  address          text,
  matched_cloud_id text,
  matcher_version  integer not null,
  computed_at      timestamp with time zone not null default (now()),
  check ((status = 'attributed') = (state_id is not null and address is not null))
);
