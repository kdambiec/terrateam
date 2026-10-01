ALTER TABLE states ADD COLUMN deleted_at timestamp with time zone;

ALTER TABLE states ADD COLUMN deleted_by uuid REFERENCES users(id)
