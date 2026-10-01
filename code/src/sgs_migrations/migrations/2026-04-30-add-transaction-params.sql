alter table transactions
  add column params jsonb not null default '{}';
