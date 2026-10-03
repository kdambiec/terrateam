(** POST [/api/v1/tenants]. Create a tenant and add the calling installation administrator as a
    member. *)
val run :
  Sgs_config.t -> Sgs_storage.t -> Sgs_api_components_tenant_create_request.t -> Brtl_rtng.Handler.t

module Tests : sig
  type run_prime_err =
    [ Pgsql_io.err
    | Pgsql_pool.err
    | `Name_conflict_err
    | `Name_invalid_err
    ]

  val run' :
    Sgs_storage.t ->
    'a Sgs_user.t ->
    string ->
    (Sgs_tenant.stored Sgs_tenant.t, [> run_prime_err ]) result Abb.Future.t
end
