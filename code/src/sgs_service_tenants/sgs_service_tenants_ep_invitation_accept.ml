let src = Logs.Src.create "ep_invitation_accept"

module Logs = (val Logs.src_log src : Logs.LOG)
module Common = Sgs_service_tenants_invitation_common
module Invitation = Sgs_service_tenants_invitation

(* Accept happens AFTER the invitee has signed in, rather than inside the OAuth callback.

   Threading the token through the OAuth round trip would mean deciding, mid-redirect, what to do when
   the token turns out to be invalid: fail the whole signup (locking someone out of the product
   because a link expired) or create the account without the membership (a half-success that a redirect
   chain cannot explain).  Deferring makes the two independently retryable, and lets a real page render
   the outcome.

   It also means all three arrival cases -- already signed in, has an account but signed out, no account
   at all -- run identical server code.  They differ only in what the browser does first, because
   find_or_create_user keys on (auth_origin, external_id) and is idempotent. *)
let accept storage ~except_login_session user token =
  let open Abbs_fc.Infix_result_monad in
  Pgsql_pool.with_conn storage ~f:(fun db ->
      Pgsql_io.tx db ~f:(fun () ->
          Invitation.consume ~token ~user_id:(Sgs_user.id user) db
          >>= fun accepted ->
          let tenant = Sgs_tenant.make ~id:accepted.Invitation.accepted_tenant_id () in
          (* Was the user already a member? Reported so the page can say "you already had access"
             rather than implying the invitation did the work. *)
          Sgs_tenant.find_member tenant (Sgs_user.id user) db
          >>= fun existing ->
          (* Always add the user to the tenant, no matter the role the invitation contains *)
          Sgs_tenant.add_user_idempotent tenant user db
          >>= fun () ->
          (match accepted.Invitation.accepted_role with
            | Invitation.Role.Member -> Abbs_fc.return_ok ()
            | Invitation.Role.Admin ->
                (* An admin invitation merges the grant into the user's capabilities. We have to make
                   sure that the user's final capability does contain the admin right, so we don't blindly
                   union. That is the goal of the dedicated Sgs_user.grant_tenant function *)
                Sgs_user.grant_tenant
                  ?except_login_session
                  ~grants:[ `Admin ]
                  ~tenant_id:accepted.Invitation.accepted_tenant_id
                  user
                  db
                >>| fun _ -> ())
          >>= fun () ->
          Sgs_tenant.fetch tenant db
          >>? fun stored ->
          match stored with
          | Some tenant -> Ok (accepted, Sgs_tenant.name tenant, CCOption.is_some existing)
          | None ->
              (* Unreachable: [consume]'s tenant_id and the [add_user_idempotent] above both FK-reference
                 tenants(id), so the row provably exists. Reaching here means the database is
                 inconsistent, so fail ([run] below turns it into a 500) rather than return a blank
                 name. The failing transaction rolls the accept back, which is harmless: a missing
                 tenant means the membership insert could not have committed either. *)
              Error (`Tenant_missing_err accepted.Invitation.accepted_tenant_id)))

(* Whether the signed-in user's address differs from the one the invitation was sent to. Comparison
   is case-insensitive, and an absent session email counts as a mismatch -- it cannot be shown to
   match. This never blocks the accept (see [run]); it is only recorded and surfaced. *)
let email_mismatch ~session_email ~invited_email =
  match session_email with
  | Some session_email ->
      not
        (CCString.equal
           (CCString.lowercase_ascii session_email)
           (CCString.lowercase_ascii invited_email))
  | None -> true

let run _config storage body =
  let { Sgs_api_components_invitation_accept_request.token } = body in
  Sgs_user_session.with_session ~caps:Sgs_user_session.Caps.allow_all ~f:(fun session ->
      Brtl_ep.run_json ~f:(fun ctx ->
          let open Abb.Future.Infix_monad in
          let user = Sgs_user_session.Session.user session in
          (* Accepting an admin invitation grants the acting user a capability, which would otherwise
             revoke their own login session and 401 their next request (poor UX). So keep the current session,
             as it is safe to leave an under-privileged session around until the next sign-in. *)
          let except_login_session =
            match Sgs_user_session.Session.expiration session with
            | Sgs_user_session.Session.Expiration.Access_token id -> Some id
            | Sgs_user_session.Session.Expiration.Duration _ -> None
          in
          accept storage ~except_login_session user token
          >>= function
          | Ok (accepted, tenant_name, already_member) ->
              (* Policy: the link is the credential, and any authenticated user holding it may accept.
                 users.email is nullable and is never re-synced after first sign-in, so a strict match
                 would permanently lock out users whose stored address is absent or stale. The
                 mismatch is recorded and returned so the UI can interstitial it, and accepted_by on
                 the row is the audit trail. *)
              let email_mismatch =
                email_mismatch
                  ~session_email:(Sgs_user.email user)
                  ~invited_email:accepted.Invitation.accepted_email
              in
              if email_mismatch then
                Logs.warn (fun m ->
                    m
                      "%s : INVITATION_ACCEPT_EMAIL_MISMATCH : invitation=%a accepted_by=%a"
                      (Brtl_ctx.token ctx)
                      Uuidm.pp
                      accepted.Invitation.accepted_id
                      Uuidm.pp
                      (Sgs_user.id user));
              Logs.info (fun m ->
                  m
                    "%s : INVITATION_ACCEPTED : invitation=%a tenant=%a by=%a already_member=%b"
                    (Brtl_ctx.token ctx)
                    Uuidm.pp
                    accepted.Invitation.accepted_id
                    Uuidm.pp
                    accepted.Invitation.accepted_tenant_id
                    Uuidm.pp
                    (Sgs_user.id user)
                    already_member);
              let body =
                Yojson.Safe.to_string
                @@ Sgs_api_components_invitation_accept_response.to_yojson
                     {
                       Sgs_api_components_invitation_accept_response.tenant_id =
                         Uuidm.to_string accepted.Invitation.accepted_tenant_id;
                       tenant_name;
                       already_member;
                       email_mismatch;
                     }
              in
              Abb.Future.return (Common.respond_json ~status:`OK body ctx)
          | Error `Not_found ->
              Logs.warn (fun m ->
                  m "%s : INVITATION_ACCEPT_FAILED : not_found" (Brtl_ctx.token ctx));
              Abb.Future.return (Common.respond_consume_err ctx `Not_found)
          | Error `Expired ->
              Logs.warn (fun m -> m "%s : INVITATION_ACCEPT_FAILED : expired" (Brtl_ctx.token ctx));
              Abb.Future.return (Common.respond_consume_err ctx `Expired)
          | Error `Revoked -> Abb.Future.return (Common.respond_consume_err ctx `Revoked)
          | Error `Already_accepted ->
              Abb.Future.return (Common.respond_consume_err ctx `Already_accepted)
          | Error (`Tenant_missing_err tenant_id) ->
              (* Unreachable in a consistent database (see [accept]): a 500 rather than a blank name. *)
              Logs.err (fun m ->
                  m
                    "%s : INVITATION_ACCEPT_TENANT_MISSING : tenant=%a"
                    (Brtl_ctx.token ctx)
                    Uuidm.pp
                    tenant_id);
              Abb.Future.return (Sgs_eplib.respond_internal_error ctx)
          | Error (#Sgs_user.tenant_grant_err as err) ->
              Logs.err (fun m ->
                  m
                    "%s : INVITATION_GRANT_FAILED : %a"
                    (Brtl_ctx.token ctx)
                    Sgs_user.pp_tenant_grant_err
                    err);
              Abb.Future.return (Sgs_eplib.respond_internal_error ctx)
          | Error (#Pgsql_pool.err as err) ->
              Logs.err (fun m ->
                  m "%s : DB_POOL_ERROR : %a" (Brtl_ctx.token ctx) Pgsql_pool.pp_err err);
              Abb.Future.return (Sgs_eplib.respond_internal_error ctx)))
