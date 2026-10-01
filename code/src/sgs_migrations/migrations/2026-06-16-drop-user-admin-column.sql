-- Drop the users.is_admin column. Admin privileges are now expressed through
-- the per-user [capabilities] JSONB ('admin' capability), backfilled by
-- 2026-06-11-add-users-capabilities.sql, so the dedicated boolean column is no
-- longer needed.

drop index if exists users_is_admin_idx;

alter table users drop column if exists is_admin;
