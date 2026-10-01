ALTER TABLE transaction_previews ADD COLUMN idx integer NOT NULL DEFAULT 0;

ALTER TABLE transaction_previews DROP CONSTRAINT transaction_previews_pkey;

ALTER TABLE transaction_previews ADD PRIMARY KEY (tx_id, idx)
