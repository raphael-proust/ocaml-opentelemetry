open Alcotest
module Config = Opentelemetry_client.Http_config

let test_config_printing () =
  let module Env = Config.Env () in
  let actual =
    Format.asprintf "%a" Config.pp @@ Env.make (fun common () -> common) ()
  in
  let expected =
    "{ debug=false;\n\
    \ self_trace=false; url_traces=\"http://localhost:4318/v1/traces\";\n\
    \ url_metrics=\"http://localhost:4318/v1/metrics\";\n\
    \ url_logs=\"http://localhost:4318/v1/logs\"; headers=[]; batch_traces=400;\n\
    \ batch_metrics=200; batch_logs=400; batch_timeout_ms=2000;\n\
    \ http_concurrency_level=None }"
  in
  check' string ~msg:"is rendered correctly" ~actual ~expected

let suite =
  [ test_case "default config pretty printing" `Quick test_config_printing ]

let () = Alcotest.run "Opentelemetry_client" [ "Config", suite ]
