-- Remove duplicate rows that would violate the unique indices below.  For each
-- object_type, keep only the most recently created row (tiebreaking on id) per
-- unique key group and delete the rest.
DELETE FROM transaction_logs
WHERE id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (
      PARTITION BY tx_id, state_id, data->>'node_id'
      ORDER BY created_at DESC, id DESC
    ) AS rn
    FROM transaction_logs
    WHERE object_type = 'hcl'
  ) dupes
  WHERE rn > 1
);

DELETE FROM transaction_logs
WHERE id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (
      PARTITION BY tx_id, state_id, data->>'address'
      ORDER BY created_at DESC, id DESC
    ) AS rn
    FROM transaction_logs
    WHERE object_type = 'resource'
  ) dupes
  WHERE rn > 1
);

DELETE FROM transaction_logs
WHERE id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (
      PARTITION BY tx_id, state_id, data->>'address'
      ORDER BY created_at DESC, id DESC
    ) AS rn
    FROM transaction_logs
    WHERE object_type = 'instance'
  ) dupes
  WHERE rn > 1
);

DELETE FROM transaction_logs
WHERE id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (
      PARTITION BY tx_id, state_id, data->>'name'
      ORDER BY created_at DESC, id DESC
    ) AS rn
    FROM transaction_logs
    WHERE object_type = 'output'
  ) dupes
  WHERE rn > 1
);

DELETE FROM transaction_logs
WHERE id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (
      PARTITION BY tx_id, state_id, data->>'name'
      ORDER BY created_at DESC, id DESC
    ) AS rn
    FROM transaction_logs
    WHERE object_type = 'provider'
  ) dupes
  WHERE rn > 1
);

DELETE FROM transaction_logs
WHERE id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (
      PARTITION BY tx_id, state_id
      ORDER BY created_at DESC, id DESC
    ) AS rn
    FROM transaction_logs
    WHERE object_type = 'state_metadata'
  ) dupes
  WHERE rn > 1
);

DELETE FROM transaction_logs
WHERE id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (
      PARTITION BY tx_id, state_id, data->>'config_addr'
      ORDER BY created_at DESC, id DESC
    ) AS rn
    FROM transaction_logs
    WHERE object_type = 'check_result'
  ) dupes
  WHERE rn > 1
);

DELETE FROM transaction_logs
WHERE id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (
      PARTITION BY tx_id, state_id, data->>'config_addr', data->>'object_addr'
      ORDER BY created_at DESC, id DESC
    ) AS rn
    FROM transaction_logs
    WHERE object_type = 'check_result_entry'
  ) dupes
  WHERE rn > 1
);

CREATE UNIQUE INDEX transaction_logs_hcl_unique_idx
  ON transaction_logs (tx_id, state_id, (data->>'node_id'))
  WHERE object_type = 'hcl';

CREATE UNIQUE INDEX transaction_logs_resource_unique_idx
  ON transaction_logs (tx_id, state_id, (data->>'address'))
  WHERE object_type = 'resource';

CREATE UNIQUE INDEX transaction_logs_instance_unique_idx
  ON transaction_logs (tx_id, state_id, (data->>'address'))
  WHERE object_type = 'instance';

CREATE UNIQUE INDEX transaction_logs_output_unique_idx
  ON transaction_logs (tx_id, state_id, (data->>'name'))
  WHERE object_type = 'output';

CREATE UNIQUE INDEX transaction_logs_provider_unique_idx
  ON transaction_logs (tx_id, state_id, (data->>'name'))
  WHERE object_type = 'provider';

CREATE UNIQUE INDEX transaction_logs_state_metadata_unique_idx
  ON transaction_logs (tx_id, state_id)
  WHERE object_type = 'state_metadata';

CREATE UNIQUE INDEX transaction_logs_check_result_unique_idx
  ON transaction_logs (tx_id, state_id, (data->>'config_addr'))
  WHERE object_type = 'check_result';

CREATE UNIQUE INDEX transaction_logs_check_result_entry_unique_idx
  ON transaction_logs (tx_id, state_id, (data->>'config_addr'), (data->>'object_addr'))
  WHERE object_type = 'check_result_entry'
