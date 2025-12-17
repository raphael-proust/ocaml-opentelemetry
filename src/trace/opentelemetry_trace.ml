open Opentelemetry_atomic
open Common_

let on_internal_error =
  ref (fun msg -> Printf.eprintf "error in Opentelemetry_trace: %s\n%!" msg)

open struct
  module Opt_syntax = struct
    let[@inline] ( let+ ) o f =
      match o with
      | None -> None
      | Some x -> Some (f x)

    let ( >|= ) = ( let+ )

    let[@inline] ( <?> ) a b =
      match a, b with
      | Some _, _ -> a
      | None, _ -> b
  end
end

module Extensions = struct
  type Otrace.extension_event +=
    | Ev_link_span of Otrace.span * OTEL.Span_ctx.t
    | Ev_record_exn of {
        sp: Otrace.span;
        exn: exn;
        bt: Printexc.raw_backtrace;
      }
    | Ev_set_span_kind of Otrace.span * OTEL.Span_kind.t
    | Ev_set_span_status of Otrace.span * OTEL.Span_status.t
end

open Extensions

module Internal = struct
  type span_begin = { span: OTEL.Span.t } [@@unboxed]

  (* use the fast, thread safe span table that relies on picos. *)
  module Active_span_tbl = Trace_subscriber.Span_tbl

  type state = {
    tbl: span_begin Active_span_tbl.t;
    span_gen: int Atomic.t;
    clock: Opentelemetry_core.Clock.t;
  }

  let create_state ~clock () : state =
    { tbl = Active_span_tbl.create (); span_gen = Atomic.make 0; clock }

  (* sanity check: otrace meta-map must be the same as hmap *)
  let () = ignore (fun (k : _ Hmap.key) : _ Otrace.Meta_map.key -> k)

  let[@inline] get_span_ (self : state) (span : Otrace.span) :
      OTEL.Span.t option =
    match Active_span_tbl.find_exn self.tbl span with
    | exception Not_found -> None
    | { span } -> Some span

  (** key to access a OTEL span (the current span) from an
      [Otrace.explicit_span]. We can reuse the context key because we know that
      [Otrace.Meta_map == Hmap]. *)
  let k_span_otrace : OTEL.Span.t Otrace.Meta_map.key = OTEL.Span.k_context

  let[@inline] get_span_explicit_ (span : Otrace.explicit_span) :
      OTEL.Span.t option =
    Otrace.Meta_map.find k_span_otrace span.meta

  let enter_span_ (self : state)
      ?(explicit_parent : Otrace.explicit_span_ctx option) ~__FUNCTION__
      ~__FILE__ ~__LINE__ ~data ~(otrace_span : Otrace.span) name : span_begin =
    let open OTEL in
    (* we create a random span ID here, it's not related in any way to
       the [Otrace.span] which is sequential. The [Otrace.span] has strong
       guarantees of uniqueness and thus we {i can} use it as an index
       in [Span_tbl], whereas an 8 bytes OTEL span ID might be prone to
       collisions over time. *)
    let otel_id = Span_id.create () in

    (* get data from parent *)
    let trace_id_from_parent, parent_id_from_parent =
      let open Opt_syntax in
      match explicit_parent with
      | Some p ->
        let trace_id = Otrace.Meta_map.find OTEL.Trace_id.k_trace_id p.meta in
        let span_id =
          Otrace.Meta_map.find k_span_otrace p.meta >|= OTEL.Span.id
        in
        let span_ctx = Otrace.Meta_map.find OTEL.Span_ctx.k_span_ctx p.meta in
        ( trace_id <?> (span_ctx >|= OTEL.Span_ctx.trace_id),
          span_id <?> (span_ctx >|= OTEL.Span_ctx.parent_id) )
      | None -> None, None
    in

    (* get data from implicit context *)
    let trace_id_from_ambient, parent_id_from_ambient =
      if Option.is_none trace_id_from_parent then
        let open Opt_syntax in
        let implicit_parent = OTEL.Ambient_span.get () in
        implicit_parent >|= OTEL.Span.trace_id, implicit_parent >|= OTEL.Span.id
      else
        None, None
    in

    let trace_id =
      match trace_id_from_parent, trace_id_from_ambient with
      | Some t, _ | None, Some t -> t
      | None, None -> Trace_id.create ()
    in

    let parent_id =
      Opt_syntax.(parent_id_from_parent <?> parent_id_from_ambient)
    in

    let attrs =
      ("code.filepath", `String __FILE__)
      :: ("code.lineno", `Int __LINE__)
      :: data
    in

    let start_time = Clock.now self.clock in
    let span : OTEL.Span.t =
      OTEL.Span.make ?parent:parent_id ~trace_id ~id:otel_id ~attrs name
        ~start_time ~end_time:start_time
    in

    let sb = { span } in

    (match __FUNCTION__ with
    | Some __FUNCTION__ when OTEL.Span.is_not_dummy span ->
      let last_dot = String.rindex __FUNCTION__ '.' in
      let module_path = String.sub __FUNCTION__ 0 last_dot in
      let function_name =
        String.sub __FUNCTION__ (last_dot + 1)
          (String.length __FUNCTION__ - last_dot - 1)
      in
      Span.add_attrs span
        [
          "code.function", `String function_name;
          "code.namespace", `String module_path;
        ]
    | _ -> ());

    Active_span_tbl.add self.tbl otrace_span sb;
    sb

  let exit_span_ self { span } : OTEL.Span.t =
    let open OTEL in
    if Span.is_not_dummy span then (
      let end_time = Clock.now self.clock in
      Proto.Trace.span_set_end_time_unix_nano span end_time
    );
    span

  let exit_span' (self : state) otrace_id otel_span_begin =
    Active_span_tbl.remove self.tbl otrace_id;
    exit_span_ self otel_span_begin

  (** Find the OTEL span corresponding to this Trace span *)
  let exit_span_from_id (self : state) otrace_id =
    match Active_span_tbl.find_exn self.tbl otrace_id with
    | exception Not_found -> None
    | otel_span_begin ->
      Active_span_tbl.remove self.tbl otrace_id;
      Some (exit_span_ self otel_span_begin)
end

module type COLLECTOR_ARG = sig
  val exporter : OTEL.Exporter.t
end

module Make_collector (A : COLLECTOR_ARG) = struct
  open Internal

  let exporter = A.exporter

  let state = create_state ~clock:exporter.clock ()

  (* NOTE: perf: it would be interesting to keep the "current (OTEL) span" in
    local storage/ambient-context, to accelerate most span-modifying
    operations. They'd first look in local storage, and if the span isn't the
    expected one, then look in the main span tbl. *)

  let with_span ~__FUNCTION__ ~__FILE__ ~__LINE__ ~data name cb =
    let otrace_span : Otrace.span =
      Int64.of_int (Atomic.fetch_and_add state.span_gen 1)
    in

    let sb : span_begin =
      enter_span_ state ~__FUNCTION__ ~__FILE__ ~__LINE__ ~data name
        ~otrace_span
    in

    match
      let@ () = OTEL.Ambient_span.with_ambient sb.span in
      cb otrace_span
    with
    | res ->
      let otel_span = exit_span' state otrace_span sb in
      OTEL.Exporter.send_trace exporter [ otel_span ];
      res
    | exception e ->
      let bt = Printexc.get_raw_backtrace () in

      let otrace_span : Otrace.span =
        Int64.of_int (Atomic.fetch_and_add state.span_gen 1)
      in
      OTEL.Span.record_exception sb.span e bt;
      let otel_span = exit_span' state otrace_span sb in
      OTEL.Exporter.send_trace exporter [ otel_span ];

      Printexc.raise_with_backtrace e bt

  let enter_span ~__FUNCTION__ ~__FILE__ ~__LINE__ ~data name : Trace_core.span
      =
    let otrace_span : Otrace.span =
      Int64.of_int (Atomic.fetch_and_add state.span_gen 1)
    in
    let _sb =
      enter_span_ state ~__FUNCTION__ ~__FILE__ ~__LINE__ ~data ~otrace_span
        name
    in

    (* NOTE: we cannot enter ambient scope in a disjoint way
         with the exit, because we only have [Ambient_context.with_binding],
         no [set_binding]. This is what {!with_parent_span} is for! *)
    otrace_span

  let exit_span otrace_id =
    match exit_span_from_id state otrace_id with
    | None -> ()
    | Some otel_span -> OTEL.Exporter.send_trace exporter [ otel_span ]

  let enter_manual_span ~(parent : Otrace.explicit_span_ctx option) ~flavor:_
      ~__FUNCTION__ ~__FILE__ ~__LINE__ ~data name : Otrace.explicit_span =
    let otrace_span : Otrace.span =
      Int64.of_int (Atomic.fetch_and_add state.span_gen 1)
    in
    let sb =
      match parent with
      | None ->
        enter_span_ state ~__FUNCTION__ ~__FILE__ ~__LINE__ ~data ~otrace_span
          name
      | Some parent ->
        enter_span_ state ~explicit_parent:parent ~__FUNCTION__ ~__FILE__
          ~__LINE__ ~data ~otrace_span name
    in

    Active_span_tbl.add state.tbl otrace_span sb;

    {
      Otrace.span = otrace_span;
      meta = Otrace.Meta_map.(empty |> add k_span_otrace sb.span);
    }

  let exit_manual_span { Otrace.span = otrace_id; _ } =
    match Active_span_tbl.find_exn state.tbl otrace_id with
    | exception Not_found ->
      !on_internal_error (spf "no active span with ID %Ld" otrace_id)
    | sb ->
      let otel_span = exit_span' state otrace_id sb in
      OTEL.Exporter.send_trace exporter [ otel_span ]

  let add_data_to_span otrace_id data =
    match Active_span_tbl.find_exn state.tbl otrace_id with
    | exception Not_found ->
      !on_internal_error (spf "no active span with ID %Ld" otrace_id)
    | sb -> OTEL.Span.add_attrs sb.span data

  let add_data_to_manual_span (span : Otrace.explicit_span) data : unit =
    match get_span_explicit_ span with
    | None ->
      !on_internal_error (spf "manual span does not a contain an OTEL scope")
    | Some span -> OTEL.Span.add_attrs span data

  let message ?(span : Otrace.span option) ~data:_ msg : unit =
    let trace_id_from_parent, span_id_from_parent =
      let open Opt_syntax in
      match span with
      | Some p ->
        let sp = get_span_ state p in
        ( (let+ sp = sp in
           OTEL.Span.trace_id sp),
          let+ sp = sp in
          OTEL.Span.id sp )
      | None -> None, None
    in

    (* get data from implicit context *)
    let trace_id_from_ambient, span_id_from_ambient =
      if Option.is_none trace_id_from_parent then
        let open Opt_syntax in
        let implicit_parent = OTEL.Ambient_span.get () in
        implicit_parent >|= OTEL.Span.trace_id, implicit_parent >|= OTEL.Span.id
      else
        None, None
    in

    let trace_id =
      Opt_syntax.(trace_id_from_parent <?> trace_id_from_ambient)
    in
    let span_id = Opt_syntax.(span_id_from_parent <?> span_id_from_ambient) in

    let log =
      let observed_time_unix_nano = OTEL.Clock.now exporter.clock in
      OTEL.Log_record.make_str ~observed_time_unix_nano ?trace_id ?span_id msg
    in
    OTEL.Exporter.send_logs exporter [ log ]

  let shutdown () = ()

  let name_process _name = ()

  let name_thread _name = ()

  let counter_int ~data:attrs name cur_val : unit =
    let now = OTEL.Clock.now exporter.clock in
    let m = OTEL.Metrics.(gauge ~name [ int ~attrs ~now cur_val ]) in
    OTEL.Exporter.send_metrics exporter [ m ]

  let counter_float ~data:attrs name cur_val : unit =
    let now = OTEL.Clock.now exporter.clock in
    let m = OTEL.Metrics.(gauge ~name [ float ~attrs ~now cur_val ]) in
    OTEL.Exporter.send_metrics exporter [ m ]

  let extension_event = function
    | Ev_link_span (sp1, sc2) ->
      (match get_span_ state sp1 with
      | Some sc1 -> OTEL.Span.add_links sc1 [ OTEL.Span_link.of_span_ctx sc2 ]
      | _ -> !on_internal_error "could not find scope for OTEL span")
    | Ev_set_span_kind (sp, k) ->
      (match get_span_ state sp with
      | None -> !on_internal_error "could not find scope for OTEL span"
      | Some sc -> OTEL.Span.set_kind sc k)
    | Ev_set_span_status (sp, st) ->
      (match get_span_ state sp with
      | None -> !on_internal_error "could not find scope for OTEL span"
      | Some sc -> OTEL.Span.set_status sc st)
    | Ev_record_exn { sp; exn; bt } ->
      (match get_span_ state sp with
      | None -> !on_internal_error "could not find scope for OTEL span"
      | Some sc -> OTEL.Span.record_exception sc exn bt)
    | _ -> ()
end

let collector_of_exporter (exp : OTEL.Exporter.t) : Trace_core.collector =
  let module M = Make_collector (struct
    let exporter = exp
  end) in
  (module M : Trace_core.Collector.S)

let with_ambient_span (sp : Otrace.explicit_span) f =
  let open Internal in
  match get_span_explicit_ sp with
  | None -> f ()
  | Some otel_sp -> Opentelemetry.Ambient_span.with_ambient otel_sp f

let link_span_to_otel_ctx (sp1 : Otrace.span) (sp2 : OTEL.Span_ctx.t) : unit =
  if Otrace.enabled () then Otrace.extension_event @@ Ev_link_span (sp1, sp2)

(*
let link_spans (sp1 : Otrace.explicit_span) (sp2 : Otrace.explicit_span) : unit
    =
  if Otrace.enabled () then Otrace.extension_event @@ Ev_link_span (sp1, sp2)
  *)

let[@inline] set_span_kind sp k : unit =
  if Otrace.enabled () then Otrace.extension_event @@ Ev_set_span_kind (sp, k)

let[@inline] set_span_status sp status : unit =
  if Otrace.enabled () then
    Otrace.extension_event @@ Ev_set_span_status (sp, status)

let record_exception sp exn bt : unit =
  if Otrace.enabled () then
    Otrace.extension_event @@ Ev_record_exn { sp; exn; bt }

(** Collector that forwards to the {b currently installed} OTEL exporter. *)
let collector_main_otel_exporter () : Otrace.collector =
  collector_of_exporter OTEL.Main_exporter.dynamic_forward_to_main_exporter

let (collector
     [@deprecated "use collector_of_exporter or collector_main_otel_exporter"])
    =
  collector_main_otel_exporter

let setup () = Otrace.setup_collector @@ collector_main_otel_exporter ()

let setup_with_otel_exporter exp : unit =
  let coll = collector_of_exporter exp in
  OTEL.Main_exporter.set exp;
  Otrace.setup_collector coll

let setup_with_otel_backend = setup_with_otel_exporter

module Well_known = struct end
