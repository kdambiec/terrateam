ALTER TABLE outputs ADD COLUMN address TEXT;

UPDATE outputs SET address = 'output.' || name;

ALTER TABLE outputs ALTER COLUMN address SET NOT NULL;
