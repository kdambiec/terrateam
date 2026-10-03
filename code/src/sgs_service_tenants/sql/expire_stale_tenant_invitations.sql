-- Mark any timed-out pending invitation for this (tenant, address) as expired.
--
-- Not a sweeper: correctness never depends on this running, because the accept statement re-checks
-- expires_at.  It exists so that an expired invitation stops occupying the one-live-invitation-per-
-- address slot enforced by tenant_invitations_tenant_email_pending_idx, which would otherwise make
-- that address permanently un-invitable.
update tenant_invitations
set state = 'expired'
where tenant_id = $tenant_id
  and lower(email) = lower($email)
  and state = 'pending'
  and expires_at <= now()
