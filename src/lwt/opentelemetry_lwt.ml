open Lwt.Syntax
include Opentelemetry

module Main_exporter = struct
  include Main_exporter

  let remove () : unit Lwt.t =
    let p, resolve = Lwt.wait () in
    remove () ~on_done:(fun () -> Lwt.wakeup_later resolve ());
    p
end

external reraise : exn -> 'a = "%reraise"
(** This is equivalent to [Lwt.reraise]. We inline it here so we don't force to
    use Lwt's latest version *)

module Tracer = struct
  include Tracer

  (** Sync span guard *)
  let with_ (type a) ?(tracer = dynamic_main) ?force_new_trace_id ?trace_state
      ?attrs ?kind ?trace_id ?parent ?links name (cb : Span.t -> a Lwt.t) :
      a Lwt.t =
    let thunk, finally =
      with_thunk_and_finally tracer ?force_new_trace_id ?trace_state ?attrs
        ?kind ?trace_id ?parent ?links name cb
    in

    match thunk () with
    | exception exn ->
      let bt = Printexc.get_raw_backtrace () in
      finally (Error (exn, bt));
      Printexc.raise_with_backtrace exn bt
    | promise ->
      Lwt.on_any promise
        (fun _ -> finally (Ok ()))
        (fun exn ->
          let bt = Printexc.get_raw_backtrace () in
          finally (Error (exn, bt)));
      promise
end

module Trace = Tracer [@@deprecated "use Tracer"]

module Metrics = struct
  include Metrics
end

module Logs = struct
  include Proto.Logs
  include Log_record
  include Logger
end
