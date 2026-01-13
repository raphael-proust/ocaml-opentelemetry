(** Add batching to the emitters of an exporter.

    The exporter has multiple emitters (one per signal type), this can add
    batching on top of each of them (so that they emit less frequent, larger
    batches of signals, amortizing the per-signal cost). *)

open Common_

val add_batching : config:Http_config.t -> OTEL.Exporter.t -> OTEL.Exporter.t
(** Given an exporter, add batches for each emitter according to [config]. *)
