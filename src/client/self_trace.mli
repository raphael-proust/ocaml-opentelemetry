(** Mini tracing module for OTEL itself.

    When enabled via {!set_enabled}, emits spans via the current
    {!OTEL.Trace_provider}. Disabled by default. *)

open Common_

val add_event : OTEL.Span.t -> OTEL.Event.t -> unit

val with_ :
  ?kind:OTEL.Span_kind.t ->
  ?attrs:(string * OTEL.value) list ->
  string ->
  (OTEL.Span.t -> 'a) ->
  'a
(** Instrument a section of SDK code with a span. No-ops when disabled. *)

val set_enabled : bool -> unit
(** Enable or disable self-tracing. When enabled, uses the current
    {!OTEL.Trace_provider} to emit spans. *)
