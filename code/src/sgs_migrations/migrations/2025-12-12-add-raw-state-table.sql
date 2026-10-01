-- Raw binary content of states
create table raw_states (
    created_at timestamp with time zone not null default (now()),
    data bytea not null,
    idx integer not null,
    state_id uuid not null,
    tx_id uuid not null,
    primary key (state_id, idx),
    foreign key (state_id) references states(id),
    foreign key (tx_id) references transactions(id)
);
