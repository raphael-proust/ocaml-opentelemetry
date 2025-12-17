open Opentelemetry_emitter

type t = {
  emit: Metrics.t Emitter.t;
  clock: Clock.t;
}

let dummy : t = { emit = Emitter.dummy; clock = Clock.ptime_clock }

let[@inline] enabled (self : t) = Emitter.enabled self.emit

let of_exporter (exp : Exporter.t) : t =
  { emit = exp.emit_metrics; clock = exp.clock }

let dynamic_main : t =
  Main_exporter.dynamic_forward_to_main_exporter |> of_exporter

(** Emit some metrics to the collector (sync). This blocks until the backend has
    pushed the metrics into some internal queue, or discarded them. *)
let (emit [@deprecated "use an explicit Metrics_emitter.t"]) =
 fun ?attrs:_ (l : Metrics.t list) : unit ->
  match Main_exporter.get () with
  | None -> ()
  | Some exp -> Exporter.send_metrics exp l

let[@inline] emit1 (self : t) (m : Metrics.t) : unit =
  Emitter.emit self.emit [ m ]
