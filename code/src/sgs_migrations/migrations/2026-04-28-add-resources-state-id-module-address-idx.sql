CREATE INDEX CONCURRENTLY IF NOT EXISTS resources_state_id_module_address_idx
  ON resources (state_id, ((coalesce(module_ || '.', '') || address)))
