-- Boundary-inline column populated by the reifier subgraph walk.  When set,
-- holds a JSON map from referenced boundary addresses (e.g.
-- "terraform_data.b") to the slice of state attributes the row's HCL needs in
-- order to be rewritten as inline literals at page-render time.  Null for
-- rows that do not need inlining.  Backwards-compatible: existing readers
-- ignore the column.
alter table transaction_subgraphs
  add column boundary_inline jsonb
