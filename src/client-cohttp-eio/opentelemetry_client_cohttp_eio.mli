(*
   TODO: more options from
   https://opentelemetry.io/docs/reference/specification/protocol/exporter/
   *)

module Config = Config

val create_consumer :
  ?config:Config.t ->
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  unit ->
  Opentelemetry_client.Consumer.any_signal_l_builder
(** Consumer that pulls from a queue *)

val create_exporter :
  ?config:Config.t ->
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  unit ->
  Opentelemetry.Exporter.t
(** NOTE [after_cleanup] optional parameter removed @since 0.12 *)

val create_backend :
  ?config:Config.t ->
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  unit ->
  Opentelemetry.Exporter.t
[@@deprecated "use create_exporter"]

val setup :
  ?config:Config.t ->
  ?enable:bool ->
  sw:Eio.Switch.t ->
  Eio_unix.Stdenv.base ->
  unit
(** Setup endpoint. This modifies {!Opentelemetry.Collector.backend}.
    @param enable
      actually setup the backend (default true). This can be used to
      enable/disable the setup depending on CLI arguments or environment.
    @param config configuration to use
    @param stop
      an atomic boolean. When it becomes true, background threads will all stop
      after a little while. *)

val remove_exporter : unit -> unit
(** Shutdown current exporter
    @since 0.12 *)

val remove_backend : unit -> unit
[@@deprecated "use remove_exporter"]
(** @since 0.12 *)

val with_setup :
  ?config:Config.t -> ?enable:bool -> Eio_unix.Stdenv.base -> (unit -> 'a) -> 'a
(** [with_setup () f] is like [setup(); f()] but takes care of cleaning up after
    [f()] returns See {!setup} for more details. *)
