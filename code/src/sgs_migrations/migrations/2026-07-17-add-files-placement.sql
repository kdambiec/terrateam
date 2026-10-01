-- Add the reified canon placement of an escaping file read to the files table.
--
-- An escaping read (a file whose resolved path leaves the repo, directly or via
-- variables/loops/module inputs) is reified to
-- ${path.root}/state_<prefix>/<placement_dir>/<placement_basename>, where
-- placement_dir is the md5 of the read's location-independent canonical path and
-- placement_basename is its basename (see Sg_tf_eval_canon). These are computed at
-- collection and must survive on the committed files table because reification also
-- runs from committed state (the tofu-oracle re-plan after apply).
--
-- Backwards-compatible: both columns are nullable and NULL for non-escaping reads
-- (which keep the structure-preserving reified placement). A file collected before
-- this migration has NULL placement and is re-collected on the next import.
alter table files
    add column placement_dir text,
    add column placement_basename text;
