-- Add a [module_] column to outputs, mirroring [resources.module_]: the module
-- path the output lives in.  This lets the reifier's remote-module state-subgraph
-- join (insert_reifier_state_subgraph.sql: remote_module_output_rows) match
-- outputs to a remote module block with a plain equi-join on the module path,
-- instead of the current O(remote_modules x outputs) prefix-LIKE cartesian
-- (o.address LIKE rmh.address || '.%').
--
-- Unlike resources -- whose module cannot be recovered from the address, because
-- the resource type is a variable segment (module.a.<type>.name) and so needs its
-- own column -- an output's address has a FIXED [output] segment:
--   module.<path>.output.<name>   (module output)   ->  module_ = module.<path>
--   output.<name>                 (root output)     ->  module_ = NULL
-- so the module is deterministically derivable from the address.  A STORED
-- generated column keeps [module_] in lockstep with [address] with no change to
-- the writer (update_state_apply_tx.sql does not list module_), and PostgreSQL
-- computes it for existing rows when the column is added.
--
-- Backwards compatible: the column is generated + nullable and the index is
-- partial; existing code that does not reference module_ is unaffected.
ALTER TABLE outputs
    ADD COLUMN module_ text
    GENERATED ALWAYS AS (
        CASE
            WHEN address LIKE 'output.%' THEN NULL
            ELSE regexp_replace(address, '\.output\.[^.]+$', '')
        END
    ) STORED;

-- Supports the module equi-join in remote_module_output_rows.  Partial because
-- today's committed outputs are root-only (module_ IS NULL), so the index is
-- empty now and grows only if child-module outputs are ever stored.
CREATE INDEX outputs_state_id_module_idx ON outputs (state_id, module_)
    WHERE module_ IS NOT NULL;
