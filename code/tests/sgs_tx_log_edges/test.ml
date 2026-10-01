(* Characterisation of the [attr_path] that {!Sgs_tx_log_edges.edges_of_references}
   attaches to each edge: the tail of a reference beyond the tokens the edge's
   address consumed.

   The attr_path is derived STRUCTURALLY from the reference token list, by
   [Sg_tf_references.attr_path_of_reference].  It used to be recovered textually —
   joining the tokens with ".", stripping the address string off the front, and
   splitting the remainder back on ".".  That was a prefix match on text rather
   than on structure, so it mis-handled a token that reproduces the ".output."
   separator [address_of_reference] synthesises for a module output;
   [module_output_named_output] below is the one case whose result changed.

   Note a module reference emits TWO edges to the same address: the base edge,
   then the rewritten child-output edge (see [rewrite_module_output_ref]).  These
   tests assert every attr_path for an address, in emission order, so a change to
   either edge is visible. *)

let pp_path fmt l = Format.fprintf fmt "[%s]" (CCString.concat "; " l)

let pp_paths fmt ls =
  Format.fprintf
    fmt
    "[%a]"
    (Format.pp_print_list ~pp_sep:(fun fmt () -> Format.fprintf fmt "; ") pp_path)
    ls

let assert_paths expected actual =
  Oth.Assert.eq ~eq:(CCList.equal (CCList.equal CCString.equal)) ~pp:pp_paths expected actual

(* Every attr_path carried by an edge pointing at [to_addr], in emission order. *)
let attr_paths ~to_addr ref_ =
  (* No selectors. This file describes [attr_path], which comes from the token list alone. An empty
     list is also the identity for the selector channel: [selector_of] finds nothing, and the edge
     keeps the [`Null] index that it had before the channel existed. Thus the selector channel does
     not change these expectations. *)
  Sgs_tx_log_edges.edges_of_references
    ~module_address:None
    ~from_depends_on:false
    ~selectors:[]
    (Sg_tf_references.Reference_set.of_list [ ref_ ])
  |> CCList.filter (fun e -> CCString.equal e.Sgs_tx_log_data.Edge.to_addr to_addr)
  |> CCList.map (fun e -> e.Sgs_tx_log_data.Edge.attr_path)

let plain_tail =
  Oth.test ~name:"plain_tail" (fun _ ->
      assert_paths
        [ [ "a"; "b" ] ]
        (attr_paths ~to_addr:"local.config" [ "local"; "config"; "a"; "b" ]);
      ())

let no_tail =
  Oth.test ~name:"no_tail" (fun _ ->
      assert_paths [ [] ] (attr_paths ~to_addr:"local.config" [ "local"; "config" ]);
      ())

let data_consumes_three =
  Oth.test ~name:"data_consumes_three" (fun _ ->
      assert_paths
        [ [ "id" ] ]
        (attr_paths ~to_addr:"data.aws_ami.ubuntu" [ "data"; "aws_ami"; "ubuntu"; "id" ]);
      ())

(* [outputs.X] resolves to the REWRITTEN address [output.X], which is not a
   verbatim prefix of the reference, so no tail is attributed to it. *)
let outputs_root_has_no_attr_path =
  Oth.test ~name:"outputs_root_has_no_attr_path" (fun _ ->
      assert_paths [ [] ] (attr_paths ~to_addr:"output.name" [ "outputs"; "name"; "x" ]);
      ())

(* The ordinary module-output shape: ONE edge, which carries the tail.

   The base edge and the rewritten child-output edge name the SAME address, because
   [address_of_reference] resolves a module read to the output node. Thus both edges together leave
   a whole-value read beside the narrow one. A walk that narrows one edge at a time cannot refuse an
   empty path, thus the narrow edge never gets its answer, and the server admits each reader of each
   attribute. For that reason the code drops the base edge where the tail is not empty. *)
let module_ordinary_output =
  Oth.test ~name:"module_ordinary_output" (fun _ ->
      assert_paths
        [ [ "sub" ] ]
        (attr_paths ~to_addr:"module.m.output.out" [ "module"; "m"; "out"; "sub" ]);
      ())

(* A module read with NO tail keeps its whole-value edge. There is nothing narrower to say, and the
   server must admit a consumer of the whole object whatever member moved. Both spellings stay here
   and both are empty, thus the pair says one thing, and the relation removes the duplicate. *)
let module_whole_output =
  Oth.test ~name:"module_whole_output" (fun _ ->
      assert_paths [ []; [] ] (attr_paths ~to_addr:"module.m.output.out" [ "module"; "m"; "out" ]);
      ())

(* The shape the textual derivation got wrong, and the only expectation this
   commit changes.  A child module whose output is literally named [output] made
   the synthesised address [module.m] ^ ".output." ^ "output" collide with the
   reference's own tokens, so the string prefix test spuriously matched and the
   base edge picked up a tail of ["x"] — not even the right tail, since the
   attribute path inside the node [module.m.output.output] is ["output"; "x"],
   which is what the sibling child-output edge carries.

   Deriving structurally makes the base edge [] like every other module root.
   That over-approximates (an empty path selects the whole attributes object)
   instead of naming the wrong field, so the change is in the safe direction. *)
let module_output_named_output =
  Oth.test ~name:"module_output_named_output" (fun _ ->
      assert_paths
        [ [ "output"; "x" ] ]
        (attr_paths ~to_addr:"module.m.output.output" [ "module"; "m"; "output"; "output"; "x" ]);
      ())

let test =
  Oth.serial
    [
      plain_tail;
      no_tail;
      data_consumes_three;
      outputs_root_has_no_attr_path;
      module_ordinary_output;
      module_whole_output;
      module_output_named_output;
    ]

let () =
  Random.self_init ();
  Oth.run ~file:__FILE__ ~setup:(fun () -> Ok ()) ~teardown:(fun _ -> ()) (fun _ -> test)
