type level =
  | Debug
  | Info
  | Warning
  | Error

type logger = level -> (unit -> string) -> unit

let logger : logger ref = ref (fun _ _ -> ())

let[@inline] log level f = !logger level f

let string_of_level = function
  | Debug -> "debug"
  | Info -> "info"
  | Warning -> "warning"
  | Error -> "error"

let to_stderr ?(min_level = Warning) () : unit =
  let[@inline] int_of_level_ = function
    | Debug -> 0
    | Info -> 1
    | Warning -> 2
    | Error -> 3
  in
  let threshold = int_of_level_ min_level in
  logger :=
    fun level mk_msg ->
      if int_of_level_ level >= threshold then (
        let msg = mk_msg () in
        Printf.eprintf "[otel:%s] %s\n%!" (string_of_level level) msg
      )
