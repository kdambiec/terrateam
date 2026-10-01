-- hcl_refs uniqueness must include the state a remote ref points AT.
--
-- A consumer that reads two different remote states in one expression writes two
-- rows that differ only in [ref_state_id]:
--
--   * Sg_tf_references.address_of_reference maps both [outputs.foo] and
--     [outputs.foo.b] to "output.foo", so two producers exporting the same output
--     name share a [ref], and
--   * Sg_tf_references.attr_path_of_reference returns [] for every [outputs.*]
--     reference, so a whole read and a narrow read share an [attr_path] too.
--
-- [ref_state_id] was the only column left to tell them apart and it was not in the
-- key -- (state_id, id, ref, attr_path, from_depends_on), created as
-- [hcl_refs_new]'s primary key by Sgs_migrations_ex_685.  insert_remote_refs in
-- sql/update_state_apply_tx.sql inserts with [on conflict do nothing], so the
-- second row was dropped and which one survived followed jsonb_each ordering.
-- Everything that follows a cross-state edge through [ref_state_id] (the subgraph
-- walk, and sql/delete_state_prune_orphan_hcl_blast.sql) then stopped reaching
-- one of the two upstream states.
--
-- NULLS NOT DISTINCT is what keeps this ONE index rather than a pair of partial
-- ones: local refs carry a NULL [ref_state_id] and so keep exactly the uniqueness
-- they had, while remote refs are separated by their target state.  It requires
-- PostgreSQL 15; we run 17 (docker/stategraph/docker-compose-dev.yml).
--
-- The new index is strictly weaker than the primary key it replaces, so it cannot
-- fail to build on existing data.  It is created BEFORE the key is dropped so the
-- table is never left without a uniqueness guard.
create unique index concurrently if not exists hcl_refs_uniq_with_ref_state_idx
    on hcl_refs (state_id, id, ref, attr_path, from_depends_on, ref_state_id)
    nulls not distinct;

-- Sgs_migrations_ex_685 built the table as [hcl_refs_new] and renamed it into
-- place, and renaming a table does not rename its constraints, so the live name
-- of the key is [hcl_refs_new_pkey] -- confirmed by running every migration up
-- to this one against an empty PostgreSQL 17 database, where hcl_refs comes out
-- with exactly [hcl_refs_new_pkey] (primary key) and [hcl_refs_state_id_id_fkey]
-- (the foreign key ex_685 re-installs).
--
-- [hcl_refs_pkey] is the name the original table carried
-- (2026-02-04-add-hcl.sql), and ex_685 dropped that table outright.  Since
-- ex_685 is an unconditional entry in sgs_migrations.ml's ordered list, no
-- database can reach this migration still holding that name, and the second
-- statement is a no-op ("constraint does not exist, skipping") on every database
-- that migrated in order.  It stays as an IF EXISTS guard for an hcl_refs
-- rebuilt outside the migration chain, where tooling would regenerate the key
-- under the table's own name.  Those are the only two names the key has ever
-- had, so drop both by name rather than reaching into pg_constraint.
--
-- Nothing depends on the key being gone-or-present beyond uniqueness: no foreign
-- key targets hcl_refs (pg_constraint has no row with confrelid = hcl_refs), the
-- column NOT NULLs are declared on the columns and survive the drop, and the new
-- index leads with the dropped key's five columns in order, so index-only prefix
-- lookups keep the same access path.  insert_local_refs in
-- sql/update_state_apply_tx.sql already arbitrates on the six-column list, which
-- only this index can satisfy.
alter table hcl_refs drop constraint if exists hcl_refs_new_pkey;

alter table hcl_refs drop constraint if exists hcl_refs_pkey;
