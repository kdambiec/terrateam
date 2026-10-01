-- The capability columns in the decision-tree shape
-- (api_schemas/stategraph/capability-wire.json), next to the legacy columns they replace.
--
-- Nullable only until the rows have one: the backfill that follows
-- (Sgs_migrations_ex_capability_trie) fills every row that exists, and the migration after it makes
-- the columns not null. Read the three as one step.
--
-- The legacy columns are frozen from here on: the release that reads these stops writing them, and
-- they stay as the record of what was stored before the change. They are dropped at the next major
-- release.
alter table users add column if not exists capability_trie jsonb;

alter table users add column if not exists base_capability_trie jsonb;

alter table access_tokens add column if not exists capability_trie jsonb;

alter table caps_group_rules add column if not exists capability_trie jsonb;

comment on column users.capability_trie is
  'Capabilities granted to this user; see api_schemas/stategraph/capability-wire.json';

comment on column users.base_capability_trie is
  'The manually managed baseline this user''s capabilities are recomputed from; see api_schemas/stategraph/capability-wire.json';

comment on column access_tokens.capability_trie is
  'Capabilities of this access token; see api_schemas/stategraph/capability-wire.json';

comment on column caps_group_rules.capability_trie is
  'Capabilities this rule grants; see api_schemas/stategraph/capability-wire.json';
