create table transaction_previews (
  created_at timestamp with time zone not null default (now()),
  data jsonb not null,
  tx_id uuid primary key,
  foreign key (tx_id) references transactions (id)
);
