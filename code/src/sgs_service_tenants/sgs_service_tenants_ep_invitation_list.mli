(** GET [/api/v1/tenants/{tenant_id}/invitations]. Page a tenant's invitations, newest first.

    Requires administering the tenant or holding [users-manage] scoped to it, plus membership. *)
val run :
  Sgs_config.t ->
  Sgs_storage.t ->
  Sgs_tenant.minted Sgs_tenant.t ->
  string option ->
  int ->
  Brtl_rtng.Handler.t
