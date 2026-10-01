-- Widen the [files] uniqueness from (state_id, filepath) to (state_id, id)
-- where id = Sg_node.Id.of_file ?module_address filepath, i.e.
--   'file.' || encode_fragment(module_address or '') || '.' || encode_fragment(filepath)
--
-- The old schema had a primary key on (state_id, filepath) and a
-- unique (state_id, id) index where id was derived from filepath alone.
-- When two instances of the same child module referenced the same file
-- (e.g. two modules sourced from '../modules/shared' each calling
-- file("${path.module}/shared.yaml")), both instances computed the same
-- filepath string and therefore the same node id — and the primary key
-- collapsed them into a single row, losing the second module_address.
--
-- We intentionally do NOT backfill existing rows.  Operators running
-- this migration must re-import affected states to repopulate the
-- files table with per-module rows.
--
-- Statements are separated by a blank line so [run_sql] in
-- sgs_migrations.ml can split them (it splits on ";\n\n").

-- Drop the filepath-based FK from filepath_refs so filepath no longer
-- needs to be unique in files.
alter table filepath_refs drop constraint filepath_refs_state_id_filepath_fkey;

-- Drop the old (state_id, filepath) PK.
alter table files drop constraint files_pkey;

-- Promote the existing (state_id, id) unique index to be the primary key.
-- [USING INDEX] converts the index in place so the filepath_refs_file_id_fkey
-- foreign key — which references this unique index — continues to be
-- satisfied throughout the migration.
alter table files add primary key using index files_state_id_id_idx;

-- Lookup index so cone SQL can find files by (module_address, filepath)
-- without recomputing the id string in SQL.  Non-unique — uniqueness is
-- enforced by the PK on (state_id, id) — which sidesteps the NULL-handling
-- pain of unique-with-NULL.
create index files_state_id_module_address_filepath_idx
    on files (state_id, module_address, filepath);
