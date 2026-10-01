-- Group-rules: admin-managed rules mapping IdP group conditions to capability grants.  One row per
-- rule; edits are supersedes and deletes are soft (deleted_at) so a database snapshot reconstructs
-- the full history.  Evaluation reads only alive rows; the result is a union, so rule order is
-- irrelevant (no ordinal column).  Additive (new table) => backwards-compatible.
create table if not exists caps_group_rules (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  created_by uuid not null references users (id),
  deleted_at timestamptz,
  description text,
  condition jsonb not null,
  capabilities jsonb not null
);

create index if not exists caps_group_rules_alive_idx
  on caps_group_rules (created_at)
  where deleted_at is null;
