create index transaction_logs_tx_id_action_object_type_idx
  on transaction_logs (tx_id, action, object_type);
