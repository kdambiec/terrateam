-- Replace a user's capabilities wholesale.  The merge happens in OCaml, because the allow-list
-- semantics -- longest match wins, a leading "!" refusing -- live in Sg_caps_trie_scope and must
-- not be reimplemented in SQL.
--
-- base_capabilities is the manually-managed baseline and capabilities the effective value login
-- recomputes from it (capabilities := base_capabilities, unioned with the IdP group rules).
-- Changes done through the API/CLI, etc. should be written to 'base_capability_trie' for being persistent
-- and they should also be written to 'capability_trie' to be effective immediately.
--
-- Returns the id so a caller can tell a no-op (user gone or deleted between the lock and here) from
-- a successful write; a caller holding the lock from that same select already knows.
update users
set capability_trie = $capability_trie,
    base_capability_trie = $base_capability_trie
where id = $user_id and state = 'active'
returning id
