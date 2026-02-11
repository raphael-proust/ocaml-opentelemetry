open Opentelemetry_emitter

val add_sampler : Sampler.t -> 'a Emitter.t -> 'a Emitter.t
(** [add_sampler sampler e] is a new emitter that uses the [sampler] on each
    individual signal before passing them to [e]. This means only
    [Sampler.proba_accept sampler] of the signals will actually be emitted. *)

val sample : proba_accept:float -> 'a Emitter.t -> 'a Emitter.t
(** [sample ~proba_accept e] is
    [add_sampler (Sampler.create ~proba_accept ()) e] *)
