-- Read an invitation by token for the unauthenticated preview, and to tell a caller whose accept
-- matched no row *why* it did not (expired, revoked, already accepted).  Returns no secret: the
-- caller masks the address before it reaches the response.
select
    i.id,
    i.tenant_id,
    t.name,
    i.email,
    i.role,
    i.state,
    to_char(i.expires_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    i.expires_at <= now(),
    coalesce(u.display_name, u.name)
from tenant_invitations as i
inner join tenants as t
    on t.id = i.tenant_id
inner join users as u
    on u.id = i.invited_by
where i.token_hash = $token_hash
