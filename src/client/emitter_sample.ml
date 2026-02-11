open Opentelemetry_emitter

let add_sampler (self : Sampler.t) (e : _ Emitter.t) : _ Emitter.t =
  let enabled () = e.enabled () in
  let closed () = Emitter.closed e in
  let flush_and_close () = Emitter.flush_and_close e in
  let tick ~mtime = Emitter.tick e ~mtime in

  let emit l =
    if l <> [] && e.enabled () then (
      let accepted = List.filter (fun _x -> Sampler.accept self) l in
      if accepted <> [] then Emitter.emit e accepted
    )
  in

  { Emitter.closed; enabled; flush_and_close; tick; emit }

let sample ~proba_accept e = add_sampler (Sampler.create ~proba_accept ()) e
