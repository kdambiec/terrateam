UPDATE transaction_subgraphs
SET node_type = 'tfvar'
WHERE node_type = 'hcl'
  AND (item->>'node_id') LIKE 'tfvar.%';
