-- Add is_admin column for admin privileges
alter table users add column if not exists is_admin boolean not null default false;

-- Index for fast admin lookups
create index if not exists users_is_admin_idx on users (is_admin)
    where is_admin = true;

-- Make the first user (if exists) an admin
update users
set is_admin = true
where type = 'user'
  and id = (
    select id from users
    where type = 'user'
    order by created_at
    limit 1
  );

comment on column users.is_admin is 'Whether user has administrative privileges';
