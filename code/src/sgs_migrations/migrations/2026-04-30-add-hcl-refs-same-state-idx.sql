-- Partial index supporting same-state ref following in
-- insert_reifier_hcl_subgraph_cone.sql's same_committed_hcl_refs CTE,
-- which joins (state_id, id) and filters ref_state_id IS NULL.  Without
-- it the planner seq-scans all of hcl_refs and disk-sorts the result
-- (~20MB external merge per cone iteration).
-- Created CONCURRENTLY (must run with ~mode:`Async outside the migration tx).
CREATE INDEX CONCURRENTLY IF NOT EXISTS hcl_refs_same_state_state_id_id_idx
  ON hcl_refs (state_id, id)
  WHERE ref_state_id IS NULL
