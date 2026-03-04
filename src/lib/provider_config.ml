(** Per-provider batching configuration. *)

type t = {
  batch: int option;
  timeout: Mtime.Span.t;
}

let make ?(batch : int option) ?(timeout = Mtime.Span.(2_000 * ms)) () : t =
  { batch; timeout }

let default : t = make ()
