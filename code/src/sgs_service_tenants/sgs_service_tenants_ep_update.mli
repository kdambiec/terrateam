(** PUT [/api/v1/tenants/{tenant_id}]. Rename a tenant.

    Requires administering the tenant, plus membership. Deliberately does {i not} accept
    [users-manage] scoped to the tenant: renaming is administration of the tenant itself, not of its
    membership. *)
val run :
  Sgs_config.t ->
  Sgs_storage.t ->
  Sgs_tenant.minted Sgs_tenant.t ->
  Sgs_api_components_tenant_update_request.t ->
  Brtl_rtng.Handler.t
