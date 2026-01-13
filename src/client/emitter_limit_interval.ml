open Common_.OTEL

let add_interval_limiter il (e : _ Emitter.t) : _ Emitter.t =
  let emit xs = if Interval_limiter.make_attempt il then Emitter.emit e xs in
  { e with emit }

let limit_interval ~min_interval (e : _ Emitter.t) : _ Emitter.t =
  add_interval_limiter (Interval_limiter.create ~min_interval ()) e
