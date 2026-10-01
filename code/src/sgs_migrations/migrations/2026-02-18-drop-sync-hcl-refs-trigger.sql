-- The sync_hcl_refs trigger maintained hcl_refs rows (local and remote)
-- on every hcl insert/update.  All hcl modifications go through
-- update_state_apply_tx.sql, so the ref syncing is now handled there
-- as explicit CTEs.  This avoids per-row trigger visibility issues
-- where bulk-inserted rows are not visible to each other's triggers.
drop trigger hcl_refs_sync on hcl;

drop function sync_hcl_refs()
