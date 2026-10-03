-- Invitations this user created within the last $hours hours, for the per-inviter rate limit.
select count(*)
from tenant_invitations
where invited_by = $invited_by and created_at > now() - ($hours::text || ' hours')::interval
