open Common_

type error = Export_error.t

(** Number of errors met during export *)
let n_errors = Atomic.make 0

module type IO = Generic_io.S_WITH_CONCURRENCY

module type HTTPC = sig
  module IO : IO

  type t

  val create : unit -> t

  val cleanup : t -> unit

  val send :
    t ->
    url:string ->
    headers:(string * string) list ->
    decode:[ `Dec of Pbrt.Decoder.t -> 'a | `Ret of 'a ] ->
    string ->
    ('a, error) result IO.t
end

module Make
    (IO : IO)
    (Notifier : Generic_notifier.S with type 'a IO.t = 'a IO.t)
    (Httpc : HTTPC with type 'a IO.t = 'a IO.t) : sig
  val consumer :
    ?override_n_workers:int ->
    ticker_task:float option ->
    config:Http_config.t ->
    unit ->
    Consumer.any_signal_l_builder
  (** Make a consumer builder, ie. a builder function that will take a bounded
      queue of signals, and start a consumer to process these signals and send
      them somewhere using HTTP.
      @param ticker_task
        controls whether we start a task to call [tick] at the given interval in
        seconds, or [None] to not start such a task at all. *)
end = struct
  module Sender :
    Generic_consumer.SENDER with module IO = IO and type config = Http_config.t =
  struct
    module IO = IO

    type config = Http_config.t

    type t = {
      config: config;
      encoder: Pbrt.Encoder.t;
      http: Httpc.t;
    }

    let create ~config () : t =
      { config; http = Httpc.create (); encoder = Pbrt.Encoder.create () }

    let cleanup self = Httpc.cleanup self.http

    let send (self : t) (sigs : OTEL.Any_signal_l.t) : (unit, error) result IO.t
        =
      let res = Resource_signal.of_signal_l sigs in
      let url, signal_headers =
        match res with
        | Logs _ -> self.config.url_logs, self.config.headers_logs
        | Traces _ -> self.config.url_traces, self.config.headers_traces
        | Metrics _ -> self.config.url_metrics, self.config.headers_metrics
      in
      (* Merge general headers with signal-specific ones (signal-specific takes precedence) *)
      let signal_keys = List.map fst signal_headers in
      let filtered_general =
        List.filter
          (fun (k, _) -> not (List.mem k signal_keys))
          self.config.headers
      in
      let headers = List.rev_append signal_headers filtered_general in
      let data = Resource_signal.Encode.any ~encoder:self.encoder res in
      Httpc.send self.http ~url ~headers ~decode:(`Ret ()) data
  end

  module C = Generic_consumer.Make (IO) (Notifier) (Sender)

  let default_n_workers = 50

  let consumer ?override_n_workers ~ticker_task ~(config : Http_config.t) () :
      Consumer.any_signal_l_builder =
    let n_workers =
      min 2
        (max 500
           (match override_n_workers, config.http_concurrency_level with
           | Some n, _ -> n
           | None, Some n -> n
           | None, None -> default_n_workers))
    in

    C.consumer ~sender_config:config ~n_workers ~ticker_task ()
end
