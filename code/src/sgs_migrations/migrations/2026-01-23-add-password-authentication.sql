-- Add password hash column for local auth users
alter table users add column if not exists password_hash text;

-- Index for email lookups during login
create index if not exists users_email_idx on users (email)
    where email is not null;

-- Constraint: users must have either OAuth OR password auth
alter table users add constraint users_auth_method_check
    check (type <> 'user' or (type = 'user' and (auth_origin is null or password_hash is null)));
