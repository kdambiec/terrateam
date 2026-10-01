-- Storage for the run-detail (tx detail) endpoint: the per-resource plan
-- operations and the tx -> apply-task link.

-- Per-resource plan operations, persisted at preview-finalize from the
-- demangled plan JSON (see Sgs_plan_operations). Instance-level and immutable:
-- a historical run's operations never drift as the current resources table
-- moves on. Powers the run-detail plan tree and the "N to add, M to change,
-- K to destroy" summaries on the tx list and detail endpoints. Rows are
-- delete-then-inserted per preview, so a re-plan always reflects the latest
-- plan. Transactions predating this table (or that never planned, e.g.
-- bulk-apply/import) have no rows and show no operations.
create table transaction_plan_operations (
  tx_id uuid not null,
  address text not null,
  operation text not null check (operation in ('create', 'update', 'replace', 'destroy')),
  primary key (tx_id, address),
  foreign key (tx_id) references transactions (id)
);

-- Links a transaction to the generic task that ran its apply (tofu apply) so
-- the Apply tab can resolve tx -> apply task -> the captured apply stdout
-- (which the commit workflow stores at idx=0 in that task's task_results).
--
-- A plain nullable column rather than a link table: at most one apply task
-- ever exists per tx (a re-commit overwrites the link), and holding it on the
-- transaction side keeps the generic tasks table agnostic of what it runs.
alter table transactions
  add column apply_task_id uuid references tasks (id) on delete set null;
