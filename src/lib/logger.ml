(** Logs.

    The logger is an object that can be used to emit logs.

    See
    {{:https://opentelemetry.io/docs/reference/specification/overview/#log-signal}
     the spec} *)

open Opentelemetry_emitter

(** {2 Logger object} *)

type t = {
  emit: Log_record.t Emitter.t;
  clock: Clock.t;
}

let dummy : t = { emit = Emitter.dummy; clock = Clock.ptime_clock }

let[@inline] enabled (self : t) : bool = Emitter.enabled self.emit

let of_exporter (exp : Exporter.t) : t =
  { emit = exp.emit_logs; clock = exp.clock }

let[@inline] emit1 (self : t) (l : Log_record.t) = Emitter.emit self.emit [ l ]

let (emit_main [@deprecated "use an explicit Logger.t"]) =
 fun (logs : Log_record.t list) : unit ->
  match Main_exporter.get () with
  | None -> ()
  | Some exp -> Exporter.send_logs exp logs

open struct
  (* internal default, keeps the default params below working without deprecation alerts *)
  let dynamic_main_ : t =
    of_exporter Main_exporter.dynamic_forward_to_main_exporter
end

(** A logger that uses the current {!Main_exporter}'s logger *)
let default = dynamic_main_

(** {2 Logging helpers} *)

open Log_record

(** Create log record and emit it on [logger] *)
let log ?(logger = dynamic_main_) ?attrs ?trace_id ?span_id
    ?(severity : severity option) (msg : string) : unit =
  if enabled logger then (
    let now = Clock.now logger.clock in
    let logrec =
      Log_record.make_str ?attrs ?trace_id ?span_id ?severity
        ~observed_time_unix_nano:now msg
    in
    emit1 logger logrec
  )

(** Helper to create a log record, with a suspension, like in [Logs].

    Example usage:
    [logf ~severity:Severity_number_warn (fun k->k"oh no!! %s it's bad: %b"
     "help" true)] *)
let logf ?(logger = dynamic_main_) ?attrs ?trace_id ?span_id ?severity msgf :
    unit =
  if enabled logger then
    msgf (fun fmt ->
        Format.kasprintf (log ~logger ?attrs ?trace_id ?span_id ?severity) fmt)
