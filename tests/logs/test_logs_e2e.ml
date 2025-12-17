module Client = Opentelemetry_client
module L = Opentelemetry_proto.Logs

(* NOTE: This port must be different from that used by other integration tests,
   to prevent socket binding clashes. *)
let port = 4359

let url = Printf.sprintf "http://localhost:%d" port

let cmd = [ "emit_logs_cohttp"; "--url"; url ]

let tests (signal_batches : Client.Signal.t list) =
  ignore signal_batches;
  let cur_time = ref 0 in
  List.iter
    (fun (signal_batch : Client.Signal.t) ->
      match signal_batch with
      | Logs ls ->
        ls (* Mask out the times so tests don't change in between runs *)
        |> List.map (fun (l : L.resource_logs) ->
               let masked_scope_logs =
                 List.map
                   (fun (sl : L.scope_logs) ->
                     let masked_log_records =
                       List.map
                         (fun (lr : L.log_record) ->
                           let lr = L.copy_log_record lr in
                           let pseudo_time = Int64.of_int !cur_time in
                           incr cur_time;
                           L.log_record_set_time_unix_nano lr pseudo_time;
                           L.log_record_set_observed_time_unix_nano lr
                             pseudo_time;
                           lr)
                         sl.log_records
                     in
                     let sl = L.copy_scope_logs sl in
                     L.scope_logs_set_log_records sl masked_log_records;
                     sl)
                   l.scope_logs
               in
               let l = L.copy_resource_logs l in
               L.resource_logs_set_scope_logs l masked_scope_logs;
               l)
        |> List.iter (Format.printf "%a\n" L.pp_resource_logs)
      | _ -> ())
    signal_batches

let () =
  let signal_batches =
    Lwt_main.run (Signal_gatherer.gather_signals ~port cmd)
  in
  tests signal_batches
