-- Indexes supporting the index-free state<->HCL equality join on fq_address.
-- Created CONCURRENTLY (must run with ~mode:`Async outside the migration tx).
CREATE INDEX CONCURRENTLY IF NOT EXISTS resources_state_id_fq_address_idx
  ON resources (state_id, fq_address);

CREATE INDEX CONCURRENTLY IF NOT EXISTS instances_state_id_fq_address_idx
  ON instances (state_id, fq_address);
