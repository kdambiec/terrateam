(** The structured edges of a configuration item, derived from the references it makes, in the shape
    that [hcl_refs] stores. *)

(** [qualify_address module_address addr] prefixes [addr] with [module_address]: a child module's
    local [var.abc123] becomes [module.child.var.abc123], the full address its node is stored under.
*)
val qualify_address : string -> string -> string

(** Convert a reference set into the edges that flow through [transaction_logs.data->'edges'] and
    into [hcl_refs] / [hcl_ref_edges] at apply time. A reference yields zero, one or several edges:
    [module.m.out.sub] yields an edge to [module.m.output.out] with attr_path [["sub"]] and a bare
    edge to [module.m]. [from_depends_on] tags the resulting edges; pass [true] when [refs] came
    from [Sg_tf_references.depends_on_references] and [false] otherwise. [selectors] pairs the token
    list of a reference with the member that the reference names without an evaluation. It goes onto
    the edge as [index_kind] and [index_val]; both stay null for a reference without a selector. *)
val edges_of_references :
  module_address:string option ->
  from_depends_on:bool ->
  selectors:(string list * Sg_tf_references.Selector.t) list ->
  Sg_tf_references.Reference_set.t ->
  Sgs_tx_log_data.Edge.t list
