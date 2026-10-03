-- Create a pending invitation.  The caller expires stale pending rows for the same (tenant, email)
-- first (expire_stale_tenant_invitations.sql), so the partial unique index only fires on a genuinely
-- live duplicate -- which the caller turns into a resend rather than an error.
insert into tenant_invitations (
    email, expires_at, invited_by, role, tenant_id, token_hash
)
values (
    $email,
    now() + ($ttl_hours::text || ' hours')::interval,
    $invited_by,
    $role,
    $tenant_id,
    $token_hash
)
returning
    id,
    to_char(created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    to_char(expires_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
