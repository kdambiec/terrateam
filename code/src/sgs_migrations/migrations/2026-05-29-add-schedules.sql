create table schedules (
    id uuid primary key default gen_random_uuid(),
    last_run_at timestamp with time zone not null default now(),
    schedule text not null check (schedule in ('minutely', 'hourly', 'daily', 'weekly', 'monthly')),
    kind text not null,
    data jsonb not null default '{}'::jsonb
);

create index schedules_last_run_at_idx on schedules (last_run_at);
