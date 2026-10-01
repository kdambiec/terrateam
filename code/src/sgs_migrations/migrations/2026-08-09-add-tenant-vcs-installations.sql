-- Maps orchestration-engine (terrateam) VCS installations to Stategraph
-- tenants, keyed on the uuid core_id from the terrateam *_installations_map
-- tables (the stable surrogate for the provider's bigint installation id).
-- This is what scopes MQL reads of terrateam tables per-tenant: a terrateam
-- row is visible to a tenant iff it reaches an installation whose core_id is
-- mapped here. One tenant per installation; a tenant may own many
-- installations. Lives in the stategraph database -- terrat knows nothing
-- about tenants.
create table tenant_vcs_installations (
  tenant_id uuid not null references tenants (id) on delete cascade,
  provider text not null check (provider in ('github', 'gitlab')),
  installation_core_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (provider, installation_core_id)
);

create index tenant_vcs_installations_tenant_id_idx on tenant_vcs_installations (tenant_id);
