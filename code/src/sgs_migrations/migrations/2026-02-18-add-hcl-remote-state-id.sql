alter table hcl
  add column remote_state_id uuid references states (id);
