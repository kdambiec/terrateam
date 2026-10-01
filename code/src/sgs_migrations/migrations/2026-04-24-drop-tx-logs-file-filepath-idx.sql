-- Drop the transaction_logs filepath-based unique index for file rows.
--
-- With Sg_node.Id.of_file now encoding module_address into file node
-- ids, two file tx-log entries can legitimately share a filepath string
-- while carrying distinct node_ids (one per module instance).  The
-- node_id-based unique index added in migration 2026-04-20-add-files-id
-- remains as the forward-facing uniqueness contract; the older
-- filepath-based index would reject the second tx-log entry as a
-- duplicate and must be removed.

drop index transaction_logs_file_unique_idx;
