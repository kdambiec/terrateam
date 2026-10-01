-- Speeds up the per-file module_source lookup in select_reifier_subgraph_page.sql.
-- The reifier dereferences (state_id, module_address) for each file node it
-- materializes; without this index that becomes a seq scan of hcl per file.
CREATE INDEX CONCURRENTLY IF NOT EXISTS hcl_state_id_module_address_module_source_idx
  ON hcl (state_id, module_address)
  WHERE module_source IS NOT NULL
