-- Re-issue a pending invitation under a fresh token, resetting its lifetime and send budget.
--
-- Needed because only the token's hash is stored, so the link cannot be shown a second time.  The
-- previous link stops working, which is the trade the UI has to state plainly.
update tenant_invitations
set token_hash = $token_hash,
    expires_at = now() + ($ttl_hours::text || ' hours')::interval,
    send_count = 0,
    last_sent_at = null,
    delivered = null
where id = $id and tenant_id = $tenant_id and state = 'pending'
returning id,
    -- created_at is untouched by the update above; return it so the response reports the real
    -- creation time rather than fabricating one from the new expiry.
    to_char(created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    to_char(expires_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
