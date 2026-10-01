-- Restore the three partial hcl_refs indexes lost in the hcl-refs
-- structured-edges rebuild (Sgs_migrations_ex_685).  That migration does
-- `drop table hcl_refs cascade` then recreates the table, but only
-- re-installs the primary key, the foreign key, and hcl_refs_state_ref_idx.
-- The three partial ref_state_id indexes below were silently dropped with
-- the old table, which forces the cross-state branches of the orphan-prune
-- blast traversal and the cone CTEs onto far slower index paths.
--
-- This is a NEW migration; the original index migrations and the
-- structured-edges migration are left untouched.  CREATE INDEX CONCURRENTLY
-- must run outside the migration transaction, so this is registered with
-- ~mode:`Async in sgs_migrations.ml.

-- Cross-state ref following: delete_state_prune_orphan_hcl_blast.sql
-- clauses 3 & 4 (hr.ref_state_id = t.state_id and hr.ref = t.fq_address).
-- Originally from 2026-02-20-add-reifier-performance-indexes.sql.
create index concurrently if not exists hcl_refs_ref_state_id_ref_idx
    on hcl_refs (ref_state_id, ref)
    where ref_state_id is not null;

-- Cross-state cone lookups by (state_id, id).
-- Originally from 2026-02-22-add-hcl-refs-cone-index.sql.
create index concurrently if not exists hcl_refs_state_id_id_ref_state_idx
    on hcl_refs (state_id, id)
    where ref_state_id is not null;

-- Same-state ref following in the cone CTE's same_committed_hcl_refs.
-- Originally from 2026-04-30-add-hcl-refs-same-state-idx.sql.
create index concurrently if not exists hcl_refs_same_state_state_id_id_idx
    on hcl_refs (state_id, id)
    where ref_state_id is null;
