-- Accept an invitation: the single statement that makes acceptance single-use.
--
-- The state and expiry predicates live in the WHERE clause, so under READ COMMITTED two concurrent
-- accepts of the same token serialise on the row lock and the loser re-evaluates against the
-- committed row, sees state = 'accepted', and updates nothing.  No SELECT FOR UPDATE, no advisory
-- lock, no retry loop -- and no window in which both callers believe they won.
--
-- expires_at > now() here is the security boundary for expiry.  Do not rely on the 'expired' state
-- being set, which is only ever a lazy bookkeeping update.
update tenant_invitations
set state = 'accepted',
    accepted_at = now(),
    accepted_by = $user_id
where token_hash = $token_hash
  and state = 'pending'
  and expires_at > now()
returning id, tenant_id, email, role
