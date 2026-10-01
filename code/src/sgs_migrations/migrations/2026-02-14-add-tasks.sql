create table task_states (
  id text primary key
);

insert into task_states (id) values
  ('aborted'),
  ('completed'),
  ('failed'),
  ('pending'),
  ('running');

create table tasks (
  id uuid not null default (gen_random_uuid()),
  state text not null,
  primary key (id),
  foreign key (state) references task_states (id)
);
