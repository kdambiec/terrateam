create table transaction_states (
    id text primary key
);

insert into transaction_states (id) values
    ('aborted'),
    ('open'),
    ('failed'),
    ('committed');

create table transactions (
    completed_at timestamp with time zone,
    completed_by uuid,
    created_at timestamp with time zone not null default (now()),
    created_by uuid not null,
    id uuid primary key default (gen_random_uuid()),
    state text not null,
    tags jsonb not null default ('{}'::jsonb),
    tenant_id uuid not null,
    foreign key (state) references transaction_states(id),
    foreign key (created_by) references users(id),
    foreign key (completed_by) references users(id),
    foreign key (tenant_id) references tenants(id),
    check ((state = 'open' and completed_at is null)
           or (state in ('aborted', 'failed', 'committed') and completed_at is not null))
);

create table transaction_log_actions (
    id text primary key
);

insert into transaction_log_actions (id) values
    ('state_set'),
    ('state_delete');

create table transaction_log_object_types (
    id text primary key
);

insert into transaction_log_object_types (id) values
    ('check_result'),
    ('check_result_entry'),
    ('instance'),
    ('output'),
    ('provider'),
    ('resource'),
    ('state_metadata');

create table transaction_logs (
    action text not null,
    created_at timestamp with time zone not null default (now()),
    data jsonb not null,
    id uuid primary key default (gen_random_uuid()),
    object_type text not null,
    state_id uuid not null,
    tx_id uuid not null,
    user_id uuid,
    foreign key (tx_id) references transactions(id),
    foreign key (action) references transaction_log_actions(id),
    foreign key (state_id) references states(id),
    foreign key (object_type) references transaction_log_object_types(id),
    foreign key (user_id) references users(id)
);
