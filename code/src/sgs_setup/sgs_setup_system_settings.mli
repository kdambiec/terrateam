(** Installation-wide settings, stored as JSON values by key in the [system_settings] table. *)

(** [fetch key db] is the value stored under [key], or [None] when no value is stored. *)
val fetch : string -> Pgsql_io.t -> (Yojson.Safe.t option, [> Pgsql_io.err ]) result Abb.Future.t

(** [store key value db] stores [value] under [key], and replaces the value already stored there. *)
val store : string -> Yojson.Safe.t -> Pgsql_io.t -> (unit, [> Pgsql_io.err ]) result Abb.Future.t
