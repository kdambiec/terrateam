INSERT INTO transaction_states (id) VALUES ('previewing'), ('committing');

ALTER TABLE transactions DROP CONSTRAINT transactions_check;

ALTER TABLE transactions ADD CONSTRAINT transactions_check
  CHECK (
    (state IN ('open', 'previewing', 'committing') AND completed_at IS NULL)
    OR (state IN ('aborted', 'failed', 'committed') AND completed_at IS NOT NULL)
  )