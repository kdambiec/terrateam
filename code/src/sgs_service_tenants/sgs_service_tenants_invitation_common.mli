(** Shared pieces of the tenant invitation endpoints: the API projection, the rate limits, the
    address masking, and best-effort delivery. *)

(** Rate limits. These SQL-backed counts are authoritative; the control plane keeps a per-replica
    token bucket as a backstop only. Accept attempts are deliberately not limited — a token is 256
    bits of entropy, so brute force is not in the threat model, and a limit there would let an
    attacker lock a legitimate invitee out by burning the budget. *)
val max_per_inviter_hour : int

val max_per_inviter_day : int
val max_pending_per_tenant : int
val role_of_admin_flag : bool option -> Sgs_service_tenants_invitation.Role.t
val api_role : Sgs_service_tenants_invitation.Role.t -> Sgs_api_components_tenant_invitation.Role.t

(** Project an invitation onto the API type. The reported status accounts for an expiry that has
    passed while the stored state still says pending. *)
val to_api : Sgs_service_tenants_invitation.t -> Sgs_api_components_tenant_invitation.t

(** Mask a recipient address for the unauthenticated preview, keeping the first character and the
    domain. The invitee already knows their own address; this stops a forwarded or leaked link from
    disclosing who it was for. *)
val mask_email : string -> string

val respond_json :
  status:Cohttp.Code.status_code -> string -> ('a, 'b) Brtl_ctx.t -> ('a, Brtl_rspnc.t) Brtl_ctx.t

(** Answer a failed lookup. Expiry is 410 Gone rather than 404: the link was real, and "expired, ask
    for a new one" is a different instruction than "this was never valid". *)
val respond_consume_err :
  ('a, 'b) Brtl_ctx.t ->
  [< `Not_found | `Expired | `Revoked | `Already_accepted ] ->
  ('a, Brtl_rspnc.t) Brtl_ctx.t

val respond_act_err :
  ('a, 'b) Brtl_ctx.t ->
  [< `Not_found | `Not_pending | `Cooldown | `Send_limit ] ->
  ('a, Brtl_rspnc.t) Brtl_ctx.t

(** The link the invitee follows. The trailing slash is required rather than cosmetic: the console
    is a static export with [trailingSlash] enabled, so the artifact is [/invite/index.html] and
    [/invite?token=] would 404 unless the host redirects while preserving the query. *)
val accept_url : console_base:string -> token:string -> string

val check_rate_limits :
  invited_by:Uuidm.t ->
  tenant_id:Uuidm.t ->
  Pgsql_io.t ->
  (unit, [> `Rate_limited of string | Pgsql_io.err ]) result Abb.Future.t

(** What became of the invitation message.

    Only [Transport_failed] is a fault. [Not_configured] (no control plane to call),
    [No_provider_key] (the control plane answered 2xx but only logged the message) and
    [Inviter_has_no_email] (no identity to present, so delivery short-circuits before the control
    plane is reached) all mean "nobody was emailed" — a supported mode, not a failure, per
    {!Sgs_cloud.S.send_tenant_invite}. Callers must not report those three to the inviter as a
    delivery failure: there, the copyable link {i is} the delivery path. *)
module Delivery : sig
  type t =
    | Emailed
    | Not_configured
    | No_provider_key
    | Inviter_has_no_email
    | Transport_failed

  (** The tri-state to store on the row: [Some true] emailed, [Some false] attempted and did not
      arrive, [None] never attempted. *)
  val delivered : t -> bool option

  val to_api : t -> Sgs_api_components_invitation_create_response.Delivery.t
end

module Make_sender (_ : Sgs_cloud.S) : sig
  (** Send the invitation email and record the attempt, returning which of the five outcomes
      happened.

      Delivery failure never fails the invitation: the row exists and its link works whether or not
      an email arrived. The caller must return the link to the inviter so they can pass it on
      themselves. *)
  val deliver :
    config:Sgs_config.t ->
    request_token:string ->
    inviter:Sgs_user.stored Sgs_user.t ->
    invitation_id:Uuidm.t ->
    email:string ->
    tenant_name:string ->
    accept_url:string ->
    expires_at:string ->
    Pgsql_io.t ->
    (Delivery.t, [> Pgsql_io.err ]) result Abb.Future.t
end
