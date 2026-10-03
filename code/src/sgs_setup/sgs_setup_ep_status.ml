let src = Logs.Src.create "ep_status"

module Logs = (val Logs.src_log src : Logs.LOG)

let response ~needs_setup ~mode =
  let body =
    Yojson.Safe.to_string
    @@ Sgs_api_components_setup_status_response.to_yojson
         { Sgs_api_components_setup_status_response.mode; needs_setup }
  in
  Brtl_rspnc.create ~status:`OK body

let internal_server_error () = Brtl_rspnc.create ~status:`Internal_server_error ""

module Make (Cloud : Sgs_cloud.S) = struct
  let run storage =
    Brtl_ep.run_json ~f:(fun ctx ->
        let open Abb.Future.Infix_monad in
        let token = Brtl_ctx.token ctx in
        let mode = Cloud.api_mode () in
        match Cloud.setup () with
        | `Out_of_band ->
            Logs.debug (fun m -> m "%s : SETUP_STATUS_OUT_OF_BAND" token);
            Abb.Future.return (Brtl_ctx.set_response (response ~needs_setup:false ~mode) ctx)
        | `In_app -> (
            Pgsql_pool.with_conn storage ~f:(fun db ->
                Sgs_setup_system_settings.fetch "setup_completed" db)
            >>= function
            | Ok (Some value) ->
                let needs_setup = not (Yojson.Safe.equal value (`Bool true)) in
                Abb.Future.return (Brtl_ctx.set_response (response ~needs_setup ~mode) ctx)
            | Ok None ->
                Abb.Future.return (Brtl_ctx.set_response (response ~needs_setup:true ~mode) ctx)
            | Error (#Pgsql_pool.err as err) ->
                Logs.err (fun m -> m "%s : DB_POOL_ERR : %a" token Pgsql_pool.pp_err err);
                Abb.Future.return (Brtl_ctx.set_response (internal_server_error ()) ctx)
            | Error (#Pgsql_io.err as err) ->
                Logs.err (fun m -> m "%s : DB_IO_ERR : %a" token Pgsql_io.pp_err err);
                Abb.Future.return (Brtl_ctx.set_response (internal_server_error ()) ctx)))
end
