(** Unix timestamp.

    These timestamps measure time since the Unix epoch (jan 1, 1970) UTC in
    nanoseconds. *)

type t = int64

open struct
  let ns_in_a_day = Int64.(mul 1_000_000_000L (of_int (24 * 3600)))
end

let pp_debug out (self : t) =
  let d = Int64.(to_int (div self ns_in_a_day)) in
  let ns = Int64.(rem self ns_in_a_day) in
  let ps = Int64.(mul ns 1_000L) in
  match Ptime.Span.of_d_ps (d, ps) with
  | None -> Format.fprintf out "ts: <%Ld ns>" self
  | Some span ->
    (match Ptime.add_span Ptime.epoch span with
    | None -> Format.fprintf out "ts: <%Ld ns>" self
    | Some ptime -> Ptime.pp_rfc3339 ~space:false ~frac_s:6 () out ptime)
