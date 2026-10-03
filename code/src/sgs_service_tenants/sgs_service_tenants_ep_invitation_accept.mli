(** POST [/api/v1/invitations/accept]. Accept an invitation as the signed-in user: consume the
    token, join the tenant, and for an admin invitation merge the tenant into the user's [admin]
    allow-list.

    All of it in one transaction, and the capability write {i unions} rather than replaces — a
    shared-instance user already administers their own personal tenant, and overwriting would
    silently revoke authority over their own workspace.

    Runs after sign-in rather than inside the OAuth callback, so that an invalid token cannot fail a
    signup and a real page can explain the outcome. All three arrival cases (signed in, has an
    account but signed out, no account at all) reach identical server code.

    A session whose email differs from the invited address is allowed through and reported via
    [email_mismatch] rather than refused: [users.email] is nullable and never re-synced after first
    sign-in, so strict matching would permanently lock out legitimate users. The mismatch is logged
    and [accepted_by] on the row is the audit trail. *)
val run :
  Sgs_config.t ->
  Sgs_storage.t ->
  Sgs_api_components_invitation_accept_request.t ->
  Brtl_rtng.Handler.t
