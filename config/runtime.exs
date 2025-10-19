import Config

enable_otlp? =
  System.get_env("CODEX_OTLP_ENABLE", "false")
  |> String.downcase()
  |> Kernel.==("true")

config :codex_sdk, :enable_otlp?, enable_otlp?

if enable_otlp? do
  config :opentelemetry, :tracer, :otel_trace
  config :opentelemetry, :meter, :otel_meter
  config :opentelemetry, :traces_exporter, :otlp
  config :opentelemetry, :metrics_exporter, :otlp
else
  config :opentelemetry, :tracer, :none
  config :opentelemetry, :meter, :none
  config :opentelemetry, :traces_exporter, :none
  config :opentelemetry, :metrics_exporter, :none
  config :opentelemetry_exporter, :resource, []
end
