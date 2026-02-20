(** Global registry of metric instruments.

    Instruments are stateful accumulators (counters, gauges, histograms, …).
    [update] is called at any time to record a value; [emit] is called at
    collection time by a {!Meter.t}, which supplies the clock.

    All instruments register themselves into a global list on creation via
    {!register}, so any meter can collect the full set in one pass. Make sure to
    only create instruments at the toplevel so that the list doesn't grow
    forever. *)

type 'a t = {
  kind: string;  (** "counter", "gauge", "histogram", … *)
  name: string;
  emit: clock:Clock.t -> unit -> Metrics.t list;
      (** Snapshot current accumulated state into metrics. *)
  update: 'a -> unit;  (** Record a new value. *)
}

val register : 'a t -> unit
(** Add an instrument's [emit] to {!all}. Called automatically by the standard
    instrument-creation functions. *)

(** Implementation details for a custom stateful instrument. Pass to {!Make} to
    obtain a [create] function. *)
module type CUSTOM_IMPL = sig
  type data

  type state

  val kind : string

  val init : unit -> state

  val update : state -> data -> unit

  val to_metrics :
    state ->
    name:string ->
    ?description:string ->
    ?unit_:string ->
    clock:Clock.t ->
    unit ->
    Metrics.t list
end

(** Build a custom instrument type from a {!CUSTOM_IMPL}. The returned [create]
    registers the instrument into {!all} automatically. *)
module Make (I : CUSTOM_IMPL) : sig
  val create :
    name:string -> ?description:string -> ?unit_:string -> unit -> I.data t
end

module Int_counter : sig
  val create :
    name:string -> ?description:string -> ?unit_:string -> unit -> int t

  val add : int t -> int -> unit
end

module Float_counter : sig
  val create :
    name:string -> ?description:string -> ?unit_:string -> unit -> float t

  val add : float t -> float -> unit
end

module Int_gauge : sig
  val create :
    name:string -> ?description:string -> ?unit_:string -> unit -> int t

  val record : int t -> int -> unit
end

module Float_gauge : sig
  val create :
    name:string -> ?description:string -> ?unit_:string -> unit -> float t

  val record : float t -> float -> unit
end

module Histogram : sig
  val default_bounds : float list

  val create :
    name:string ->
    ?description:string ->
    ?unit_:string ->
    ?bounds:float list ->
    unit ->
    float t

  val record : float t -> float -> unit
end

module Internal : sig
  val iter_all : ((clock:Clock.t -> unit -> Metrics.t list) -> unit) -> unit
  (** Access all the instruments *)
end
