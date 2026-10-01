ALTER TABLE instances ALTER COLUMN index_key TYPE jsonb USING
  CASE
    WHEN index_key ~ '^\d{1,4}$' THEN to_jsonb(index_key::integer)
    WHEN index_key IS NOT NULL THEN to_jsonb(index_key)
    ELSE NULL
  END
