(** Setup Lwt as the ambient context *)
let setup_ambient_context () =
  Opentelemetry_ambient_context.set_current_storage Ambient_context_lwt.storage
