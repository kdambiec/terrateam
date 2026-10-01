create table dwork_states (id text primary key);

insert into dwork_states (id) values
  ('waiting'), ('running'), ('timedout'), ('failed'), ('completed');

create table dworks (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  name text not null,
  params jsonb not null default ('{}'::jsonb),
  state text not null default ('waiting'),
  exec_timeout_at timestamp with time zone not null,
  idle_timeout_ns bigint not null,
  wakeup_at timestamp with time zone,
  created_at timestamp with time zone not null default (now()),
  last_run_at timestamp with time zone not null default (now()),
  foreign key (state) references dwork_states (id)
);

create index dworks_kind_idx on dworks (kind);

create index dworks_ready_idx on dworks (wakeup_at) where state = 'waiting';

create table dwork_ops (
  workflow_id uuid not null,
  op_id text not null,
  data jsonb not null,
  created_at timestamp with time zone not null default (now()),
  primary key (workflow_id, op_id),
  foreign key (workflow_id) references dworks (id) on delete cascade
);

create table dwork_msgs (
  workflow_id uuid not null,
  seq bigint generated always as identity,
  token bytea not null,
  data jsonb not null,
  created_at timestamp with time zone not null default (now()),
  primary key (workflow_id, seq),
  unique (workflow_id, token),
  foreign key (workflow_id) references dworks (id) on delete cascade
);
