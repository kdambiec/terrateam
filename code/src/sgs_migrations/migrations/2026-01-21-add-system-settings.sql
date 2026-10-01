-- Simple key-value settings table for system configuration
create table system_settings (
    key text primary key,
    value jsonb not null,
    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone not null default now()
);
