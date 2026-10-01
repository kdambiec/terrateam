-- OAuth2 session storage table for oauth2-proxy HTTP storage backend
-- Sessions are stored by oauth2-proxy during the OAuth flow and used to
-- maintain state between redirects to the OAuth provider and back

create table if not exists oauth2_sessions (
    -- Session key from oauth2-proxy (format: {CookieName}-{ticketID})
    key text not null,
    -- Machine-friendly name of the OAuth config (e.g., "google", "okta")
    namespace text not null,
    -- Hash of the OAuth config for invalidation when config changes
    config_hash text not null,
    -- Base64-encoded encrypted session data from oauth2-proxy
    data text not null,
    -- When the session expires (used for cleanup)
    expires_at timestamp with time zone not null,
    -- When the session was created
    created_at timestamp with time zone not null default (now()),
    -- Primary key is (namespace, key) to allow same key in different namespaces
    primary key (namespace, key)
);

-- Index for cleaning up expired sessions
create index oauth2_sessions_expires_at_idx on oauth2_sessions (expires_at);

-- Index for deleting all sessions when a config changes
create index oauth2_sessions_config_hash_idx on oauth2_sessions (namespace, config_hash);
