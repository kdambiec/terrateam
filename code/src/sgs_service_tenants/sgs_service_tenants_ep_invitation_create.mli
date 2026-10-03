(** POST [/api/v1/tenants/{tenant_id}/invitations]. Invite an address to a tenant, and email the
    link.

    Requires administering the tenant or holding [users-manage] scoped to it, plus membership.

    Responds 201 with the invitation and its {i one-shot} [invite_url] even when nobody was emailed
    — the row exists and the link works regardless, and [delivery] tells the inviter whether the
    message went out, so they know to pass the link on themselves. *)
module Make (_ : Sgs_cloud.S) : sig
  val run :
    Sgs_config.t ->
    Sgs_storage.t ->
    Sgs_tenant.minted Sgs_tenant.t ->
    Sgs_api_components_invitation_create_request.t ->
    Brtl_rtng.Handler.t
end
