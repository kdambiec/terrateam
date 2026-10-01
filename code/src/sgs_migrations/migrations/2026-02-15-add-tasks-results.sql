create table task_results (
  data jsonb not null,
  task_id uuid not null,
  primary key (task_id),
  foreign key (task_id) references tasks (id)
);
