-- Drop the reified canon placement of an escaping file read from the files table.
--
-- These columns named a staging bucket, state_<prefix>/<placement_dir>/<placement_basename>, that
-- the reified read located by having tofu recompute md5(canon)/basename(canon) at plan time. That
-- rewrite is gone: the reifier now emits the bundle path as a literal, so the location no longer has
-- to be expressible in tofu's function vocabulary, and Sg_bundle_paths.classify derives it on both
-- the staging and the read side from (module_source, module_address, filepath) -- all three present
-- on the file row and on the HCL ref alike. One derivation, nothing to store.
--
-- Safe unconditionally: both columns are nullable with no index, constraint or view depending on
-- them, and nothing has read them since the rewrite was retired. No backfill, no table rewrite.
alter table files
    drop column placement_dir,
    drop column placement_basename;
