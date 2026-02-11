module OTEL = Opentelemetry
module Otrace = Trace_core (* ocaml-trace *)
module Ambient_context = Opentelemetry_ambient_context

let ( let@ ) = ( @@ )

let spf = Printf.sprintf
