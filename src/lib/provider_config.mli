(** Per-provider batching configuration. *)

type t = {
  batch: int option;
      (** Batch size (number of items). [None] means unbatched (immediate emit).
      *)
  timeout: Mtime.Span.t;  (** Timeout between automatic batch flushes. *)
}

val make : ?batch:int -> ?timeout:Mtime.Span.t -> unit -> t
(** Create a provider config.
    @param batch batch size. Default: [Some 200].
    @param timeout flush timeout. Default: [2000ms] *)

val default : t
(** Default provider config: [200] batch size, [2s] timeout. *)
