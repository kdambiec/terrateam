(** GET [/api/v1/invitations/preview?token=]. What the invite landing page shows before the invitee
    has signed in. Unauthenticated: the token is the credential.

    The invited address is masked, so a forwarded or leaked link does not disclose who it was for.
    The reported status distinguishes expired from never-valid, which is what lets the page tell the
    user whether asking for a new invitation would help. *)
val run : Sgs_config.t -> Sgs_storage.t -> string -> Brtl_rtng.Handler.t
