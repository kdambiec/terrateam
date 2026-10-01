-- Migrate module_address from nullable (NULL = root module) to NOT NULL with
-- '' as the root-module sentinel.
--
-- Why: PostgreSQL cannot use IS NOT DISTINCT FROM as a merge/hash join key, so
-- joins like (f.module_address IS NOT DISTINCT FROM v.module_address) fall
-- into a post-join Join Filter and force a Cartesian-shaped scan. EXPLAIN of
-- the cone iteration showed 65M rows being generated and discarded by exactly
-- this filter, costing ~22s of a 30s query. Switching to a non-null sentinel
-- promotes the equality into a real join key.
UPDATE hcl SET module_address = '' WHERE module_address IS NULL;

UPDATE files SET module_address = '' WHERE module_address IS NULL;

ALTER TABLE hcl ALTER COLUMN module_address SET DEFAULT '';

ALTER TABLE files ALTER COLUMN module_address SET DEFAULT '';

ALTER TABLE hcl ALTER COLUMN module_address SET NOT NULL;

ALTER TABLE files ALTER COLUMN module_address SET NOT NULL;
