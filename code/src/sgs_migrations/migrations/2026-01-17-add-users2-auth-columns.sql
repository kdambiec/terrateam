-- Add OAuth authentication columns to users table
-- These columns track which OAuth provider a user authenticated with
-- and allow invalidation when the OAuth config changes

-- Machine-friendly name of the OAuth config (e.g., "google", "okta")
-- NULL for users created before OAuth (e.g., GitHub users, system user)
alter table users add column if not exists auth_origin text;

-- Hash of the OAuth config at time of authentication
-- Used to invalidate sessions when config changes
alter table users add column if not exists auth_config_hash text;

-- External user ID from the OAuth provider (username/sub claim)
-- Unique within each auth_origin
alter table users add column if not exists external_id text;

-- User's display name from OAuth provider
alter table users add column if not exists display_name text;

-- Index for looking up users by auth_origin + external_id
-- This is the primary lookup pattern for OAuth authentication
create unique index if not exists users_auth_origin_external_id_idx on users (auth_origin, external_id)
    where auth_origin is not null and external_id is not null;

-- Index for finding all users from a specific OAuth config
create index if not exists users_auth_origin_idx on users (auth_origin)
    where auth_origin is not null;
