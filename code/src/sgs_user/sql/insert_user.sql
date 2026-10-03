insert into users (email, name, type, password_hash, capability_trie, base_capability_trie)
values ($email, $name, $type, $password_hash, $capability_trie, $capability_trie)
returning id
