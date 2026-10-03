-- Revoke a pending invitation, killing its outstanding link before the TTL would have.
update tenant_invitations
set state = 'revoked', revoked_at = now(), revoked_by = $user_id
where id = $id and tenant_id = $tenant_id and state = 'pending'
returning id
