open Common_
module Trace_service = Opentelemetry.Proto.Trace_service
module Metrics_service = Opentelemetry.Proto.Metrics_service
module Logs_service = Opentelemetry.Proto.Logs_service
module Span = Opentelemetry.Span

open struct
  let of_x_or_empty ?service_name ?attrs ~f l =
    if l = [] then
      []
    else
      [ f ?service_name ?attrs l ]
end

type t =
  | Traces of Proto.Trace.resource_spans list
  | Metrics of Proto.Metrics.resource_metrics list
  | Logs of Proto.Logs.resource_logs list

let of_logs ?service_name ?attrs logs : t =
  Logs [ Util_resources.make_resource_logs ?service_name ?attrs logs ]

let of_logs_or_empty ?service_name ?attrs logs =
  of_x_or_empty ?service_name ?attrs ~f:of_logs logs

let of_spans ?service_name ?attrs spans : t =
  Traces [ Util_resources.make_resource_spans ?service_name ?attrs spans ]

let of_spans_or_empty ?service_name ?attrs spans =
  of_x_or_empty ?service_name ?attrs ~f:of_spans spans

let of_metrics ?service_name ?attrs m : t =
  Metrics [ Util_resources.make_resource_metrics ?service_name ?attrs m ]

let of_metrics_or_empty ?service_name ?attrs ms =
  of_x_or_empty ?service_name ?attrs ~f:of_metrics ms

let to_traces = function
  | Traces xs -> Some xs
  | _ -> None

let to_metrics = function
  | Metrics xs -> Some xs
  | _ -> None

let to_logs = function
  | Logs xs -> Some xs
  | _ -> None

let is_traces = function
  | Traces _ -> true
  | _ -> false

let is_metrics = function
  | Metrics _ -> true
  | _ -> false

let is_logs = function
  | Logs _ -> true
  | _ -> false

let of_signal_l ?service_name ?attrs (s : OTEL.Any_signal_l.t) : t =
  match s with
  | Logs logs -> of_logs ?service_name ?attrs logs
  | Spans sp -> of_spans ?service_name ?attrs sp
  | Metrics ms -> of_metrics ?service_name ?attrs ms

module Encode = struct
  let resource_to_string ~encoder ~ctor ~enc resource : string =
    let encoder =
      match encoder with
      | Some e ->
        Pbrt.Encoder.reset e;
        e
      | None -> Pbrt.Encoder.create ()
    in
    let x = ctor resource in
    let data =
      let@ _sc =
        Self_trace.with_ ~kind:Span.Span_kind_internal "encode-proto"
      in
      enc x encoder;
      let data = Pbrt.Encoder.to_string encoder in
      Span.add_attrs _sc [ "size", `Int (String.length data) ];
      Pbrt.Encoder.reset encoder;
      data
    in

    data

  let logs ?encoder resource_logs =
    resource_to_string ~encoder resource_logs
      ~ctor:(fun r ->
        Logs_service.make_export_logs_service_request ~resource_logs:r ())
      ~enc:Logs_service.encode_pb_export_logs_service_request

  let metrics ?encoder resource_metrics =
    resource_to_string ~encoder resource_metrics
      ~ctor:(fun r ->
        Metrics_service.make_export_metrics_service_request ~resource_metrics:r
          ())
      ~enc:Metrics_service.encode_pb_export_metrics_service_request

  let traces ?encoder resource_spans =
    resource_to_string ~encoder resource_spans
      ~ctor:(fun r ->
        Trace_service.make_export_trace_service_request ~resource_spans:r ())
      ~enc:Trace_service.encode_pb_export_trace_service_request

  let any ?encoder (r : t) : string =
    match r with
    | Logs l -> logs ?encoder l
    | Traces sp -> traces ?encoder sp
    | Metrics ms -> metrics ?encoder ms
end

module Decode = struct
  let resource_of_string ~dec s = Pbrt.Decoder.of_string s |> dec

  let logs data =
    (resource_of_string ~dec:Logs_service.decode_pb_export_logs_service_request
       data)
      .resource_logs

  let metrics data =
    (resource_of_string
       ~dec:Metrics_service.decode_pb_export_metrics_service_request data)
      .resource_metrics

  let traces data =
    (resource_of_string
       ~dec:Trace_service.decode_pb_export_trace_service_request data)
      .resource_spans
end

module Pp = struct
  let pp_sep fmt () = Format.fprintf fmt ",@."

  let pp_signal pp fmt t =
    Format.fprintf fmt "[@ @[";
    Format.pp_print_list ~pp_sep pp fmt t;
    Format.fprintf fmt "@ ]@]@."

  let logs = pp_signal Proto.Logs.pp_resource_logs

  let metrics = pp_signal Proto.Metrics.pp_resource_metrics

  let traces = pp_signal Proto.Trace.pp_resource_spans

  let pp fmt = function
    | Logs ls -> logs fmt ls
    | Metrics ms -> metrics fmt ms
    | Traces ts -> traces fmt ts
end

let pp = Pp.pp
