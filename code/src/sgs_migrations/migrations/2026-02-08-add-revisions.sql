-- The revision representing the actual state as it is in the latest commit
create table revision_hashes (
  created_at timestamp with time zone not null default (now()),
  hash text not null,
  key text not null,
  state_id uuid not null,
  tx_id uuid not null,
  user_id uuid not null,
  primary key (state_id, key),
  foreign key (state_id) references states (id),
  foreign key (tx_id) references transactions (id),
  foreign key (user_id) references users (id)
);

-- Revisions as they exist for a particular tx
create table revision_tx_hashes (
  created_at timestamp with time zone not null default (now()),
  hash text not null,
  key text not null,
  state_id uuid not null,
  tx_id uuid not null,
  user_id uuid not null,
  primary key (tx_id, state_id, key),
  foreign key (state_id) references states (id),
  foreign key (tx_id) references transactions (id),
  foreign key (user_id) references users (id)
);
