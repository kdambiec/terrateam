-- Records, per HCL row, the config attributes whose value is statically anchored
-- at a ${path.module|root|cwd} variable (e.g. chart = "${path.module}/helm/certs").
-- Detected at transaction-log time (see Sg_path_attr) and consumed during
-- reification to rewrite the persisted state value to the bundle-specific layout,
-- avoiding a spurious plan diff under reification.  Shape (expr is the
-- value expression serialized to its Yojson.Safe representation):
--   [{"attr": "chart", "expr": <serialized ${path.module}/helm/certs>}, ...]
-- Nullable: NULL for rows with no anchored attributes.
ALTER TABLE hcl ADD COLUMN path_attrs jsonb;
