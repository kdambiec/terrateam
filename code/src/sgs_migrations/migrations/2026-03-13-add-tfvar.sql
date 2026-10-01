create table tfvars (
    state_id uuid not null references states(id),
    id text not null,
    var_address text not null,
    file text not null,
    data jsonb not null,
    primary key (state_id, id)
);

create unique index tfvars_state_id_var_address_idx on tfvars (state_id, var_address);

insert into transaction_log_actions (id) values ('tfvar_set');

insert into transaction_log_actions (id) values ('tfvar_delete');

insert into transaction_log_object_types (id) values ('tfvar')
