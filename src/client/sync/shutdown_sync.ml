open Common_

(** Shutdown this exporter and block the thread until it's done.

    {b NOTE}: this might deadlock if the exporter runs entirely in the current
    thread! *)
let shutdown (exp : OTEL.Exporter.t) : unit =
  let q = Sync_queue.create () in
  OTEL.Exporter.on_stop exp (Sync_queue.push q);
  OTEL.Exporter.shutdown exp;
  Sync_queue.pop q

(** Shutdown main exporter and wait *)
let shutdown_main () : unit = Option.iter shutdown (OTEL.Main_exporter.get ())
