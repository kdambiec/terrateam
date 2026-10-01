-- Client-computed hints for an HCL row: an extensible container (schema:
-- api_schemas/stategraph/tx_log_hints.json) for data the client derives from the
-- whole config (it has the resolver + scope) that the server's per-block view
-- cannot. The first kind is [path_attrs]: a canonical representation of a
-- path-bearing attribute whose ${path.*} anchor is reached through local/var
-- indirection, which Sg_path_attr.of_block (per-block, at tx-log time) misses.
-- Persisted so reification can consume it without re-deriving. Shape:
--   {"path_attrs": [{"attr": "filename", "canon": "<rendered canonical expr>"}, ...]}
-- Nullable: NULL for rows the client provided no hints for.
ALTER TABLE hcl ADD COLUMN hints jsonb;

-- Mirror the column on the per-tx reified-subgraph read cache
-- (transaction_subgraph_nodes): its columns track the reifier page read contract
-- (Sgs_reifier.Subgraph_page.page_row), so the page reader can carry hints
-- whether served from the cache or the live enrichment query. Nullable, same as
-- the source column.
ALTER TABLE transaction_subgraph_nodes ADD COLUMN hints jsonb;
