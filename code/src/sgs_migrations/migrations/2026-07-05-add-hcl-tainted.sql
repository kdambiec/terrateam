-- Tracks HCL entries that must be treated as changed on every plan until a
-- transaction that includes them commits successfully.  Populated when an apply
-- fails after committing (failed-committed): the failed transaction's own
-- seed+blast HCL nodes are tainted so the operator is forced to re-plan them,
-- since a partial apply may have left real infrastructure inconsistent with the
-- state we wrote back.  Cleared per-node on the next successful commit that
-- applies the node.  The cascading FK keeps taint rows in step with their HCL
-- entries (an entry deleted by a later commit takes its taint row with it).
create table hcl_tainted (
  state_id uuid not null,
  id text not null,
  created_at timestamp with time zone not null default (now()),
  primary key (state_id, id),
  foreign key (state_id, id) references hcl (state_id, id) on delete cascade
);
