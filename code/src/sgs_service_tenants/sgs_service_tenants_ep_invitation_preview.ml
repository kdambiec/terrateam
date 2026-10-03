let src = Logs.Src.create "ep_invitation_preview"

module Logs = (val Logs.src_log src : Logs.LOG)
module Common = Sgs_service_tenants_invitation_common
module Inv = Sgs_service_tenants_invitation

(* Unauthenticated: the token IS the credential, so there is no session to gate on.  The response is
   deliberately minimal -- tenant name, who invited them, the role, when it expires -- and the address
   is masked, because a link that was forwarded or leaked must not disclose its original recipient to
   whoever now holds it.

   Distinct statuses for not-found / expired / revoked / already-accepted are safe and worth the UX:
   reaching any of them requires holding a real token, which takes 256 bits of guessing, and the
   difference between "this link expired, ask for a new one" and "this link was never valid" is the
   difference between a user who can recover and one who cannot. *)
let run _config storage token =
  Brtl_ep.run_json ~f:(fun ctx ->
      let open Abb.Future.Infix_monad in
      Pgsql_pool.with_conn storage ~f:(fun db -> Inv.preview ~token db)
      >>= function
      | Ok None ->
          Logs.warn (fun m -> m "%s : INVITATION_PREVIEW_NOT_FOUND" (Brtl_ctx.token ctx));
          Abb.Future.return (Common.respond_consume_err ctx `Not_found)
      | Ok (Some preview) ->
          let status =
            match (preview.Inv.preview_state, preview.Inv.preview_expired) with
            | Inv.State.Pending, true -> `Expired
            | Inv.State.Pending, false -> `Pending
            | Inv.State.Accepted, _ -> `Accepted
            | Inv.State.Revoked, _ -> `Revoked
            | Inv.State.Expired, _ -> `Expired
          in
          let body =
            Yojson.Safe.to_string
            @@ Sgs_api_components_invitation_preview_response.to_yojson
                 {
                   Sgs_api_components_invitation_preview_response.tenant_name =
                     preview.Inv.preview_tenant_name;
                   inviter_name = preview.Inv.preview_inviter_name;
                   invited_email_masked = Common.mask_email preview.Inv.preview_email;
                   role = Common.api_role preview.Inv.preview_role;
                   status;
                   expires_at = preview.Inv.preview_expires_at;
                 }
          in
          Abb.Future.return (Common.respond_json ~status:`OK body ctx)
      | Error (#Pgsql_pool.err as err) ->
          Logs.err (fun m -> m "%s : DB_POOL_ERROR : %a" (Brtl_ctx.token ctx) Pgsql_pool.pp_err err);
          Abb.Future.return (Sgs_eplib.respond_internal_error ctx)
      | Error (#Pgsql_io.err as err) ->
          Logs.err (fun m -> m "%s : DB_ERROR : %a" (Brtl_ctx.token ctx) Pgsql_io.pp_err err);
          Abb.Future.return (Sgs_eplib.respond_internal_error ctx))
