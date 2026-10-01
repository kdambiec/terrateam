-- Re-shape resources/instances address columns so the HCL-template form
-- (no module-path index keys, no leaf [key]) lives on its own column and
-- can be joined to hcl.fq_address with plain equality.
--
-- Prior layout:
--   resources(address text NOT NULL,        -- type.name (no module prefix)
--             fq_address text NOT NULL,     -- module-path + type.name, with module-path indices, PK
--             ...)
--   instances(address text NOT NULL,        -- type.name + leaf [key]
--             resource_address text NOT NULL, -- type.name (no module prefix)
--             fq_address text NOT NULL,     -- full unique address, PK
--             fq_resource_address text NOT NULL, -- module-path + type.name, with module-path indices
--             ...)
--
-- New layout:
--   resources(address text NOT NULL,        -- was fq_address (full, w/ module-path indices), PK
--             fq_address text NOT NULL,     -- HCL-shape: module-path + type.name, NO indices anywhere
--             ...)
--   instances(address text NOT NULL,        -- was fq_address (full, w/ all indices), PK
--             resource_address text NOT NULL, -- was fq_resource_address (full, w/ module-path indices)
--             fq_address text NOT NULL,     -- HCL-shape: module-path + type.name, NO indices anywhere
--             ...)
--
-- The new fq_address columns are backfilled in this migration by stripping
-- index keys ('[...]') from the existing fq_address / fq_resource_address.
-- That expression is exactly the one the original (pre-nwvnknsv) reifier
-- join used at query time, so the resulting fq_address values match the
-- HCL-shaped form the post-fix code will write.

-- Drop the buggy expression index from commit nwvnknsv: it depends on the
-- soon-to-be-dropped resources.address column.
DROP INDEX IF EXISTS resources_state_id_module_address_idx;

-- Drop the FK that references the column we're about to rename.
ALTER TABLE instances DROP CONSTRAINT instances_fq_resource_address_fkey;

-- Resources: drop legacy short address.
ALTER TABLE resources DROP COLUMN address;

-- Promote fq_address -> address.
ALTER TABLE resources RENAME COLUMN fq_address TO address;

-- Add the new HCL-shape fq_address column.
ALTER TABLE resources ADD COLUMN fq_address TEXT;

UPDATE resources
SET fq_address = regexp_replace(address, '\[[^\]]*\]', '', 'g');

ALTER TABLE resources ALTER COLUMN fq_address SET NOT NULL;

-- Instances: drop legacy short forms.
ALTER TABLE instances DROP COLUMN address;

ALTER TABLE instances DROP COLUMN resource_address;

-- Promote fq_address -> address.
ALTER TABLE instances RENAME COLUMN fq_address TO address;

-- Promote fq_resource_address -> resource_address.
ALTER TABLE instances RENAME COLUMN fq_resource_address TO resource_address;

-- Add the new HCL-shape fq_address column.
ALTER TABLE instances ADD COLUMN fq_address TEXT;

-- Backfill: instance.fq_address mirrors the parent resource's HCL-form
-- fq_address (no module-path index keys, no leaf [key]).  Equivalent to
-- stripping '[...]' from the instance's resource_address.
UPDATE instances
SET fq_address = regexp_replace(resource_address, '\[[^\]]*\]', '', 'g');

ALTER TABLE instances ALTER COLUMN fq_address SET NOT NULL;

-- Re-establish the FK with the new column names.  PKs survived the
-- renames automatically (resources_pkey on (state_id, address) and
-- instances_pkey on (state_id, address)).
ALTER TABLE instances
  ADD CONSTRAINT instances_resource_address_fkey
  FOREIGN KEY (state_id, resource_address)
  REFERENCES resources(state_id, address);

-- Re-point the partial unique indexes on transaction_logs.  Previously
-- they keyed by (tx_id, state_id, data->>'fq_address') where 'fq_address'
-- in the JSON payload was the full unique address.  After the rename,
-- the payload field with the full unique address is 'address' (the new
-- 'fq_address' field is the non-unique HCL-shape form).
DROP INDEX IF EXISTS transaction_logs_resource_unique_idx;

CREATE UNIQUE INDEX transaction_logs_resource_unique_idx
  ON transaction_logs (tx_id, state_id, (data->>'address'))
  WHERE object_type = 'resource';

DROP INDEX IF EXISTS transaction_logs_instance_unique_idx;

CREATE UNIQUE INDEX transaction_logs_instance_unique_idx
  ON transaction_logs (tx_id, state_id, (data->>'address'))
  WHERE object_type = 'instance';
