let src = Logs.Src.create "ep_update"

module Logs = (val Logs.src_log src : Logs.LOG)

let run _config storage tenant body =
  let { Sgs_api_components_tenant_update_request.name } = body in
  (* Deliberately [admin_tenant] alone, not the membership-management pair: renaming the tenant is
     administration of the tenant itself, not of its membership.  A holder of [users-manage] scoped
     to this tenant can add and remove members but cannot relabel their workspace. *)
  Sgs_user_session.with_user
    ~caps:(Sgs_user_session.Caps.admin_tenant (Uuidm.to_string (Sgs_tenant.id tenant)))
    ~f:(fun user ->
      Brtl_ep.run_json ~f:(fun ctx ->
          let open Abb.Future.Infix_monad in
          Pgsql_pool.with_conn storage ~f:(fun db ->
              Pgsql_io.tx db ~f:(fun () ->
                  let open Abbs_fc.Infix_result_monad in
                  Sgs_tenant.enforce_user user tenant db
                  >>= fun () -> Sgs_tenant.rename ~name tenant db))
          >>= function
          | Ok renamed ->
              Logs.info (fun m ->
                  m
                    "%s : TENANT_RENAMED : tenant=%a name=%s by=%a"
                    (Brtl_ctx.token ctx)
                    Uuidm.pp
                    (Sgs_tenant.id tenant)
                    (Sgs_tenant.name renamed)
                    Uuidm.pp
                    (Sgs_user.id user));
              let body =
                Yojson.Safe.to_string
                @@ Sgs_api_components_tenant.to_yojson (Sgs_tenant.to_api renamed)
              in
              Abb.Future.return (Brtl_ctx.set_response (Brtl_rspnc.create ~status:`OK body) ctx)
          | Error ((`Name_invalid_err | `Name_conflict_err) as err) ->
              Abb.Future.return
                (Sgs_eplib.respond_tenant_name_err ~tenant:(Sgs_tenant.id tenant) ctx err)
          | Error (`Tenant_not_found_err id) ->
              Logs.warn (fun m ->
                  m "%s : TENANT_NOT_FOUND : tenant=%a" (Brtl_ctx.token ctx) Uuidm.pp id);
              Abb.Future.return
                (Brtl_ctx.set_response (Brtl_rspnc.create ~status:`Not_found "") ctx)
          | Error (#Sgs_eplib.tenant_access_err as err) ->
              Abb.Future.return (Sgs_eplib.respond_tenant_access_err ctx err)))
