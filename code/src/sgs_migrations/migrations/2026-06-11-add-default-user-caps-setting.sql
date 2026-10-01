-- System-wide default capabilities granted to users.  Users can belong to
-- multiple tenants, so this is a global setting (key 'default_user_caps' in
-- system_settings), not a per-tenant column.  JSONB object keyed by capability
-- name, matching the shape consumed by Sgs_session_caps.Capabilities.  The
-- default enables access-token-create, access-token-refresh, commit, and preview
-- (the bool caps are `true`; commit/preview are enabled as empty objects, i.e.
-- unscoped).
insert into system_settings (key, value)
values (
  'default_user_caps',
  '{"access-token-create": true, "access-token-refresh": true, "commit": {}, "preview": {}}'
)
on conflict (key) do nothing;
