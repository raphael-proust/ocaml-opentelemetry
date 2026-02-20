open Opentelemetry_emitter

type t = {
  emit: Metrics.t Emitter.t;
  clock: Clock.t;
}

let dummy : t = { emit = Emitter.dummy; clock = Clock.ptime_clock }

let[@inline] enabled (self : t) = Emitter.enabled self.emit

let of_exporter (exp : Exporter.t) : t =
  { emit = exp.emit_metrics; clock = exp.clock }

let (create [@deprecated "use Meter.of_exporter"]) =
 fun ~(exporter : Exporter.t) ?name:_name () : t -> of_exporter exporter

let default : t = Main_exporter.dynamic_forward_to_main_exporter |> of_exporter

let[@inline] emit1 (self : t) (m : Metrics.t) : unit =
  Emitter.emit self.emit [ m ]

(** Global list of raw metric callbacks, collected alongside {!Instrument.all}.
*)
let cbs_ : (clock:Clock.t -> unit -> Metrics.t list) Alist.t = Alist.make ()

let add_cb (f : clock:Clock.t -> unit -> Metrics.t list) : unit =
  Alist.add cbs_ f

let collect (self : t) : Metrics.t list =
  let clock = self.clock in
  let acc = ref [] in
  Instrument.Internal.iter_all (fun f ->
      acc := List.rev_append (f ~clock ()) !acc);
  List.iter
    (fun f -> acc := List.rev_append (f ~clock ()) !acc)
    (Alist.get cbs_);
  List.rev !acc

let minimum_min_interval_ = Mtime.Span.(100 * ms)

let default_min_interval_ = Mtime.Span.(4 * s)

let clamp_interval_ interval =
  if Mtime.Span.is_shorter interval ~than:minimum_min_interval_ then
    minimum_min_interval_
  else
    interval

let add_to_exporter ?(min_interval = default_min_interval_) (exp : Exporter.t)
    (self : t) : unit =
  let limiter =
    Interval_limiter.create ~min_interval:(clamp_interval_ min_interval) ()
  in
  Exporter.on_tick exp (fun () ->
      if Interval_limiter.make_attempt limiter then (
        let metrics = collect self in
        if metrics <> [] then Emitter.emit self.emit metrics
      ))

let add_to_main_exporter ?(min_interval = default_min_interval_) (self : t) :
    unit =
  let limiter =
    Interval_limiter.create ~min_interval:(clamp_interval_ min_interval) ()
  in
  Main_exporter.add_on_tick_callback (fun () ->
      if Interval_limiter.make_attempt limiter then (
        let metrics = collect self in
        if metrics <> [] then Emitter.emit self.emit metrics
      ))

module Instrument = Instrument

module type INSTRUMENT_IMPL = Instrument.CUSTOM_IMPL

module Make_instrument = Instrument.Make
module Int_counter = Instrument.Int_counter
module Float_counter = Instrument.Float_counter
module Int_gauge = Instrument.Int_gauge
module Float_gauge = Instrument.Float_gauge
module Histogram = Instrument.Histogram
