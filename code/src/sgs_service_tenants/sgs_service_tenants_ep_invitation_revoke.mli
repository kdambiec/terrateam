(** POST [/api/v1/tenants/{tenant_id}/invitations/revoke?id=]. Revoke a pending invitation, killing
    its outstanding link before the TTL would have.

    Requires administering the tenant or holding [users-manage] scoped to it, plus membership. *)
val run :
  Sgs_config.t -> Sgs_storage.t -> Sgs_tenant.minted Sgs_tenant.t -> string -> Brtl_rtng.Handler.t
