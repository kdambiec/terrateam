-- The 'admin' capability changed from a bare boolean to a tenant-scoped object, the
-- same shape as 'users-manage': an object with no 'tenants' array is administrative
-- authority over the whole installation, a 'tenants' allow-list restricts it.
--
-- Rewrite the stored booleans so existing admins keep exactly the access they have
-- today: '{"admin": true}' becomes '{"admin": {}}' (installation-wide), and
-- '{"admin": false}' -- which granted nothing -- drops the key.

update users
set capabilities = jsonb_set(capabilities, '{admin}', '{}'::jsonb, true)
where capabilities -> 'admin' = 'true'::jsonb;

update users
set capabilities = capabilities - 'admin'
where capabilities -> 'admin' = 'false'::jsonb;

update access_tokens
set capabilities = jsonb_set(capabilities, '{admin}', '{}'::jsonb, true)
where capabilities -> 'admin' = 'true'::jsonb;

update access_tokens
set capabilities = capabilities - 'admin'
where capabilities -> 'admin' = 'false'::jsonb;

update system_settings
set value = jsonb_set(value, '{admin}', '{}'::jsonb, true)
where key = 'default_user_caps'
  and value -> 'admin' = 'true'::jsonb;

update system_settings
set value = value - 'admin'
where key = 'default_user_caps'
  and value -> 'admin' = 'false'::jsonb;
