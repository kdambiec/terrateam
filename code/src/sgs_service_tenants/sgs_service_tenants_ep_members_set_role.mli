(** POST [/api/v1/tenants/{tenant_id}/members/set-role?user_id=]. Grant or revoke a member's
    tenant-scoped [admin] and [users-manage] capabilities. Both body fields are optional; an omitted
    one is left alone, and the two grants are independent.

    Requires administering the tenant or holding [users-manage] scoped to it, plus membership.

    Refuses to demote the caller (that would lock them out of the screen needed to undo it), to
    demote the tenant's only administrator, or to edit a grant that covers more than this tenant.
    Promoting a member who already holds an installation-wide grant is a no-op rather than a
    downgrade; the response reports the coverage actually stored. *)
val run :
  Sgs_config.t ->
  Sgs_storage.t ->
  Sgs_tenant.minted Sgs_tenant.t ->
  string ->
  Sgs_api_components_tenant_member_set_role_request.t ->
  Brtl_rtng.Handler.t

(** Test-only. {!run} is the HTTP handler and cannot be driven from a test; this is the storage half
    it delegates to. Exposed so a test can pin the asymmetry [apply_grant] encodes: a widening
    self-change keeps [except_login_session], a narrowing one drops it and logs the caller out. It
    takes its own connection from the pool, so a test must commit its fixture before calling. *)
module Tests : sig
  type run_prime_err =
    [ Pgsql_io.err
    | Pgsql_pool.err
    | Sgs_tenant.enforce_user_err
    | `Last_tenant_admin
    | `Member_not_found
    | `Wider_grant of Sg_caps_ops.tenant_grant
    | `User_not_found_err of Uuidm.t
    ]

  val run' :
    except_login_session:Uuidm.t option ->
    Sgs_storage.t ->
    Sgs_tenant.minted Sgs_tenant.t ->
    'a Sgs_user.t ->
    Uuidm.t ->
    Sgs_api_components_tenant_member_set_role_request.t ->
    (Sgs_tenant.Member.t, [> run_prime_err ]) result Abb.Future.t
end
