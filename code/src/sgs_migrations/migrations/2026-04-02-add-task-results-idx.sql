ALTER TABLE task_results ADD COLUMN idx integer NOT NULL DEFAULT 0;

ALTER TABLE task_results DROP CONSTRAINT task_results_pkey;

ALTER TABLE task_results ADD PRIMARY KEY (task_id, idx)
