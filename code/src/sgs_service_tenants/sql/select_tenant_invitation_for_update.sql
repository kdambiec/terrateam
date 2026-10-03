-- Lock one of a tenant's invitations for a resend, re-issue or revoke.  Scoped by tenant_id as well
-- as id so an id from another tenant cannot be acted on by this tenant's administrator.
select
    i.id,
    i.email,
    i.role,
    i.state,
    i.send_count,
    i.last_sent_at is not null and i.last_sent_at > now() - interval '5 minutes',
    t.name
from tenant_invitations as i
inner join tenants as t
    on t.id = i.tenant_id
where i.id = $id and i.tenant_id = $tenant_id
for update of i
