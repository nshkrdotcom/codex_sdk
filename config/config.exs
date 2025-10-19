import Config

config :codex_sdk, :enable_otlp?, false

# Disable OTLP exporters by default; callers can opt in via runtime configuration.
config :opentelemetry, :tracer, :none
config :opentelemetry, :meter, :none
config :opentelemetry, :traces_exporter, :none
config :opentelemetry, :metrics_exporter, :none
config :opentelemetry_exporter, :resource, []
