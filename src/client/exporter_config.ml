type protocol =
  | Http_protobuf
  | Http_json

type log_level =
  | Log_level_none
  | Log_level_error
  | Log_level_warn
  | Log_level_info
  | Log_level_debug

type rest = unit

type t = {
  debug: bool;
  log_level: log_level;
  sdk_disabled: bool;
  url_traces: string;
  url_metrics: string;
  url_logs: string;
  headers: (string * string) list;
  headers_traces: (string * string) list;
  headers_metrics: (string * string) list;
  headers_logs: (string * string) list;
  protocol: protocol;
  timeout_ms: int;
  timeout_traces_ms: int;
  timeout_metrics_ms: int;
  timeout_logs_ms: int;
  batch_traces: int option;
  batch_metrics: int option;
  batch_logs: int option;
  batch_timeout_ms: int;
  self_trace: bool;
  http_concurrency_level: int option;
  _rest: rest;
}

open struct
  let ppiopt out i =
    match i with
    | None -> Format.fprintf out "None"
    | Some i -> Format.fprintf out "%d" i

  let pp_header ppf (a, b) = Format.fprintf ppf "@[%s: @,%s@]@." a b

  let ppheaders out l =
    Format.fprintf out "[@[%a@]]" (Format.pp_print_list pp_header) l

  let pp_protocol out = function
    | Http_protobuf -> Format.fprintf out "http/protobuf"
    | Http_json -> Format.fprintf out "http/json"

  let pp_log_level out = function
    | Log_level_none -> Format.fprintf out "none"
    | Log_level_error -> Format.fprintf out "error"
    | Log_level_warn -> Format.fprintf out "warn"
    | Log_level_info -> Format.fprintf out "info"
    | Log_level_debug -> Format.fprintf out "debug"
end

let pp out (self : t) : unit =
  let {
    debug;
    log_level;
    sdk_disabled;
    self_trace;
    url_traces;
    url_metrics;
    url_logs;
    headers;
    headers_traces;
    headers_metrics;
    headers_logs;
    protocol;
    timeout_ms;
    timeout_traces_ms;
    timeout_metrics_ms;
    timeout_logs_ms;
    batch_traces;
    batch_metrics;
    batch_logs;
    batch_timeout_ms;
    http_concurrency_level;
    _rest = _;
  } =
    self
  in
  Format.fprintf out
    "{@[ debug=%B;@ log_level=%a;@ sdk_disabled=%B;@ self_trace=%B;@ \
     url_traces=%S;@ url_metrics=%S;@ url_logs=%S;@ @[<2>headers=@,\
     %a@];@ @[<2>headers_traces=@,\
     %a@];@ @[<2>headers_metrics=@,\
     %a@];@ @[<2>headers_logs=@,\
     %a@];@ protocol=%a;@ timeout_ms=%d;@ timeout_traces_ms=%d;@ \
     timeout_metrics_ms=%d;@ timeout_logs_ms=%d;@ batch_traces=%a;@ \
     batch_metrics=%a;@ batch_logs=%a;@ batch_timeout_ms=%d;@ \
     http_concurrency_level=%a @]}"
    debug pp_log_level log_level sdk_disabled self_trace url_traces url_metrics
    url_logs ppheaders headers ppheaders headers_traces ppheaders
    headers_metrics ppheaders headers_logs pp_protocol protocol timeout_ms
    timeout_traces_ms timeout_metrics_ms timeout_logs_ms ppiopt batch_traces
    ppiopt batch_metrics ppiopt batch_logs batch_timeout_ms ppiopt
    http_concurrency_level

let default_url = "http://localhost:4318"

type 'k make =
  ?debug:bool ->
  ?log_level:log_level ->
  ?sdk_disabled:bool ->
  ?url:string ->
  ?url_traces:string ->
  ?url_metrics:string ->
  ?url_logs:string ->
  ?batch_traces:int option ->
  ?batch_metrics:int option ->
  ?batch_logs:int option ->
  ?headers:(string * string) list ->
  ?headers_traces:(string * string) list ->
  ?headers_metrics:(string * string) list ->
  ?headers_logs:(string * string) list ->
  ?protocol:protocol ->
  ?timeout_ms:int ->
  ?timeout_traces_ms:int ->
  ?timeout_metrics_ms:int ->
  ?timeout_logs_ms:int ->
  ?batch_timeout_ms:int ->
  ?self_trace:bool ->
  ?http_concurrency_level:int ->
  'k

module type ENV = sig
  val make : (t -> 'a) -> 'a make
end

open struct
  let get_debug_from_env () =
    match Sys.getenv_opt "OTEL_OCAML_DEBUG" with
    | Some ("1" | "true") -> true
    | _ -> false

  let get_log_level_from_env () =
    match Sys.getenv_opt "OTEL_LOG_LEVEL" with
    | Some "none" -> Log_level_none
    | Some "error" -> Log_level_error
    | Some "warn" -> Log_level_warn
    | Some "info" -> Log_level_info
    | Some "debug" -> Log_level_debug
    | Some s ->
      Printf.eprintf "warning: unknown log level %S, defaulting to info\n%!" s;
      (* log in info level, so we at least don't miss warnings and errors  *)
      Log_level_info
    | None ->
      if get_debug_from_env () then
        Log_level_debug
      else
        Log_level_none

  let get_sdk_disabled_from_env () =
    match Sys.getenv_opt "OTEL_SDK_DISABLED" with
    | Some ("true" | "1") -> true
    | _ -> false

  let get_protocol_from_env env_name =
    match Sys.getenv_opt env_name with
    | Some "http/protobuf" -> Http_protobuf
    | Some "http/json" -> Http_json
    | _ -> Http_protobuf

  let get_timeout_from_env env_name default =
    match Sys.getenv_opt env_name with
    | Some s -> (try int_of_string s with _ -> default)
    | None -> default

  let make_get_from_env env_name =
    let value = ref None in
    fun () ->
      match !value with
      | None ->
        value := Sys.getenv_opt env_name;
        !value
      | Some value -> Some value

  let get_url_from_env = make_get_from_env "OTEL_EXPORTER_OTLP_ENDPOINT"

  let get_url_traces_from_env =
    make_get_from_env "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"

  let get_url_metrics_from_env =
    make_get_from_env "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT"

  let get_url_logs_from_env =
    make_get_from_env "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT"

  let remove_trailing_slash url =
    if url <> "" && String.get url (String.length url - 1) = '/' then
      String.sub url 0 (String.length url - 1)
    else
      url

  let parse_headers s =
    let parse_header s =
      match String.split_on_char '=' s with
      | [ key; value ] -> key, value
      | _ -> failwith "Unexpected format for header"
    in
    String.split_on_char ',' s |> List.map parse_header

  let get_headers_from_env env_name =
    try parse_headers (Sys.getenv env_name) with _ -> []

  let get_general_headers_from_env () =
    try parse_headers (Sys.getenv "OTEL_EXPORTER_OTLP_HEADERS") with _ -> []
end

module Env () : ENV = struct
  let merge_headers base specific =
    (* Signal-specific headers override generic ones *)
    let specific_keys = List.map fst specific in
    let filtered_base =
      List.filter (fun (k, _) -> not (List.mem k specific_keys)) base
    in
    List.rev_append specific filtered_base

  let make k ?(debug = get_debug_from_env ())
      ?(log_level = get_log_level_from_env ())
      ?(sdk_disabled = get_sdk_disabled_from_env ()) ?url ?url_traces
      ?url_metrics ?url_logs ?(batch_traces = Some 400)
      ?(batch_metrics = Some 200) ?(batch_logs = Some 400)
      ?(headers = get_general_headers_from_env ()) ?headers_traces
      ?headers_metrics ?headers_logs
      ?(protocol = get_protocol_from_env "OTEL_EXPORTER_OTLP_PROTOCOL")
      ?(timeout_ms = get_timeout_from_env "OTEL_EXPORTER_OTLP_TIMEOUT" 10_000)
      ?timeout_traces_ms ?timeout_metrics_ms ?timeout_logs_ms
      ?(batch_timeout_ms = 2_000) ?(self_trace = false) ?http_concurrency_level
      =
    let url_traces, url_metrics, url_logs =
      let base_url =
        let base_url =
          match get_url_from_env () with
          | None -> Option.value url ~default:default_url
          | Some url -> remove_trailing_slash url
        in
        remove_trailing_slash base_url
      in
      let url_traces =
        match get_url_traces_from_env () with
        | None -> Option.value url_traces ~default:(base_url ^ "/v1/traces")
        | Some url -> url
      in
      let url_metrics =
        match get_url_metrics_from_env () with
        | None -> Option.value url_metrics ~default:(base_url ^ "/v1/metrics")
        | Some url -> url
      in
      let url_logs =
        match get_url_logs_from_env () with
        | None -> Option.value url_logs ~default:(base_url ^ "/v1/logs")
        | Some url -> url
      in
      url_traces, url_metrics, url_logs
    in

    (* Get per-signal headers from env vars *)
    let env_headers_traces =
      get_headers_from_env "OTEL_EXPORTER_OTLP_TRACES_HEADERS"
    in
    let env_headers_metrics =
      get_headers_from_env "OTEL_EXPORTER_OTLP_METRICS_HEADERS"
    in
    let env_headers_logs =
      get_headers_from_env "OTEL_EXPORTER_OTLP_LOGS_HEADERS"
    in

    (* Merge with provided headers, env-specific takes precedence *)
    let headers_traces =
      match headers_traces with
      | Some h -> h
      | None -> merge_headers headers env_headers_traces
    in
    let headers_metrics =
      match headers_metrics with
      | Some h -> h
      | None -> merge_headers headers env_headers_metrics
    in
    let headers_logs =
      match headers_logs with
      | Some h -> h
      | None -> merge_headers headers env_headers_logs
    in

    (* Get per-signal timeouts from env vars with fallback to general timeout *)
    let timeout_traces_ms =
      match timeout_traces_ms with
      | Some t -> t
      | None ->
        get_timeout_from_env "OTEL_EXPORTER_OTLP_TRACES_TIMEOUT" timeout_ms
    in
    let timeout_metrics_ms =
      match timeout_metrics_ms with
      | Some t -> t
      | None ->
        get_timeout_from_env "OTEL_EXPORTER_OTLP_METRICS_TIMEOUT" timeout_ms
    in
    let timeout_logs_ms =
      match timeout_logs_ms with
      | Some t -> t
      | None ->
        get_timeout_from_env "OTEL_EXPORTER_OTLP_LOGS_TIMEOUT" timeout_ms
    in

    k
      {
        debug;
        log_level;
        sdk_disabled;
        url_traces;
        url_metrics;
        url_logs;
        headers;
        headers_traces;
        headers_metrics;
        headers_logs;
        protocol;
        timeout_ms;
        timeout_traces_ms;
        timeout_metrics_ms;
        timeout_logs_ms;
        batch_traces;
        batch_metrics;
        batch_logs;
        batch_timeout_ms;
        self_trace;
        http_concurrency_level;
        _rest = ();
      }
end
