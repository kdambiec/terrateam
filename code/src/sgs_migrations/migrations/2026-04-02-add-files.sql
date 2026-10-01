-- The files table stores file content referenced by HCL functions (file, filebase64, templatefile) and local_file data sources.
-- Columns are as follows:
-- - filepath is the evaluated path to the file
-- - content is the file content
-- - content_hash is the hash of content (used to check if a file's content changed by sending only the hash to the server)
-- - template_vars is the list of variables in the template file (if it is a template file, otherwise empty)
create table files (
    state_id uuid not null references states(id),
    filepath text not null,
    content bytea not null,
    content_hash text not null,
    template_vars text[] not null default '{}',
    primary key (state_id, filepath)
);

-- The filepath_refs table links HCL nodes to the files they reference.
-- Each row represents one reference path from an HCL node to a file.
-- A single HCL node can produce multiple rows when:
--   - The filepath expression contains a variable (one row with ref = the variable address)
--   - A templatefile() call has template variables (one row per variable, with template_var set)
--   - A templatefile() call also gets a row with ref = NULL for the filepath itself
--
-- Columns:
--   state_id     — the state owning the HCL node and file
--   id           — the HCL node id (e.g. "resource.terraform_data.with_file")
--   ref          — the HCL address referenced in the filepath or template variable expression
--                   (e.g. "var.config_path", "var.name"), or NULL if the path is a literal
--   filepath     — the evaluated filepath (e.g. "data.txt", "configs/data.txt")
--   template_var — for templatefile() calls: the name of the template variable being instantiated
--                   (e.g. "name", "nickname"), or NULL for non-template references
--
-- Examples:
--   file("data.txt")                         → (id, NULL,             "data.txt",         NULL)
--   file("${var.config_path}/data.txt")      → (id, "var.config_path","configs/data.txt", NULL)
--   templatefile("t.tpl", {name = var.name}) → (id, NULL,             "t.tpl",            NULL)
--                                              (id, "var.name",       "t.tpl",            "name")
--
-- See e2e_tests_files.ml for examples
create table filepath_refs (
    state_id uuid not null,
    id text not null,
    ref text,
    filepath text not null,
    template_var text,
    foreign key (state_id, id) references hcl(state_id, id),
    foreign key (state_id, filepath) references files(state_id, filepath)
);

create unique index filepath_refs_unique_idx on filepath_refs (state_id, id, filepath, coalesce(template_var, ''));

create index filepath_refs_state_filepath_idx on filepath_refs (state_id, filepath);

create index filepath_refs_state_id_idx on filepath_refs (state_id, id);

-- file_refs jsonb column on hcl: stores which file functions are called
-- and their evaluated paths. The value is a JSON array of objects, each with:
--   file_function  - the function name: "file", "filebase64", "templatefile", or "data.local_file"
--   filepath       - the evaluated filepath (e.g. "data.txt"), or null if evaluation failed
--   index          - the index of the occurence of the file_function call in the enclosing HCL block, in depth-first order
--   refs           - array of HCL addresses referenced in the filepath expression
--                     (e.g. ["var.config_path"]), empty if the path is a literal
--   template_vars  - array of {var_name, var_refs} objects for templatefile() calls;
--                     var_name is the template variable name (e.g. "name"),
--                     var_refs is the list of HCL addresses in the instantiation expression
--                     (e.g. ["var.name"]). Empty array for non-templatefile functions.
--
-- Example for templatefile("template.tpl", {name = var.name, nickname = var.name}):
--
--   [{"file_function": "templatefile", "filepath": "template.tpl", "index":0, "refs": [],
--     "template_vars": [{"var_name": "name", "var_refs": ["var.name"]},
--                        {"var_name": "nickname", "var_refs": ["var.name"]}]}]
--
-- See e2e_tests_files.ml for examples
alter table hcl add column file_refs jsonb;

-- Transaction log actions and object type for files.
insert into transaction_log_actions (id) values ('file_set');

insert into transaction_log_actions (id) values ('file_delete');

insert into transaction_log_object_types (id) values ('file');

-- Unique index for file upsert deduplication in transaction logs.
create unique index transaction_logs_file_unique_idx
    on transaction_logs (tx_id, state_id, (data->>'filepath'))
    where object_type = 'file';
