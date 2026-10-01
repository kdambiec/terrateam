let src = Logs.Src.create "sgs_migrations_ex_capability_trie"

module Logs = (val Logs.src_log src : Logs.LOG)
module Ts = Pgsql_io.Typed_sql
module Ps = Pgsql_io.Prepared_stmt

let chunk_limit = 1000

let fail msg =
  Logs.err (fun m -> m "CAPABILITY_TRIE : %s" msg);
  failwith ("capability trie migration: " ^ msg)

let rewritten ~table ~id json =
  match Sgs_session_caps_capabilities.of_yojson json with
  | Error msg -> Error (Printf.sprintf "%s %s does not decode: %s" table id msg)
  | Ok legacy -> (
      match Sg_caps_legacy_conversion.convert legacy with
      | Ok caps -> Ok (Sg_caps_wire_capabilities.to_yojson (Sg_caps_json.to_wire caps))
      | Error (`Invalid_pattern_err pattern) ->
          Error
            (Printf.sprintf
               "%s %s holds the pattern %S, which the capability model cannot express"
               table
               id
               pattern))

let backfill db ~table ~source ~target =
  let open Abbs_fc.Infix_result_monad in
  let select =
    Ts.(
      sql
      // Ret.uuid
      // Ret.jsonb
      /^ Printf.sprintf
           "select id, %s from %s where id > $cursor and %s is null order by id limit $limit"
           source
           table
           target
      /% Var.uuid "cursor"
      /% Var.integer "limit")
  in
  let update =
    Ts.(
      sql
      /^ Printf.sprintf "update %s set %s = $rules where id = $id" table target
      /% Var.json "rules"
      /% Var.uuid "id")
  in
  let write (id, json) =
    match rewritten ~table ~id:(Uuidm.to_string id) json with
    | Ok rules -> Ps.execute db update rules id
    | Error msg -> fail msg
  in
  let rec loop ~cursor ~total =
    Ps.fetch db select ~f:(fun id caps -> (id, caps)) cursor (Int32.of_int chunk_limit)
    >>= function
    | [] ->
        Logs.info (fun m -> m "CAPABILITY_TRIE : %s.%s : %d rows" table target total);
        Abbs_fc.return_ok ()
    | rows ->
        Abbs_fc.List_result.iter ~f:write rows
        >>= fun () ->
        let last_id, _ = CCList.last_opt rows |> CCOption.get_exn_or "non-empty chunk" in
        loop ~cursor:last_id ~total:(total + CCList.length rows)
  in
  loop ~cursor:Uuidm.nil ~total:0

(* The default capabilities of a new user are a settings row rather than a table, so they get a key
   of their own instead of a column. *)
let backfill_default_caps db =
  let open Abbs_fc.Infix_result_monad in
  let select =
    Ts.(sql // Ret.jsonb /^ "select value from system_settings where key = 'default_user_caps'")
  in
  let insert =
    Ts.(
      sql
      /^ "insert into system_settings (key, value) values ('default_user_capability_trie', $value) \
          on conflict (key) do nothing"
      /% Var.json "value")
  in
  Ps.fetch db select ~f:CCFun.id
  >>= function
  | [] ->
      Logs.info (fun m -> m "CAPABILITY_TRIE : no default_user_caps setting to convert");
      Abbs_fc.return_ok ()
  | value :: _ -> (
      match rewritten ~table:"system_settings" ~id:"default_user_caps" value with
      | Ok rules -> Ps.execute db insert rules
      | Error msg -> fail msg)

let run db =
  let open Abbs_fc.Infix_result_monad in
  Logs.info (fun m -> m "CAPABILITY_TRIE : backfilling");
  backfill db ~table:"users" ~source:"capabilities" ~target:"capability_trie"
  >>= fun () ->
  backfill db ~table:"users" ~source:"base_capabilities" ~target:"base_capability_trie"
  >>= fun () ->
  backfill db ~table:"access_tokens" ~source:"capabilities" ~target:"capability_trie"
  >>= fun () ->
  backfill db ~table:"caps_group_rules" ~source:"capabilities" ~target:"capability_trie"
  >>= fun () ->
  backfill_default_caps db
  >>| fun () ->
  Logs.info (fun m -> m "CAPABILITY_TRIE : complete");
  `Sync
