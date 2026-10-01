-- Every row has its capability trie now: the columns were added, the backfill filled the rows that
-- existed, and every write since writes both columns.
--
-- Saying so in the schema is what keeps an unreadable row from being created at all. During a
-- rolling deploy an instance of the previous release still inserts rows knowing only the legacy
-- columns; without this, such a row would be created with no trie and would then fail to read.
-- With it, that insert fails instead, for as long as an instance of the previous release is still
-- serving. The window is the deploy itself, and a refused user creation is easier to understand
-- than a user that cannot be read afterwards.
alter table users alter column capability_trie set not null;

alter table users alter column base_capability_trie set not null;

alter table access_tokens alter column capability_trie set not null;

alter table caps_group_rules alter column capability_trie set not null;

-- And the legacy columns stop being written: a row created from here on has nothing to say in
-- them, so they lose the constraint and the default that would otherwise put a capability set
-- nobody granted into a row created after the change. What is in them is what was stored before
-- this migration ran, and nothing else.
alter table users alter column capabilities drop not null;

alter table users alter column capabilities drop default;

alter table users alter column base_capabilities drop not null;

alter table users alter column base_capabilities drop default;

alter table access_tokens alter column capabilities drop not null;

alter table access_tokens alter column capabilities drop default;

alter table caps_group_rules alter column capabilities drop not null;
