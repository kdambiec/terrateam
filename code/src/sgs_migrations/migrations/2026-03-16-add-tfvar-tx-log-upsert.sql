CREATE UNIQUE INDEX transaction_logs_tfvar_unique_idx
  ON transaction_logs (tx_id, state_id, (data->>'node_id'))
  WHERE object_type = 'tfvar';

CREATE OR REPLACE FUNCTION upsert_tx_logs_from_tmp() RETURNS void AS $$
BEGIN
  -- hcl
  INSERT INTO transaction_logs (tx_id, state_id, action, data, object_type, user_id)
  SELECT tx_id, state_id, action, data, object_type, user_id
  FROM tmp_tx_logs WHERE object_type = 'hcl'
  ON CONFLICT (tx_id, state_id, (data->>'node_id')) WHERE object_type = 'hcl'
  DO UPDATE SET action = EXCLUDED.action, data = EXCLUDED.data, user_id = EXCLUDED.user_id;
  -- tfvar
  INSERT INTO transaction_logs (tx_id, state_id, action, data, object_type, user_id)
  SELECT tx_id, state_id, action, data, object_type, user_id
  FROM tmp_tx_logs WHERE object_type = 'tfvar'
  ON CONFLICT (tx_id, state_id, (data->>'node_id')) WHERE object_type = 'tfvar'
  DO UPDATE SET action = EXCLUDED.action, data = EXCLUDED.data, user_id = EXCLUDED.user_id;
  -- resource
  INSERT INTO transaction_logs (tx_id, state_id, action, data, object_type, user_id)
  SELECT tx_id, state_id, action, data, object_type, user_id
  FROM tmp_tx_logs WHERE object_type = 'resource'
  ON CONFLICT (tx_id, state_id, (data->>'address')) WHERE object_type = 'resource'
  DO UPDATE SET action = EXCLUDED.action, data = EXCLUDED.data, user_id = EXCLUDED.user_id;
  -- instance
  INSERT INTO transaction_logs (tx_id, state_id, action, data, object_type, user_id)
  SELECT tx_id, state_id, action, data, object_type, user_id
  FROM tmp_tx_logs WHERE object_type = 'instance'
  ON CONFLICT (tx_id, state_id, (data->>'address')) WHERE object_type = 'instance'
  DO UPDATE SET action = EXCLUDED.action, data = EXCLUDED.data, user_id = EXCLUDED.user_id;
  -- output
  INSERT INTO transaction_logs (tx_id, state_id, action, data, object_type, user_id)
  SELECT tx_id, state_id, action, data, object_type, user_id
  FROM tmp_tx_logs WHERE object_type = 'output'
  ON CONFLICT (tx_id, state_id, (data->>'name')) WHERE object_type = 'output'
  DO UPDATE SET action = EXCLUDED.action, data = EXCLUDED.data, user_id = EXCLUDED.user_id;
  -- provider
  INSERT INTO transaction_logs (tx_id, state_id, action, data, object_type, user_id)
  SELECT tx_id, state_id, action, data, object_type, user_id
  FROM tmp_tx_logs WHERE object_type = 'provider'
  ON CONFLICT (tx_id, state_id, (data->>'name')) WHERE object_type = 'provider'
  DO UPDATE SET action = EXCLUDED.action, data = EXCLUDED.data, user_id = EXCLUDED.user_id;
  -- state_metadata
  INSERT INTO transaction_logs (tx_id, state_id, action, data, object_type, user_id)
  SELECT tx_id, state_id, action, data, object_type, user_id
  FROM tmp_tx_logs WHERE object_type = 'state_metadata'
  ON CONFLICT (tx_id, state_id) WHERE object_type = 'state_metadata'
  DO UPDATE SET action = EXCLUDED.action, data = EXCLUDED.data, user_id = EXCLUDED.user_id;
  -- check_result
  INSERT INTO transaction_logs (tx_id, state_id, action, data, object_type, user_id)
  SELECT tx_id, state_id, action, data, object_type, user_id
  FROM tmp_tx_logs WHERE object_type = 'check_result'
  ON CONFLICT (tx_id, state_id, (data->>'config_addr')) WHERE object_type = 'check_result'
  DO UPDATE SET action = EXCLUDED.action, data = EXCLUDED.data, user_id = EXCLUDED.user_id;
  -- check_result_entry
  INSERT INTO transaction_logs (tx_id, state_id, action, data, object_type, user_id)
  SELECT tx_id, state_id, action, data, object_type, user_id
  FROM tmp_tx_logs WHERE object_type = 'check_result_entry'
  ON CONFLICT (tx_id, state_id, (data->>'config_addr'), (data->>'object_addr'))
    WHERE object_type = 'check_result_entry'
  DO UPDATE SET action = EXCLUDED.action, data = EXCLUDED.data, user_id = EXCLUDED.user_id;
END;
$$ LANGUAGE plpgsql;
