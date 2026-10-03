(** DELETE [/api/v1/tenants/{tenant_id}/members?user_id=]. Remove a member from a tenant, stripping
    the tenant from their [admin] and [users-manage] allow-lists in the same transaction.

    Requires administering the tenant or holding [users-manage] scoped to it, plus membership.

    Refuses to remove the caller (leaving a tenant is a different action from administering its
    membership), the tenant's only administrator, or a member whose grant covers more than this
    tenant — in the last case nothing is written at all, because the half-applied state leaves the
    user still authorized. *)
val run :
  Sgs_config.t -> Sgs_storage.t -> Sgs_tenant.minted Sgs_tenant.t -> string -> Brtl_rtng.Handler.t
