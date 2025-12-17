open Opentelemetry_atomic

type t = { now: unit -> Timestamp_ns.t } [@@unboxed]
(** A clock: can get the current timestamp, with nanoseconds precision *)

let[@inline] now (self : t) : Timestamp_ns.t = self.now ()

(** Clock using {!Unix.gettimeofday} *)
let unix : t =
  { now = (fun () -> Int64.of_float (Unix.gettimeofday () *. 1e9)) }

module Main = struct
  open struct
    let main : t Atomic.t = Atomic.make unix
  end

  let[@inline] get () = Atomic.get main

  let set t : unit = Util_atomic.update_cas main (fun _ -> (), t)

  (** Clock that always defers to the current main clock *)
  let dynamic_main : t = { now = (fun () -> now (get ())) }
end

(** Timestamp using the main clock *)
let[@inline] now_main () = now (Main.get ())
