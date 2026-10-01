-- Lock the user row for a capability read-modify-write, and hand back both capability columns.
--
-- A capability edit is a merge into an existing JSON object, not a replacement, so two concurrent
-- writes on the same user would otherwise interleave and one would lose its change. Deleted users
-- are excluded: their capabilities are not a thing callers may edit.
select capability_trie, base_capability_trie from users where id = $user_id and state = 'active' for update
