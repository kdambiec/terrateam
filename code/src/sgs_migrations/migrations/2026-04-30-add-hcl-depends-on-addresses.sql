alter table hcl
  add column depends_on_addresses text[] not null default '{}';
