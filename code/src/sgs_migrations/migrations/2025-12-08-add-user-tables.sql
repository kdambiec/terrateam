create table user_types(
    id text primary key
);

insert into user_types(id) values
    ('user'),
    ('system'),
    ('api');

create table user_states(
    id text primary key
);

insert into user_states(id) values
    ('active');

create table users (
    created_at timestamp with time zone not null default (now()),
    email text,
    id uuid primary key default (gen_random_uuid()),
    name text not null,
    state text not null default 'active',
    type text not null default 'user',
    foreign key (type) references user_types(id),
    foreign key (state) references user_states(id)
);

-- Only allow one system users
create unique index users_system_type_idx on users(type)
    where type = 'system';

-- Create our system user
insert into users (name, type) values('HAL', 'system');

create table access_tokens (
    capabilities jsonb,
    created_at timestamp with time zone not null default (now()),
    expiration timestamp with time zone,
    id uuid default gen_random_uuid() primary key,
    name text not null,
    user_id uuid not null,
    foreign key (user_id) references users(id)
);

-- Which users are associated with a tenant
create table tenant_users (
    tenant_id uuid not null,
    user_id uuid not null,
    primary key (tenant_id, user_id),
    foreign key (tenant_id) references tenants(id),
    foreign key (user_id) references users(id)
);

-- Probably want to be doing reverse lookups quite a bit too
create index tenant_users_user_idx on tenant_users(user_id, tenant_id);

create table encryption_keys (
    created_at timestamp with time zone not null default (now()),
    data text not null default (encode(gen_random_bytes(64), 'hex')),
    rank integer primary key
);

insert into encryption_keys (rank) values(0);
