-- Split the manual capability baseline out of users.capabilities.
--
-- base_capabilities is the manually-managed input (creation default, bootstrap admin, admin
-- toggles); users.capabilities becomes the materialized effective maximum, recomputed from
-- base_capabilities at each login. Additive and backwards-compatible: the default byte-matches the
-- existing capabilities default, and existing rows are backfilled so base == capabilities.
alter table users
  add column if not exists base_capabilities jsonb not null default
    '{"access-token-create": true, "access-token-refresh": true, "commit": {}, "preview": {}}';

update users set base_capabilities = capabilities;
