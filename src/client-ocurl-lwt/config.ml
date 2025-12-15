type t = Opentelemetry_client.Http_config.t

module Env = Opentelemetry_client.Http_config.Env ()

let pp = Opentelemetry_client.Http_config.pp

let make = Env.make (fun common () -> common)
