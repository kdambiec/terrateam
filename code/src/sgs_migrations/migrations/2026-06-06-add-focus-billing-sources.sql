-- Per-tenant FOCUS billing sources: the DB-driven replacement for the env-var
-- config that drove the foundation ETL.  One row per configured export; a tenant
-- may have many, including several of the same provider (e.g. multiple AWS
-- payer exports).  Managed via the admin API / CLI / UI; synced by the
-- scheduler-driven worker, which writes the last_* status columns back.
-- Credentials are NOT stored here -- they resolve ambiently via DuckDB's
-- credential_chain (the same order the AWS CLI / SDKs use).
create table focus_billing_sources (
  id              uuid primary key default (gen_random_uuid()),
  tenant_id       uuid not null,
  provider        text not null check (provider in ('aws', 'gcp', 'azure')),
  source_uri      text not null,            -- s3://bucket/prefix/data/**/*.parquet (or a path)
  region          text,                     -- bucket region (aws); null = ambient / other
  window_months   integer not null default (2),
  enabled         boolean not null default (true),

  -- sync state, written only by the worker (never user-set):
  last_status     text check (last_status in ('ok', 'error', 'running')),
  last_error      text,
  last_synced_at  timestamp with time zone,
  last_row_count  integer,

  created_at      timestamp with time zone not null default (now()),
  updated_at      timestamp with time zone not null default (now()),

  foreign key (tenant_id) references tenants(id),
  -- N sources per provider, but no two pointed at the literally-same export.
  unique (tenant_id, provider, source_uri)
);

-- The worker scans for due work by enabled flag; partial keeps it tiny.
create index focus_billing_sources_enabled_idx
  on focus_billing_sources (enabled) where enabled;
