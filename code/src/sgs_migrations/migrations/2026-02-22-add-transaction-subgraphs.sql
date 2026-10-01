create table transaction_subgraphs (
  depth int not null,
  direction text not null,
  id bigint generated always as identity primary key,
  item jsonb not null,
  node_type text not null,
  state_id uuid not null references states (id),
  tx_id uuid not null references transactions (id)
);

create index transaction_subgraphs_tx_id_idx on transaction_subgraphs (tx_id);

create index transaction_subgraphs_tx_id_id_idx on transaction_subgraphs (tx_id, id)
