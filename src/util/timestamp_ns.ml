(** Unix timestamp.

    These timestamps measure time since the Unix epoch (jan 1, 1970) UTC in
    nanoseconds. *)

type t = int64

let pp_debug out (self : t) = Format.fprintf out "<timestamp: %Ld ns>" self
