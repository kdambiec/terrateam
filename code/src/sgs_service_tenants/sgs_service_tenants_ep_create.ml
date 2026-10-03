let src = Logs.Src.create "ep_create"

module Logs = (val Logs.src_log src : Logs.LOG)
module Fc = Abbs_fc

(* Create a tenant and make the calling administrator a member of it. Installation admin only, so
   the caller already administers every tenant; membership is what makes the new one show up for
   them and pass the tenant-membership checks. No capability is written: the installation-wide
   admin grant required to create a tenant already covers the new tenant. *)
let run' storage user name =
  let open Fc.Infix_result_monad in
  Pgsql_pool.with_conn storage ~f:(fun db ->
      Pgsql_io.tx db ~f:(fun () ->
          Sgs_tenant.create name db
          >>= fun tenant -> Sgs_tenant.add_user tenant user db >>| fun () -> tenant))

let run _config storage body =
  let { Sgs_api_components_tenant_create_request.name } = body in
  Sgs_user_session.with_user ~caps:Sgs_user_session.Caps.admin_instance ~f:(fun user ->
      Brtl_ep.run_json ~f:(fun ctx ->
          let open Abb.Future.Infix_monad in
          run' storage user name
          >>= function
          | Ok tenant ->
              Logs.info (fun m ->
                  m
                    "%s : TENANT_CREATED : tenant=%a by=%a"
                    (Brtl_ctx.token ctx)
                    Uuidm.pp
                    (Sgs_tenant.id tenant)
                    Uuidm.pp
                    (Sgs_user.id user));
              let body =
                Yojson.Safe.to_string
                @@ Sgs_api_components_tenant.to_yojson (Sgs_tenant.to_api tenant)
              in
              Abb.Future.return
                (Brtl_ctx.set_response (Brtl_rspnc.create ~status:`Created body) ctx)
          | Error ((`Name_invalid_err | `Name_conflict_err) as err) ->
              Abb.Future.return (Sgs_eplib.respond_tenant_name_err ctx err)
          | Error ((#Pgsql_io.err | #Pgsql_pool.err) as err) ->
              Abb.Future.return (Sgs_eplib.respond_db_err ctx err)))

module Tests = struct
  type run_prime_err =
    [ Pgsql_io.err
    | Pgsql_pool.err
    | `Name_conflict_err
    | `Name_invalid_err
    ]

  let run' = run'
end
