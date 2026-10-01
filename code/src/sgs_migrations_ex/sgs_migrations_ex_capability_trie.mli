(** Migration body for the capability columns the decision-tree model reads: every stored capability
    value is read as the legacy record and written into the column beside it, leaving the legacy
    columns as they were. Extracted from {!Sgs_migrations} so the conversion is not buried in the
    migration list.

    A row whose capabilities do not convert raises, naming the row and the pattern, rather than
    storing something weaker than what was granted. The migration is then unapplied and the server
    does not start. *)
val run : Pgsql_io.t -> ([> `Sync ], [> Pgsql_io.err ]) result Abb.Future.t
