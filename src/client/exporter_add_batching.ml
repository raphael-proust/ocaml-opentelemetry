(** Add batching to the emitters of an exporter.

    The exporter has multiple emitters (one per signal type), this can add
    batching on top of each of them (so that they emit less frequent, larger
    batches of signals, amortizing the per-signal cost). *)

open Common_

(** Given an exporter, add batches for each emitter according to [config]. *)
let add_batching ~(config : Http_config.t) (exp : OTEL.Exporter.t) :
    OTEL.Exporter.t =
  let timeout = Mtime.Span.(config.batch_timeout_ms * ms) in

  let emit_spans =
    Emitter_add_batching.add_batching_opt ~timeout
      ~batch_size:config.batch_traces exp.emit_spans
  in
  let emit_metrics =
    Emitter_add_batching.add_batching_opt ~timeout
      ~batch_size:config.batch_metrics exp.emit_metrics
  in
  let emit_logs =
    Emitter_add_batching.add_batching_opt ~timeout ~batch_size:config.batch_logs
      exp.emit_logs
  in

  let active = exp.active in
  let tick = exp.tick in
  let on_tick = exp.on_tick in
  let clock = exp.clock in

  let self_metrics () = exp.self_metrics () in
  let shutdown () =
    let open Opentelemetry_emitter in
    Emitter.flush_and_close emit_spans;
    Emitter.flush_and_close emit_metrics;
    Emitter.flush_and_close emit_logs;

    exp.shutdown ()
  in

  {
    OTEL.Exporter.active;
    clock;
    emit_spans;
    emit_metrics;
    emit_logs;
    on_tick;
    tick;
    shutdown;
    self_metrics;
  }
