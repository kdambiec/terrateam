(** POST [/api/v1/tenants/{tenant_id}/invitations/reissue?id=]. Re-issue a pending invitation under
    a fresh link and email it again.

    Requires administering the tenant or holding [users-manage] scoped to it, plus membership.

    This is the only way to obtain a link for an existing invitation: only the token's hash is
    stored, so the original is unrecoverable once created. The previous link stops working, which
    the UI must say plainly. Responds 200 with the new [invite_url] whether or not the email was
    delivered. *)
module Make (_ : Sgs_cloud.S) : sig
  val run :
    Sgs_config.t -> Sgs_storage.t -> Sgs_tenant.minted Sgs_tenant.t -> string -> Brtl_rtng.Handler.t
end
