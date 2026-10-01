create table focus_billing (
  id                    bigint generated always as identity primary key,
  tenant_id             uuid not null,
  provider              text not null check (provider in ('aws', 'gcp', 'azure')),

  -- trailing-window key (FOCUS BillingPeriod*) + line-item time grain (ChargePeriod*)
  billing_period_start  timestamp with time zone not null,
  billing_period_end    timestamp with time zone,
  charge_period_start   timestamp with time zone not null,
  charge_period_end     timestamp with time zone,

  -- FOCUS cost measures
  billing_currency      text not null,
  billed_cost           numeric not null,
  effective_cost        numeric,
  list_cost             numeric,
  contracted_cost       numeric,

  -- charge classification
  charge_category       text,
  charge_class          text,
  charge_frequency      text,
  charge_description    text,

  -- provider / account identity
  provider_name         text,
  publisher_name        text,
  invoice_issuer_name   text,
  billing_account_id    text,
  sub_account_id        text,

  -- service / resource / region dimensions
  service_name          text,
  service_category      text,
  resource_id           text,
  resource_type         text,
  region_id             text,

  -- usage
  pricing_quantity      numeric,
  pricing_unit          text,
  consumed_quantity     numeric,
  consumed_unit         text,
  sku_id                text,

  tags                  jsonb,   -- normalized key/value tags
  focus_raw             jsonb,   -- full original FOCUS row; forward-compat escape hatch
  loaded_at             timestamp with time zone not null default (now()),

  foreign key (tenant_id) references tenants(id)
);

-- Serves per-(tenant, provider) rollup reads (tenant_id / provider are
-- denormalized for grouping without a join).  The idempotent reload DELETE is
-- keyed on source_id; see focus_billing_source_window_idx in
-- add-focus-billing-source-id.
create index focus_billing_window_idx
  on focus_billing (tenant_id, provider, billing_period_start);
