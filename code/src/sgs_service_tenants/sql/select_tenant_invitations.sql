-- A page of a tenant's invitations, newest first.  'pending' rows whose expires_at has passed are
-- reported as expired without being rewritten -- the lazy sweep only runs when the slot is needed.
--
-- $cursor and $cursor_id are the created_at and id of the last row of the previous page.  Both are
-- needed: invitations created together share a created_at, so a created_at-only cursor would skip or
-- repeat whichever of them straddles a page boundary.  Newest-first, so the next page is the rows
-- strictly before the cursor in the (created_at, id) order.
select
    i.id,
    i.email,
    i.role,
    i.state,
    to_char(i.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    to_char(i.expires_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    i.expires_at <= now(),
    i.delivered,
    i.send_count,
    coalesce(u.display_name, u.name),
    -- Stable across pages: the tenant's whole invitation count, computed without the cursor
    -- predicate (count(*) over() would count only this page's post-cursor rows).
    (select count(*) from tenant_invitations where tenant_id = $tenant_id) as total_count
from tenant_invitations as i
inner join users as u
    on u.id = i.invited_by
where i.tenant_id = $tenant_id
  and ($cursor::timestamptz is null
       or (i.created_at, i.id) < ($cursor::timestamptz, $cursor_id::uuid))
order by i.created_at desc, i.id desc
limit $limit
