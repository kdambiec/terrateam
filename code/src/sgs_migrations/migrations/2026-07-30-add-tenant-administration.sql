-- Consolidated schema for the #1409 tenant-administration feature.  Three migrations that landed
-- together -- tenant administration, tenant invitations, and the access-token 'kind' -- are merged
-- into this one file: none depends on another's tables, every statement is transactional DDL, and a
-- single migration is simpler to review and to apply.
--
-- The migration runner splits a file into statements on a semicolon followed by a blank line, so
-- each statement below is terminated with ';' and separated from the next by a blank line.


-- Support for tenant-scoped administration: a members list a tenant admin can page through, and a
-- floor on tenant names for the rename endpoint.
--
-- Membership timestamp on tenant_users.  The members list is cursor-paginated (never OFFSET, per the
-- database conventions) and the natural order is when someone joined the tenant.  users.created_at
-- cannot serve as that cursor: a user can be added to a tenant long after signing up, and the same
-- user appears in several tenants at different times.  Existing rows have no recorded join time, and
-- now() is the only defensible backfill -- it keeps the column NOT NULL without inventing history.
--
-- The primary key (tenant_id, user_id) serves the tenant-keyed filter.  The cursor's
-- (created_at, user_id) ordering is deliberately not separately indexed: the members query's
-- per-tenant count subquery already reads every active member of the tenant, so a sort-only index
-- would not cut that scan, and a tenant's membership is bounded enough that ordering the page is
-- cheap.
alter table tenant_users
    add column if not exists created_at timestamp with time zone not null default (now());

comment on column tenant_users.created_at is
    'When the user was added to the tenant; the cursor for the tenant members list';

-- Guard the rename endpoint's input at the schema level as well as in the handler.  NOT VALID so the
-- migration cannot fail on an existing blank name: it constrains new writes now, and can be
-- validated later once installations are known clean.
--
-- Deliberately NOT added here: a unique index on tenants.name.  find_or_create resolves tenants by
-- name, so duplicates are already latently wrong, but CREATE UNIQUE INDEX would fail outright on an
-- installation that has them and migrations must be backwards compatible.  update_tenant_name.sql
-- guards collisions in-statement instead; de-duplicating and then adding the index is its own change.
alter table tenants
    add constraint tenants_name_not_blank check (length(btrim(name)) > 0) not valid;

-- Tenant invitations: an emailed, single-use, revocable link that adds its recipient to a tenant.
--
-- Why state lives here rather than in aegis, which owns email delivery: accepting must, in one
-- transaction, mark the invitation consumed, insert the membership row, and possibly merge an admin
-- grant into users.capabilities.  If consumption lived on the far side of an HTTP call the failure
-- modes are a double-usable invitation or a lost membership.  Stategraph owns identity and tenants;
-- aegis is a stateless transport for the message.
create table tenant_invitation_states (
    id text primary key
);

insert into tenant_invitation_states (id) values
    ('pending'),
    ('accepted'),
    ('revoked'),
    ('expired');

create table tenant_invitation_roles (
    id text primary key
);

insert into tenant_invitation_roles (id) values
    ('member'),
    ('admin');

create table tenant_invitations (
    accepted_at timestamp with time zone,
    accepted_by uuid,
    created_at timestamp with time zone not null default (now()),
    -- Three-valued on purpose: NULL = delivery never attempted (aegis not configured, or the inviter
    -- has no email), false = attempted but not delivered (no provider key in dev, or a transport
    -- failure), true = the provider accepted it.
    delivered boolean,
    email text not null,
    expires_at timestamp with time zone not null,
    id uuid primary key default (gen_random_uuid()),
    invited_by uuid not null,
    last_sent_at timestamp with time zone,
    revoked_at timestamp with time zone,
    revoked_by uuid,
    role text not null default 'member',
    send_count integer not null default 0,
    state text not null default 'pending',
    tenant_id uuid not null,
    -- Only the SHA-256 of the token is stored, never the token, so a database dump yields no working
    -- invitation links.  That is also why the link can only be shown once, at creation, and why
    -- re-issuing one mints a fresh token rather than revealing the old.
    token_hash bytea not null,
    foreign key (tenant_id) references tenants(id),
    foreign key (invited_by) references users(id),
    foreign key (accepted_by) references users(id),
    foreign key (revoked_by) references users(id),
    foreign key (state) references tenant_invitation_states(id),
    foreign key (role) references tenant_invitation_roles(id)
);

create unique index tenant_invitations_token_hash_idx
    on tenant_invitations (token_hash);

-- At most one live invitation per (tenant, address), case-insensitively.  This is what turns
-- "invite them again" into a resend instead of an unbounded fan-out of valid links, and it is why
-- creating an invitation first expires any stale pending row for the same pair -- otherwise an
-- expired invitation would permanently block re-inviting that address.
create unique index tenant_invitations_tenant_email_pending_idx
    on tenant_invitations (tenant_id, lower(email))
    where state = 'pending';

create index tenant_invitations_tenant_created_idx
    on tenant_invitations (tenant_id, created_at desc);

-- Serves the per-inviter rate limit counts.
create index tenant_invitations_invited_by_created_idx
    on tenant_invitations (invited_by, created_at desc);

-- Browser login sessions become DB-backed rows in access_tokens, so that changing a user's
-- capabilities can delete them and force a fresh sign-in.  'kind' separates them from API access
-- tokens: 'login' rows are invisible to the token-listing endpoints, are swept once their
-- expiration passes, and are deleted wholesale by Sgs_user.revoke_login_sessions.  'api' rows are
-- untouched by capability changes -- a token deliberately created for a holder keeps the
-- capabilities it was minted with until it expires or is revoked.
--
-- Backwards compatible: every existing row is an API token, which the default covers.
alter table access_tokens
    add column kind text not null default 'api'
    check (kind in ('api', 'login'));

comment on column access_tokens.kind is
    'api = user-created access token; login = a browser sign-in session, revoked on capability change';

-- Both login-session delete paths run on hot code paths and would otherwise be full access_tokens
-- scans as login rows accumulate: the per-user revoke on every capability change (user_id and
-- kind = 'login', delete_user_login_sessions.sql) and the expiry sweep on every sign-in (kind =
-- 'login' and expiration < now(), delete_expired_login_sessions.sql).  One partial index scoped to
-- login rows serves both -- the revoke seeks on the user_id prefix, and the sweep filters expiration
-- index-only over the same index, which stays small because the sweep bounds it.  At migration time
-- every row is kind = 'api' (the column default), so it covers zero rows and builds instantly.
create index access_tokens_login_idx
    on access_tokens (user_id, expiration)
    where kind = 'login';
