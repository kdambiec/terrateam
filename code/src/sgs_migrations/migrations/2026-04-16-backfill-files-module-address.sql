-- Backfill files.module_address for rows that predate the Step 2 write-path change.
--
-- Source of truth: filepath_refs joined to hcl. A file row reflects a file referenced by one or
-- more HCL nodes; each node carries its owning module's address. We pick the lexicographically
-- smallest non-NULL module_address for a deterministic choice when a file is referenced by
-- multiple modules. NULL (root module) is only picked if no child module references the file.
--
-- This migration is idempotent via the [module_address IS NULL] guard: re-running it leaves
-- already-populated rows alone and does not overwrite values written by the tx_log materializer.
UPDATE files
SET module_address = sub.module_address
FROM (
    SELECT DISTINCT ON (fr.state_id, fr.filepath)
        fr.state_id,
        fr.filepath,
        h.module_address
    FROM filepath_refs fr
    JOIN hcl h ON h.state_id = fr.state_id AND h.id = fr.id
    ORDER BY fr.state_id, fr.filepath, h.module_address NULLS LAST
) sub
WHERE files.state_id = sub.state_id
  AND files.filepath = sub.filepath
  AND files.module_address IS NULL;
