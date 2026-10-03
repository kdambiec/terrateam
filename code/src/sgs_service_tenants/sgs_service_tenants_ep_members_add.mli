(** POST [/api/v1/tenants/{tenant_id}/members]. Add an existing user to the tenant as a plain member
    — the direct counterpart to the DELETE remove, and distinct from an invitation, which is for
    someone who has no account yet.

    Grants no capability, only the membership row, so the added user starts with no tenant-scoped
    rights. Idempotent: adding a current member returns them unchanged, answering [200] rather than
    [201] so a caller can tell the membership it created from one that was already there — the
    members listing cannot answer that, being oldest-membership-first and paged. Requires
    administering the tenant or holding [users-manage] scoped to it, plus membership. 404 when no
    such active user exists. *)
val run :
  Sgs_config.t ->
  Sgs_storage.t ->
  Sgs_tenant.minted Sgs_tenant.t ->
  Sgs_api_components_tenant_member_add_request.t ->
  Brtl_rtng.Handler.t

(** Test-only. {!run} is the HTTP handler and cannot be driven from a test; this is the storage half
    it delegates to. Exposed so a test can pin the two outcomes only this half decides: a user id
    with no active user behind it is [`User_not_found_err], the 404 an invitation exists for, and a
    membership row still missing right after the add is [`Member_missing_after_add_err], a broken
    invariant answered with 500 rather than a 404. It takes its own connection from the pool, so a
    test must commit its fixture before calling. *)
module Tests : sig
  type run_prime_err =
    [ Pgsql_io.err
    | Pgsql_pool.err
    | Sgs_tenant.enforce_user_err
    | `Member_missing_after_add_err of Uuidm.t
    | `User_not_found_err of Uuidm.t
    ]

  val run' :
    Sgs_storage.t ->
    Sgs_tenant.minted Sgs_tenant.t ->
    'a Sgs_user.t ->
    Uuidm.t ->
    (Sgs_tenant.Member.t * [ `Added | `Already_member ], [> run_prime_err ]) result Abb.Future.t
end
