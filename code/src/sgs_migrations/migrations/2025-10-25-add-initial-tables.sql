create extension if not exists pgcrypto;

-- This SQL schema is based on the JSON schema for Terraform state files.
-- It uses PostgreSQL-specific types like JSONB and TEXT[].

-- A table for tenants. Each state belongs to exactly one tenant.
CREATE TABLE tenants (
    created_at timestamp with time zone not null default (now()),
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL
);

-- The states table defines all of the states that exist in the system.  There
-- are two IDs.
--
-- 1. Group ID - The ID for this state that all workspaces are under.  This is
-- the ID that Terraform backends will use so that they can reference other
-- workspaces underneath it.
--
-- 2. ID - This is the ID for the specific state.  This is an ID that
-- corresponds to the tuple (group_id, workspace).
--
-- It is done via two IDs so that we don't have to carry the tuple (state_id,
-- workspace) everywhere in the system.
create table states (
    created_at timestamp with time zone not null default (now()),
    group_id uuid not null default (gen_random_uuid()),
    id uuid primary key default (gen_random_uuid()),
    name text not null,
    tenant_id uuid not null,
    updated_at timestamp with time zone not null default (now()),
    workspace text not null default ('default'),
    foreign key (tenant_id) references tenants(id),
    unique (group_id, workspace),
    unique (tenant_id, name)
);

create index states_group_id_workspace_idx on states(group_id, workspace);

-- This contains state metadata.  It is separated out from states so that we can
-- create an empty state separate from filling it in with data.
CREATE TABLE states_metadata (
    id uuid primary key,
    lineage text not null,
    serial integer not null,
    terraform_version text not null,
    version integer not null,
    foreign key (id) references states(id)
);

-- A table for 'outputs' objects. Each output belongs to a state.
CREATE TABLE outputs (
    name TEXT NOT NULL, -- JSON key in the object in the enclosing state
    sensitive BOOLEAN,
    state_id UUID NOT NULL,
    type JSONB NOT NULL,
    value JSONB NOT NULL,
    PRIMARY KEY (state_id, name),
    foreign key (state_id) references states(id)
);

-- A table for providers
CREATE TABLE providers (
    name text not null,
    state_id uuid not null,
    primary key (state_id, name),
    foreign key (state_id) references states(id)
);

-- A table for 'resource' objects. Each resource belongs to a state.
create table resources (
    address text not null,
    mode text not null check (mode in ('managed', 'data')),
    module_ text,
    name text not null,
    provider text not null,
    state_id uuid not null,
    type text not null,
    primary key (state_id, address),
    foreign key (state_id) references states(id),
    foreign key (state_id, provider) references providers(state_id, name)
);

-- A table for 'instance' objects. Each instance belongs to a resource and comes from the 'instances' array.
create table instances (
    address text not null,
    attributes jsonb,
    create_before_destroy boolean,
    dependencies text[],
    deposed text,
    identity jsonb,
    identity_schema_version integer,
    index_key text, -- 'index_key' can be a string or an integer, so we use TEXT.
    private text,
    resource_address text not null,
    schema_version integer not null,
    sensitive_attributes jsonb,
    state_id uuid not null,
    status text,
    primary key (state_id, address),
    foreign key (state_id) references states(id),
    foreign key (state_id, resource_address) references resources(state_id, address)
);

-- A table for 'check_results' objects. Each check_result belongs to a state.
CREATE TABLE check_results (
    config_addr text not null,
    object_kind text not null,
    state_id uuid not null,
    status text not null,
    primary key (state_id, config_addr),
    foreign key (state_id) references states(id)
);

-- A table for 'check' objects (not named 'check' because it is a keyword). Each object belongs to a 'check_results'.
CREATE TABLE check_entries (
    config_addr text not null,
    failure_messages text[],
    object_addr text not null,
    state_id uuid not null,
    status text not null,
    primary key (state_id, config_addr, object_addr),
    foreign key (state_id, config_addr) references check_results(state_id, config_addr),
    foreign key (state_id) references states(id)
);
