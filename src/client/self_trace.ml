open Common_

let enabled = Atomic.make false

let[@inline] add_event (scope : OTEL.Span.t) ev = OTEL.Span.add_event scope ev

let set_enabled b = Atomic.set enabled b

let with_ ?kind ?attrs name f =
  if Atomic.get enabled then
    OTEL.Tracer.with_ ~tracer:(OTEL.Trace_provider.get ()) ?kind ?attrs name f
  else
    f OTEL.Span.dummy
