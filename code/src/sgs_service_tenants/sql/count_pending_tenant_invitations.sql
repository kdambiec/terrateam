-- Live invitations outstanding for this tenant, for the per-tenant cap.
select count(*)
from tenant_invitations
where tenant_id = $tenant_id and state = 'pending' and expires_at > now()
