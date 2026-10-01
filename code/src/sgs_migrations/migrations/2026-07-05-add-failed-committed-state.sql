-- Add the 'failed-committed' transaction state: the terminal state a
-- transaction enters when its apply (commit) fails after it has entered
-- 'committing', distinct from the generic 'failed' produced by a preview/plan
-- failure. Widen the terminal (completed_at IS NOT NULL) side of the check
-- constraint to admit it; the in-flight side is unchanged. Backwards
-- compatible: existing rows still satisfy the constraint and older app code
-- never writes the new value.
INSERT INTO transaction_states (id) VALUES ('failed-committed');

ALTER TABLE transactions DROP CONSTRAINT transactions_check;

ALTER TABLE transactions ADD CONSTRAINT transactions_check
  CHECK (
    (state IN ('open', 'previewing', 'previewed', 'committing') AND completed_at IS NULL)
    OR (state IN ('aborted', 'failed', 'failed-committed', 'committed') AND completed_at IS NOT NULL)
  )
