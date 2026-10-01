CREATE INDEX CONCURRENTLY IF NOT EXISTS instances_state_id_fq_resource_address_idx
  ON instances (state_id, fq_resource_address)
