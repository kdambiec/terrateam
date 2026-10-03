(** Emailed tenant invitations: a single-use, revocable link that adds its recipient to a tenant.

    The invitation row lives here rather than in the control plane, which owns email delivery,
    because accepting one must be a single transaction with the membership insert and the capability
    grant. The control plane is only the transport for the message. *)

(** The wire prefix on every token ([sgi_]). Part of the hashed input, so changing it invalidates
    every outstanding link rather than silently accepting both forms. *)
val token_prefix : string

(** Mint a fresh token: 256 bits of CSPRNG output, base64url-encoded, prefixed. The raw value is
    returned to the caller exactly once — only its hash is stored, so it cannot be recovered later.
    That is what makes {!rotate} rather than "show it again" the way to re-issue a link. *)
val mint_token : unit -> string

(** The SHA-256 of a token, as stored. *)
val hash_token : string -> string

(** How many times one invitation may be sent, across the original and every resend. *)
val max_sends : int

module Role : sig
  type t =
    | Member
    | Admin

  val to_string : t -> string
  val of_string : string -> t option
end

module State : sig
  type t =
    | Pending
    | Accepted
    | Revoked
    | Expired

  val to_string : t -> string
  val of_string : string -> t option
end

type err = Pgsql_io.err [@@deriving show]

type create_err =
  [ `Already_pending
  | Pgsql_io.err
  ]
[@@deriving show]

type consume_err =
  [ `Not_found
  | `Expired
  | `Revoked
  | `Already_accepted
  | Pgsql_io.err
  ]
[@@deriving show]

type act_err =
  [ `Not_found
  | `Not_pending
  | `Cooldown
  | `Send_limit
  | Pgsql_io.err
  ]
[@@deriving show]

(** An invitation as a tenant's administrators see it. *)
type t

val id : t -> Uuidm.t
val email : t -> string
val role : t -> Role.t
val state : t -> State.t

(** Whether the invitation has timed out. Computed from [expires_at], not from {!state}: a timed-out
    row keeps [Pending] until its one-live-invitation slot is needed, so the stored state alone
    misreports it. *)
val expired : t -> bool

val send_count : t -> int
val created_at : t -> string
val expires_at : t -> string
val delivered : t -> bool option
val invited_by_name : t -> string

(** What {!create} yields. [created_token] appears here and nowhere else: only its hash is stored,
    so this is the single opportunity to show the caller a working link. *)
type created = {
  created_id : Uuidm.t;
  created_token : string;
  created_at : string;
  created_expires_at : string;
}

(** What {!rotate} yields. Like {!created}, the token appears once and cannot be recovered after. *)
type rotated = {
  rotated_token : string;
  rotated_created_at : string;
  rotated_expires_at : string;
  rotated_email : string;
  rotated_role : Role.t;
  rotated_tenant_name : string;
}

(** What {!consume} yields, so the caller can complete the join in the same transaction. *)
type accepted = {
  accepted_id : Uuidm.t;
      (** The accepted invitation's own id. The caller uses it only to name the invitation in the
          audit log, not to perform the join. *)
  accepted_tenant_id : Uuidm.t;
      (** The tenant the invitee is added to. It's what actually drives the join: the membership
          insert and, for [Role.Admin], the admin-over-this-tenant capability patch. *)
  accepted_email : string;
      (** The address the invitation was issued to. The accepting user need not own it (the link is
          the credential), so the caller compares it against the session email only to record a
          mismatch, never to block. *)
  accepted_role : Role.t;
      (** The offered role. [Role.Member] means the membership row is the whole grant; [Role.Admin]
          additionally patches the user's capabilities with admin over [accepted_tenant_id]. *)
}

(** What the unauthenticated preview needs, before the address is masked for the response. *)
type preview = {
  preview_tenant_id : Uuidm.t;
  preview_tenant_name : string;
  preview_email : string;
  preview_role : Role.t;
  preview_state : State.t;
  preview_expires_at : string;
  preview_expired : bool;
  preview_inviter_name : string;
}

(** [create ~ttl_hours ~email ~role ~invited_by ~tenant_id db] creates a pending invitation and
    returns its id, its {i one-shot} raw token, and its timestamps.

    The grant the invitee will receive is materialised now, so a later change to the inviter's own
    authority cannot retroactively change what was offered. [Role.Admin] always names this one
    tenant and never an absent tenants list, which would be installation-wide.

    Any timed-out pending invitation for the same address is expired first, freeing the
    one-live-invitation slot. Fails with [`Already_pending] when a genuinely live invitation for
    that address exists — the caller should resend rather than mint a second link. *)
val create :
  ttl_hours:int ->
  email:string ->
  role:Role.t ->
  invited_by:Uuidm.t ->
  tenant_id:Uuidm.t ->
  Pgsql_io.t ->
  (created, [> create_err ]) result Abb.Future.t

(** [consume ~token ~user_id db] accepts an invitation on behalf of a user.

    A single UPDATE guarded on state and expiry, so two concurrent accepts of the same token
    serialise on the row lock and exactly one wins. Run inside a transaction together with the
    membership insert and, for [Role.Admin], the capability grant. *)
val consume :
  token:string -> user_id:Uuidm.t -> Pgsql_io.t -> (accepted, [> consume_err ]) result Abb.Future.t

(** Read an invitation by token for the unauthenticated preview. Returns [None] when no invitation
    has that token. *)
val preview : token:string -> Pgsql_io.t -> (preview option, [> err ]) result Abb.Future.t

(** A page of a tenant's invitations, newest first, and the tenant's total invitation count.
    [cursor] is the [(created_at, id)] of the last row of the previous page — the full sort key, so
    invitations created in the same instant are not skipped or repeated across a page boundary. *)
val list :
  ?cursor:string * Uuidm.t ->
  limit:int ->
  tenant_id:Uuidm.t ->
  Pgsql_io.t ->
  (t list * int, [> err ]) result Abb.Future.t

(** Revoke a pending invitation, killing its outstanding link before the TTL would have. *)
val revoke :
  id:Uuidm.t ->
  tenant_id:Uuidm.t ->
  user_id:Uuidm.t ->
  Pgsql_io.t ->
  (unit, [> `Not_found | Pgsql_io.err ]) result Abb.Future.t

(** [rotate ~ttl_hours ~id ~tenant_id db] re-issues a pending invitation under a fresh token,
    resetting its lifetime, and returns the new {i one-shot} link material.

    There is deliberately no "resend the same link" variant, because there cannot be one: only the
    token's hash is stored, so the original is unrecoverable the moment it leaves {!create}.
    Offering resend and rotate separately would be two names for this one operation, and would imply
    a guarantee — that the old link keeps working — the storage model cannot honour. Callers must
    tell the recipient the previous link is dead.

    Enforces the resend cooldown and {!max_sends} here rather than in the endpoint, so a second
    caller cannot bypass them.

    [authorize_role] is asked whether the caller may hand out the role stored on the invitation, and
    a [false] answer fails with [`Not_authorized]. It is consulted as soon as the row is read and
    before every other check, so an unauthorized caller cannot tell a refusal apart from a cooldown,
    a spent send budget or an already-accepted invitation. The role only becomes known here, which
    is why the caller cannot make this decision in its [~caps] predicate. *)
val rotate :
  ttl_hours:int ->
  authorize_role:(Role.t -> bool) ->
  id:Uuidm.t ->
  tenant_id:Uuidm.t ->
  Pgsql_io.t ->
  (rotated, [> act_err | `Not_authorized ]) result Abb.Future.t

(** [record_send ~delivered ~id db] records a delivery attempt. [delivered] is three-valued: [None]
    when no attempt was made at all, [Some false] when one was made but the message was not
    delivered, [Some true] when the provider accepted it. *)
val record_send :
  delivered:bool option -> id:Uuidm.t -> Pgsql_io.t -> (unit, [> err ]) result Abb.Future.t

(** Invitations this user created within the last [hours] hours, for the per-inviter rate limit. *)
val count_by_inviter :
  hours:int -> invited_by:Uuidm.t -> Pgsql_io.t -> (int, [> err ]) result Abb.Future.t

(** Live invitations outstanding for this tenant, for the per-tenant cap. *)
val count_pending : tenant_id:Uuidm.t -> Pgsql_io.t -> (int, [> err ]) result Abb.Future.t
