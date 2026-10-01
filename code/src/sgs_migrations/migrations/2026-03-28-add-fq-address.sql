ALTER TABLE resources ADD COLUMN fq_address TEXT;

ALTER TABLE instances ADD COLUMN fq_address TEXT;

ALTER TABLE instances ADD COLUMN fq_resource_address TEXT;

UPDATE resources
SET fq_address = CASE
  WHEN mode = 'data' AND module_ IS NOT NULL AND module_ != ''
    THEN module_ || '.data.' || type || '.' || name
  WHEN mode = 'data'
    THEN 'data.' || type || '.' || name
  WHEN module_ IS NOT NULL AND module_ != ''
    THEN module_ || '.' || type || '.' || name
  ELSE type || '.' || name
END;

UPDATE instances AS i
SET
  fq_resource_address = r.fq_address,
  fq_address = CASE
    WHEN i.index_key IS NULL
      THEN r.fq_address
    WHEN jsonb_typeof(i.index_key) = 'number'
      THEN r.fq_address || '[' || (i.index_key#>>'{}') || ']'
    WHEN jsonb_typeof(i.index_key) = 'string'
      THEN r.fq_address || '["' || (i.index_key#>>'{}') || '"]'
    ELSE r.fq_address
  END
FROM resources AS r
WHERE i.state_id = r.state_id
  AND i.resource_address = r.address
  AND i.mode = r.mode;

ALTER TABLE resources ALTER COLUMN fq_address SET NOT NULL;

ALTER TABLE instances ALTER COLUMN fq_address SET NOT NULL;

ALTER TABLE instances ALTER COLUMN fq_resource_address SET NOT NULL;

ALTER TABLE instances DROP CONSTRAINT instances_state_id_resource_address_mode_fkey;

ALTER TABLE instances DROP CONSTRAINT instances_pkey;

ALTER TABLE resources DROP CONSTRAINT resources_pkey;

ALTER TABLE resources ADD PRIMARY KEY (state_id, fq_address);

ALTER TABLE instances ADD PRIMARY KEY (state_id, fq_address);

ALTER TABLE instances
  ADD CONSTRAINT instances_fq_resource_address_fkey
  FOREIGN KEY (state_id, fq_resource_address)
  REFERENCES resources(state_id, fq_address);

DROP INDEX IF EXISTS transaction_logs_resource_unique_idx;

CREATE UNIQUE INDEX transaction_logs_resource_unique_idx
  ON transaction_logs (tx_id, state_id, (data->>'fq_address'))
  WHERE object_type = 'resource';

DROP INDEX IF EXISTS transaction_logs_instance_unique_idx;

CREATE UNIQUE INDEX transaction_logs_instance_unique_idx
  ON transaction_logs (tx_id, state_id, (data->>'fq_address'))
  WHERE object_type = 'instance';
