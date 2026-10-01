(** Migration body for #685: convert hcl_refs from the lossy [raw_refs] shape to the structured
    per-edge shape ([attr_path], [is_bare], [resolvable], [from_depends_on], [index_kind],
    [index_val]). Extracted from [Sgs_migrations] so the (substantial) re-derivation logic lives in
    its own file. *)
val run : Pgsql_io.t -> ([> `Sync ], [> Pgsql_io.err ]) result Abb.Future.t
