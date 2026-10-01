-- Per-tx read cache for the reified subgraph page reader.
--
-- Each bundle download page was resolved by re-running the enrichment joins in
-- select_reifier_subgraph_page.sql against the per-connection TEMP _tx_log_slice
-- -- 7 materialized CTEs over the whole tx's ~180k transaction_logs rows -- on
-- every page request (each page is its own stateless request on a pooled
-- connection, so the TEMP slice and its derived CTEs could never be shared).
--
-- This table materializes that enrichment ONCE, when the subgraph is generated
-- (Sgs_bundler.generate_subgraph, in the preview dwork), so page reads become a
-- plain (tx_id, cursor_id) range scan with no _tx_log_slice and no CTEs.
--
-- Columns mirror Sgs_reifier.Subgraph_page.page_row exactly (same order as the
-- select_page read contract) so the row decoder is unchanged. [cursor_id] is
-- transaction_subgraphs.id verbatim, so the existing cursor semantics and
-- select_reifier_subgraph_cursors.sql keep working against transaction_subgraphs.
--
-- Lifetime: populated at generation; GC'd when the tx reaches a terminal state
-- (commit finalize / timeout / runtime failure) and cascaded on state
-- hard-delete. A cache miss is a clean ERROR (`Subgraph_cache_missing_err), not a
-- live rebuild: the live-enrichment fallback this migration originally described
-- was retired, and insert_reifier_subgraph_nodes.sql is now the only producer.
-- Migrations are not rewritten to match later behaviour as a rule, but a comment
-- that states the opposite of what the code does is worse than none.

create table transaction_subgraph_nodes (
  tx_id uuid not null references transactions (id),
  cursor_id bigint not null,
  state_id uuid not null references states (id),
  node_type text not null,
  item jsonb not null,
  depth int not null,
  direction text not null,
  boundary_inline jsonb,
  hcl_data jsonb,
  module_address text,
  module_source text,
  hcl_file_refs jsonb,
  tfvar_data jsonb,
  state_resource_json jsonb,
  state_output_json jsonb,
  file_json jsonb,
  state_path_attrs jsonb,
  resource_hcl jsonb not null,
  primary key (tx_id, cursor_id)
);

-- Cascade target for hard_delete_state.sql (deletes this table by state_id).
create index transaction_subgraph_nodes_state_id_idx
  on transaction_subgraph_nodes (state_id);

-- High-churn table: every tx bulk-inserts its whole subgraph (~10^5 wide rows,
-- file rows carry base64 content) and later bulk-deletes it on the tx's terminal
-- state. Default autovacuum (scale_factor 0.2) would let dead tuples and bloat
-- accumulate to a large fraction of a moving target before reclaiming. Pin the
-- scale factors to 0 and trigger on absolute row counts so vacuum reclaims dead
-- tuples (and analyze refreshes stats) promptly and independently of table size.
--
-- Query-plan risk from stale stats is low anyway: the page read is a
-- (tx_id, cursor_id) primary-key range scan with LIMIT, which the planner serves
-- from the PK index regardless of row-count estimates. This tuning is about
-- bounding physical bloat/space reuse, not plan quality.
alter table transaction_subgraph_nodes set (
  autovacuum_vacuum_scale_factor = 0.0,
  autovacuum_vacuum_threshold = 20000,
  autovacuum_vacuum_insert_scale_factor = 0.0,
  autovacuum_vacuum_insert_threshold = 20000,
  autovacuum_analyze_scale_factor = 0.0,
  autovacuum_analyze_threshold = 20000
);
