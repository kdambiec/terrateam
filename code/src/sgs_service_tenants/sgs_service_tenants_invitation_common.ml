let src = Logs.Src.create "invitation_common"

module Logs = (val Logs.src_log src : Logs.LOG)
module Invitation = Sgs_service_tenants_invitation

(* Rate limits.  The authoritative counts are these SQL queries, not the per-replica token bucket
   the control plane keeps as a backstop.  Accept attempts are deliberately NOT limited: a token is
   256 bits of entropy, so brute force is not in the threat model, and a limit there would let an
   attacker lock a legitimate invitee out by burning the budget. *)
let max_per_inviter_hour = 20
let max_per_inviter_day = 100
let max_pending_per_tenant = 50

let api_role = function
  | Invitation.Role.Member -> `Member
  | Invitation.Role.Admin -> `Admin

let role_of_admin_flag = function
  | Some true -> Invitation.Role.Admin
  | Some false | None -> Invitation.Role.Member

(* An invitation whose expiry has passed reports as expired even while the row still says pending --
   the stored state is only updated lazily, when its one-live-invitation slot is needed. *)
let api_status invitation =
  let open Invitation in
  match (state invitation, expired invitation) with
  | State.Pending, true -> `Expired
  | State.Pending, false -> `Pending
  | State.Accepted, _ -> `Accepted
  | State.Revoked, _ -> `Revoked
  | State.Expired, _ -> `Expired

let to_api invitation =
  Invitation.
    {
      Sgs_api_components_tenant_invitation.id = Uuidm.to_string (id invitation);
      email = email invitation;
      role = api_role (role invitation);
      status = api_status invitation;
      created_at = created_at invitation;
      expires_at = expires_at invitation;
      delivered = delivered invitation;
      send_count = send_count invitation;
      invited_by_name = invited_by_name invitation;
    }

(* Mask the recipient for the unauthenticated preview.  The invitee already knows their own address;
   this stops a link that was forwarded, leaked or found in a log from disclosing who it was for.
   The first character and the domain are kept so the real recipient can recognise it. *)
let mask_email email =
  match CCString.Split.left ~by:"@" email with
  | Some (local, domain) ->
      let head = if CCString.is_empty local then "" else CCString.sub local 0 1 in
      head ^ "***@" ^ domain
  | None -> "***"

let respond_json ~status body ctx = Brtl_ctx.set_response (Brtl_rspnc.create ~status body) ctx

(* Statuses for the shapes an invitation lookup can fail in.  410 Gone for expired rather than 404:
   the caller's link was real, and "expired, ask for a new one" is a different instruction to the user
   than "this link was never valid". *)
let respond_consume_err ctx = function
  | `Not_found ->
      Sgs_eplib.respond_error
        ~status:`Not_found
        ~id:"INVITATION_NOT_FOUND"
        ~data:"That invitation link is not valid"
        ctx
  | `Expired ->
      Sgs_eplib.respond_error
        ~status:`Gone
        ~id:"INVITATION_EXPIRED"
        ~data:"That invitation has expired. Ask for a new one."
        ctx
  | `Revoked ->
      Sgs_eplib.respond_error
        ~status:`Conflict
        ~id:"INVITATION_REVOKED"
        ~data:"That invitation was revoked"
        ctx
  | `Already_accepted ->
      Sgs_eplib.respond_error
        ~status:`Conflict
        ~id:"INVITATION_ALREADY_ACCEPTED"
        ~data:"That invitation has already been accepted"
        ctx

let respond_act_err ctx = function
  | `Not_found ->
      Sgs_eplib.respond_error
        ~status:`Not_found
        ~id:"INVITATION_NOT_FOUND"
        ~data:"No such invitation for this tenant"
        ctx
  | `Not_pending ->
      Sgs_eplib.respond_error
        ~status:`Conflict
        ~id:"INVITATION_NOT_PENDING"
        ~data:"That invitation is no longer pending"
        ctx
  | `Cooldown ->
      Sgs_eplib.respond_error
        ~status:`Too_many_requests
        ~id:"INVITATION_RESEND_COOLDOWN"
        ~data:"That invitation was sent very recently. Try again in a few minutes."
        ctx
  | `Send_limit ->
      Sgs_eplib.respond_error
        ~status:`Too_many_requests
        ~id:"INVITATION_SEND_LIMIT"
        ~data:
          (Printf.sprintf
             "That invitation has already been sent %d times. Generate a new link instead."
             Invitation.max_sends)
        ctx

(* The link the invitee follows.  The trailing slash is required, not cosmetic: the console is built
   as a static export with trailingSlash enabled, so the artifact is /invite/index.html and
   /invite?token= would 404 unless the host happens to redirect while preserving the query. *)
let accept_url ~console_base ~token =
  CCString.chop_suffix ~suf:"/" console_base
  |> CCOption.get_or ~default:console_base
  |> fun base -> base ^ "/invite/?token=" ^ Uri.pct_encode token

(* Enforce the per-inviter and per-tenant caps before an invitation is created. *)
let check_rate_limits ~invited_by ~tenant_id db =
  let open Abbs_fc.Infix_result_monad in
  Invitation.count_by_inviter ~hours:1 ~invited_by db
  >>= fun hour ->
  if hour >= max_per_inviter_hour then Abbs_fc.return_err (`Rate_limited "per hour")
  else
    Invitation.count_by_inviter ~hours:24 ~invited_by db
    >>= fun day ->
    if day >= max_per_inviter_day then Abbs_fc.return_err (`Rate_limited "per day")
    else
      Invitation.count_pending ~tenant_id db
      >>? fun pending ->
      if pending >= max_pending_per_tenant then Error (`Rate_limited "outstanding for this tenant")
      else Ok ()

(* What became of the message.  Only [Transport_failed] is a fault: the other three non-delivery
   cases are the supported link-only modes (see Sgs_cloud.S.send_tenant_invite), so a caller must not
   present them to the inviter as a failure.  That distinction is the whole reason this is a sum
   type and not a string -- as a string it was read as "any value means the send broke", which is
   wrong for three values out of four. *)
module Delivery = struct
  type t =
    | Emailed
    | Not_configured
    | No_provider_key
    | Inviter_has_no_email
    | Transport_failed

  (* The tri-state stored on the row: emailed, attempted but did not arrive, or never attempted. *)
  let delivered = function
    | Emailed -> Some true
    | No_provider_key | Transport_failed -> Some false
    | Not_configured | Inviter_has_no_email -> None

  let to_api = function
    | Emailed -> `Emailed
    | Not_configured -> `Not_configured
    | No_provider_key -> `No_provider_key
    | Inviter_has_no_email -> `Inviter_has_no_email
    | Transport_failed -> `Transport_failed
end

module Make_sender (Cloud : Sgs_cloud.S) = struct
  (* Send the message, and record what happened.  Delivery failure never fails the invitation: the row
   exists and its link works regardless of whether an email arrived.

   Returns which of the five outcomes happened, so the caller can both store the [delivered]
   tri-state and tell the inviter whether anyone was actually emailed. *)
  let deliver
      ~config
      ~request_token
      ~inviter
      ~invitation_id
      ~email
      ~tenant_name
      ~accept_url
      ~expires_at
      db =
    let open Abb.Future.Infix_monad in
    let identity_of inviter =
      match Sgs_user.email inviter with
      | Some email -> Some { Sgs_cloud.user_id = Uuidm.to_string (Sgs_user.id inviter); email }
      | None -> None
    in
    let record delivery =
      Invitation.record_send ~delivered:(Delivery.delivered delivery) ~id:invitation_id db
      >>| function
      | Ok () -> Ok delivery
      | Error (#Pgsql_io.err as err) -> Error err
    in
    match identity_of inviter with
    (* The inviter has no email of their own, so there is no identity to present to the control
     plane.  The invitation still stands -- the copyable link is the whole point of returning it. *)
    | None ->
        Logs.info (fun m ->
            m
              "%s : INVITATION_SEND_SKIPPED : invitation=%a reason=inviter_has_no_email"
              request_token
              Uuidm.pp
              invitation_id);
        record Delivery.Inviter_has_no_email
    | Some identity -> (
        Cloud.send_tenant_invite
          ~config
          ~identity
          ~to_:email
          ~tenant_name
          ~inviter_name:(Sgs_user.name inviter)
          ~inviter_email:(Sgs_user.email inviter)
          ~accept_url
          ~expires_at
            (* Key on the invitation plus its current expiry, not a send counter: [rotate] resets the
             count, so a counter would repeat across re-issues and let the control plane suppress a
             genuinely new link.  Every create and rotate stamps a fresh [expires_at], so
             (id, expires_at) names exactly one minted link and stays stable across retries of the
             same send. *)
          ~idempotency_key:(Uuidm.to_string invitation_id ^ ":" ^ expires_at)
        >>= function
        | Ok (`Emailed, transport) ->
            Logs.info (fun m ->
                m
                  "%s : INVITATION_SEND_OK : invitation=%a transport=%s"
                  request_token
                  Uuidm.pp
                  invitation_id
                  (CCOption.get_or ~default:"?" transport));
            record Delivery.Emailed
        | Ok (`Logged_only, transport) ->
            (* A 2xx that did not deliver: no provider key configured, so the control plane logged it
               instead. *)
            Logs.warn (fun m ->
                m
                  "%s : INVITATION_SEND_UNDELIVERED : invitation=%a transport=%s"
                  request_token
                  Uuidm.pp
                  invitation_id
                  (CCOption.get_or ~default:"?" transport));
            record Delivery.No_provider_key
        | Error `Not_configured_err ->
            (* Self-hosted, or cloud simply not wired up.  Not an error: link-only invitations are a
             supported mode, which is why delivery is best-effort. *)
            Logs.info (fun m ->
                m
                  "%s : INVITATION_SEND_SKIPPED : invitation=%a reason=cloud_not_configured"
                  request_token
                  Uuidm.pp
                  invitation_id);
            record Delivery.Not_configured
        | Error (#Sgs_cloud.err as err) ->
            Logs.err (fun m ->
                m
                  "%s : INVITATION_SEND_FAILED : invitation=%a : %a"
                  request_token
                  Uuidm.pp
                  invitation_id
                  Sgs_cloud.pp_err
                  err);
            record Delivery.Transport_failed)
end
