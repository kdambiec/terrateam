create table cost_snapshots (
  id uuid primary key default (gen_random_uuid()),
  state_id uuid not null,
  tenant_id uuid not null,
  tx_id uuid,
  calculated_at timestamp with time zone not null default (now()),
  kind text not null default ('current') check (kind in ('current', 'planned')),
  source text not null default ('estimate') check (source in ('estimate')),
  triggered_by text not null check (triggered_by in ('state_import', 'tx_apply', 'actuator_commit', 'scheduled', 'manual', 'preview')),
  currency text not null,
  monthly_cost numeric,
  hourly_cost numeric,
  resource_count integer not null,
  supported_count integer not null,
  priced_count integer not null,
  pricing_service_version text,
  foreign key (state_id) references states(id),
  foreign key (tenant_id) references tenants(id),
  foreign key (tx_id) references transactions(id)
);

create index cost_snapshots_state_kind_calculated_at_idx
  on cost_snapshots (state_id, kind, calculated_at desc);

-- Serves the tx-scoped lookups (planned/current snapshot ids, per-state and
-- per-resource deltas, planned-snapshot cleanup): all filter on tx_id, which
-- the state/kind/calculated_at index above does not cover. Partial because
-- most snapshots are scheduled/manual/import 'current' rows with a NULL
-- tx_id; indexing only the tx-linked rows keeps it small.
create index cost_snapshots_tx_id_idx
  on cost_snapshots (tx_id) where tx_id is not null;

create table cost_snapshot_resources (
  snapshot_id uuid not null,
  address text not null,
  type text not null,
  provider text,
  region text,
  supported boolean not null,
  no_price boolean not null default (false),
  monthly_cost numeric,
  hourly_cost numeric,
  components jsonb,
  tags jsonb,
  cloud_resource_id text,
  primary key (snapshot_id, address),
  foreign key (snapshot_id) references cost_snapshots(id)
);
