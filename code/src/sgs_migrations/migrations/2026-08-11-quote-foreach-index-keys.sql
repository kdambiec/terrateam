-- [for_each] instance keys were rendered without quotes -- the raw key
-- concatenated into brackets after the resource address -- so instance
-- addresses were stored as [terraform_data.foo[a]], not an address Terraform
-- would parse and not the form tofu itself uses ([terraform_data.foo["a"]]).
-- The renderer is fixed in this commit ([Sg_tf_state.Key] now builds the
-- address as an HCL traversal and prints it with [Hcl_ast.To_string]); this
-- rewrites the rows written before it.
--
-- Only [instances.address] carries a leaf index key.  [resources.address] and
-- [instances.resource_address] are built without one, and module-path keys come
-- from tofu's own [module] field and are already quoted -- so the
-- (state_id, resource_address, mode) FK to [resources] is untouched and needs no
-- drop/re-add (contrast 2026-03-10-fix-data-source-addresses.sql, which had to
-- move both sides of it).
--
-- The predicate skips anything already containing a quote, so this is idempotent
-- and safe to re-run, and skips all-digit keys so [count] indices ([foo[0]]) are
-- left alone.  The [$] anchor keeps it to the LEAF key: an already-quoted module
-- key earlier in the address ([module.vpc["a"].terraform_data.foo]) is never a
-- candidate, and in a mixed address ([module.vpc[0]...foo[b]]) only the trailing
-- key moves.
--
-- Quoting a key is not wrapping it in two quote characters, so the rewrite has to
-- reproduce what [Hcl_ast_to_string.escape_hcl_string] does or the row it writes is
-- a plausible-looking address the renderer will never emit again -- worse than
-- leaving it alone, because nothing marks it as stale.  In order: '\' doubles,
-- newline/CR/tab become their two-character escapes, and the template introducers
-- '${' and '%{' double their first character.  Backslash MUST go first, or the
-- backslashes the other escapes introduce are doubled in turn.  '"' needs no case
-- here: the predicate below skips any address containing one.
--
-- The backslash literals are E-strings for [Pgsql_io], not for PostgreSQL.  Its
-- statement parser scans for '$name' placeholders and tracks quoted strings as it
-- goes, treating a backslash inside one as escaping the NEXT character -- so a
-- lone '\' would eat the closing quote, leave the parser believing it is still
-- inside a string, and the first '${' after that becomes an empty variable name
-- ([`Empty_variable_name], at migration time, not compile time).  E'\\' is the
-- same single backslash to PostgreSQL and keeps that scan in step.
--
-- Two limits of the old data, both unavoidable here:
--   * an all-digit [for_each] key (toset(["0"])) was stored as [foo[0]], which is
--     indistinguishable from a [count] index.  It stays unquoted.  Rows written
--     after the renderer fix are unambiguous.
--   * a key containing a literal ']' or '"' matches nothing here and is left as
--     is: the stored form is ambiguous and a migration is not the place to guess.
--
-- [transaction_logs] is deliberately NOT rewritten.  It is the append-only audit
-- history, and the addresses in it were accurate for the runs that produced them.
--
-- [cost_snapshot_resources] is not rewritten either, and it is worth saying why,
-- because it is the one place the two forms met.  A 'current' snapshot takes its
-- addresses from [instances.address] (select_instances_for_cost.sql) while a
-- 'planned' one takes them from the plan JSON, which is tofu's own quoted form --
-- so select_tx_resource_deltas.sql, which full-outer-joins the two ON ADDRESS,
-- has never matched a [for_each] instance and has been reporting each one as a
-- removal plus an addition.  Fixing the renderer fixes that for every snapshot
-- taken from here on.  Back-filling the old rows would not: a snapshot is a
-- point-in-time record, the rows it would have to match are equally old, and
-- nothing that works today starts failing by leaving them alone.
update instances
set address =
      regexp_replace(address, '\[[^]"]+\]$', '')
      || '["'
      || replace(replace(replace(replace(replace(replace(
           substring(address from '\[([^]"]+)\]$'),
           E'\\', E'\\\\'),
           E'\n', '\n'),
           E'\r', '\r'),
           E'\t', '\t'),
           '${', '$${'),
           '%{', '%%{')
      || '"]'
where address ~ '\[[^]"]+\]$'
  and address !~ '\[[0-9]+\]$';
