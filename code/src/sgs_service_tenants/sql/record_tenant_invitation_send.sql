-- Record a delivery attempt.  $delivered is three-valued (see the migration): NULL when no attempt
-- was made at all, so a send that was skipped does not consume the send budget's meaning.
update tenant_invitations
set delivered = $delivered,
    send_count = send_count + 1,
    last_sent_at = now()
where id = $id
