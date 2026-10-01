-- RFD 584: the transaction log entry a plan appends when the configuration has
-- not changed.  [sgs_refresh_gate.mli] states why such a plan now opens a
-- transaction at all, and what the server does with the entry.
--
-- transaction_logs.action and .object_type both have foreign keys to their
-- lookup tables, so both ids must exist before any client can append the entry.
--
-- Additive: no existing row changes and no column is rewritten, so an older
-- server keeps working against a migrated database.
--
-- The object_type is its own id rather than a reused one.  Every reader of
-- transaction_logs names the object types it wants -- the walk's seed takes
-- 'hcl', 'tfvar' and 'file' (subgraph2/tx_staged.sql, filtered by
-- Sgs_reifier_subgraph2_anchors), the state side takes 'instance' and
-- 'resource' -- so a type none of them names is invisible to all of them.  That
-- is the property this entry needs: it marks that a transaction exists, and it
-- must seed nothing.
insert into transaction_log_actions (id) values ('refresh');

insert into transaction_log_object_types (id) values ('refresh');

-- Dedupe key for the refresh upsert, keyed like the state_metadata one.  The
-- entry says "this transaction wants state X's data sources refreshed", which
-- is a fact about the pair alone, so there is one row per (tx_id, state_id) and
-- a resent plan updates it rather than appending.
create unique index transaction_logs_refresh_unique_idx
    on transaction_logs (tx_id, state_id)
    where object_type = 'refresh'
