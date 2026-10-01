-- Tenant-scope the group rules: every rule now belongs to a tenant.
--
-- The table shipped (2026-07-01-add-caps-group-rules.sql) with no owning tenant -- rules were
-- installation-global and an admin could grant any capability through them.  Under the new model a
-- rule belongs to a tenant: its admins manage it and its grant is bounded to that tenant.  Login
-- still evaluates every alive rule across all tenants; the tenant scopes who may manage a rule and
-- what it may grant, not which users it applies to.
--
-- [tenant_id] is a required FK with no sensible default, so it cannot be backfilled: a pre-existing
-- global rule has no valid owner and its grant may exceed any single tenant.  Such rows are dropped
-- rather than assigned a guessed tenant -- this also lets the NOT NULL column be added on a
-- possibly-populated table.  The delete only removes rows the new code could not read anyway (it
-- reads [tenant_id] as non-null), and is a no-op if the feature was never exercised.
delete from caps_group_rules;

alter table caps_group_rules add column tenant_id uuid not null references tenants (id);

-- The management list and delete are scoped to one tenant's alive rules.
create index if not exists caps_group_rules_tenant_alive_idx
  on caps_group_rules (tenant_id)
  where deleted_at is null;
