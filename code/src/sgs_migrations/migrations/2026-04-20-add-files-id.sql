-- Add `id` column to files for symmetry with hcl and tfvars (both keyed on
-- (state_id, id)). The id is derived from filepath following
-- Sg_node.Id.to_string ["file"; filepath], i.e.
--   'file.' || encode_fragment(filepath)
-- where encode_fragment replaces '%' with '%25' then '.' with '%2E'. Order
-- matters: '%' must be replaced first so that the '%' introduced by '%25'
-- is not touched by the '.' pass. See code/src/sg_node/sg_node.ml's
-- Id.encode_fragment / Id.to_string — this SQL must stay in sync with that
-- encoder.
--
-- This migration is backwards compatible: the existing (state_id, filepath)
-- primary key on `files` and the (state_id, filepath) FK from filepath_refs
-- are left intact. The new (state_id, id) unique index and filepath_refs.file_id
-- FK exist alongside them.
alter table files add column id text;

update files
set id = 'file.' || replace(replace(filepath, '%', '%25'), '.', '%2E');

alter table files alter column id set not null;

create unique index files_state_id_id_idx on files (state_id, id);

-- Mirror on filepath_refs so HCL nodes can link to files by id as well as
-- by filepath. The existing filepath FK stays in place for backwards compat.
alter table filepath_refs add column file_id text;

update filepath_refs
set file_id = 'file.' || replace(replace(filepath, '%', '%25'), '.', '%2E');

alter table filepath_refs alter column file_id set not null;

alter table filepath_refs
    add constraint filepath_refs_file_id_fkey
    foreign key (state_id, file_id) references files (state_id, id);

create index filepath_refs_state_id_file_id_idx on filepath_refs (state_id, file_id);

-- Ensure every file tx_log row carries `node_id` in its data. file_set rows
-- already include it (see sg_tx_builder.ml file_tagged_entry). file_delete
-- rows did not until the code change shipping with this migration; backfill
-- them here so the partial unique index below can be built.
update transaction_logs
set data = data || jsonb_build_object(
    'node_id',
    'file.' || replace(replace(data->>'filepath', '%', '%25'), '.', '%2E')
)
where object_type = 'file' and not (data ? 'node_id');

-- Partial unique index on node_id for file rows, matching the shape used by
-- hcl and tfvar. merge_revision_hashes.sql joins file tx_log rows on node_id
-- and depends on this index for performance.
create unique index transaction_logs_file_node_id_unique_idx
    on transaction_logs (tx_id, state_id, (data->>'node_id'))
    where object_type = 'file';
