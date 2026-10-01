-- Per-user capabilities.  JSONB object keyed by capability name, matching the
-- shape consumed by Sgs_session_caps.Capabilities.  The default mirrors the
-- per-tenant default_user_caps default (see
-- 2026-06-11-add-tenants-default-user-caps.sql): access-token-create,
-- access-token-refresh, commit, and preview enabled.
alter table users
  add column if not exists capabilities jsonb not null default
    '{"access-token-create": true, "access-token-refresh": true, "commit": {}, "preview": {}}';

-- Backfill: users flagged is_admin get the 'admin' capability.
update users
set capabilities = capabilities || '{"admin": true}'::jsonb
where is_admin = true
  and capabilities->'admin' is null;

comment on column users.capabilities is
  'Capabilities granted to this user (JSONB capabilities object)';

-- Access tokens carry their own capabilities (a subset of their user's).  Fill
-- existing NULL rows with an empty object so the column can become NOT NULL, and
-- give the column a '{}' default for future inserts.
update access_tokens
set capabilities =
  '{"access-token-create": true, "access-token-refresh": true, "commit": {}, "preview": {}}'::jsonb
where capabilities is null;

alter table access_tokens
  alter column capabilities set default '{}',
  alter column capabilities set not null;

-- Backfill the same way as users above: grant the 'admin' capability to access
-- tokens belonging to admin users.
update access_tokens
set capabilities = capabilities || '{"admin": true}'::jsonb
where capabilities->'admin' is null
  and user_id in (select id from users where is_admin = true);
