import Config

if config_env() == :test do
  # Finch reads SSLKEYLOGFILE on startup; clear ambient shell state so tests
  # do not depend on a writable home directory outside the repo.
  System.delete_env("SSLKEYLOGFILE")
end

parse_enabled = fn
  value when is_binary(value) ->
    normalized =
      value
      |> String.trim()
      |> String.downcase()

    normalized in ["1", "true", "yes", "on"]

  _ ->
    false
end

enable_otlp? =
  System.get_env("CODEX_OTLP_ENABLE")
  |> parse_enabled.()

config :codex_sdk, :enable_otlp?, enable_otlp?

env_allowlist = ~w|
  APPDATA
  BUILDKITE
  CI
  CODEX_API_KEY
  CODEX_CA_CERTIFICATE
  CODEX_HOME
  CODEX_INTERNAL_ORIGINATOR_OVERRIDE
  CODEX_MODEL
  CODEX_MODEL_DEFAULT
  CODEX_OLLAMA_BASE_URL
  CODEX_OSS_PROVIDER
  CODEX_OTLP_CACERTFILE
  CODEX_OTLP_CA_CERTFILE
  CODEX_OTLP_CERTFILE
  CODEX_OTLP_ENABLE
  CODEX_OTLP_ENDPOINT
  CODEX_OTLP_HEADERS
  CODEX_OTLP_KEYFILE
  CODEX_PATH
  CODEX_PROVIDER_BACKEND
  COMSPEC
  DISPLAY
  GITHUB_ACTIONS
  HOME
  HOMEDRIVE
  HOMEPATH
  KUBERNETES_SERVICE_HOST
  LANG
  LC_ALL
  LOCALAPPDATA
  LOGNAME
  OPENAI_API_KEY
  OPENAI_BASE_URL
  OPENAI_DEFAULT_MODEL
  PATH
  PATHEXT
  POWERSHELL
  PROGRAMDATA
  PROGRAMFILES
  PROGRAMFILES(X86)
  PROGRAMW6432
  PWSH
  SERPER_API_KEY
  SHELL
  SSH_CLIENT
  SSH_CONNECTION
  SSH_TTY
  SSL_CERT_FILE
  SYSTEMDRIVE
  SYSTEMROOT
  TAVILY_API_KEY
  TEMP
  TERM
  TMP
  TMPDIR
  TZ
  USER
  USERDOMAIN
  USERNAME
  USERPROFILE
  WAYLAND_DISPLAY
  WSL_DISTRO_NAME
  WSL_INTEROP
  __CF_USER_TEXT_ENCODING
|

config :codex_sdk, :env, Map.take(System.get_env(), env_allowlist)

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
