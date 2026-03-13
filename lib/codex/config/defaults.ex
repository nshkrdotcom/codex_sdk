defmodule Codex.Config.Defaults do
  # Specs are intentionally broader than literal return values to allow for
  # future runtime overrides without spec-breaking changes.
  @dialyzer :no_underspecs

  @moduledoc """
  Single source of truth for all Codex SDK default configuration values.

  Every tunable constant lives here as a zero-arity function. Consumers call
  these functions instead of defining their own module attributes or inline
  magic numbers. A handful of values support runtime override via
  `Application.get_env/3` — these are noted in the function docs.

  ## Quick example

      # In config/runtime.exs
      config :codex_sdk,
        rate_limit_default_delay_ms: 120_000,
        attachment_ttl_ms: 3_600_000

      # In your code — always resolved at call time
      Codex.Config.Defaults.rate_limit_default_delay_ms()
      #=> 120_000

  See the *Configuration Defaults* guide for the full table of tunables.
  """

  # ── Transport timeouts ──────────────────────────────────────────────────

  @doc "Overall exec process timeout in milliseconds (default: 3,600,000 — 1 hour)."
  @spec exec_timeout_ms() :: pos_integer()
  def exec_timeout_ms, do: 3_600_000

  @doc "Grace period for transport close before escalation (default: 2,000ms)."
  @spec transport_close_grace_ms() :: pos_integer()
  def transport_close_grace_ms, do: 2_000

  @doc "Grace period for transport shutdown before kill (default: 250ms)."
  @spec transport_shutdown_grace_ms() :: pos_integer()
  def transport_shutdown_grace_ms, do: 250

  @doc "Grace period for transport kill before demonitor (default: 250ms)."
  @spec transport_kill_grace_ms() :: pos_integer()
  def transport_kill_grace_ms, do: 250

  @doc "Maximum stdout buffer size in bytes (default: 1,048,576 — 1 MiB)."
  @spec transport_max_buffer_size() :: pos_integer()
  def transport_max_buffer_size, do: 1_048_576

  @doc "Maximum stderr buffer size in bytes (default: 262,144 — 256 KiB)."
  @spec transport_max_stderr_buffer_size() :: pos_integer()
  def transport_max_stderr_buffer_size, do: 262_144

  @doc "GenServer call timeout for transport operations (default: 5,000ms)."
  @spec transport_call_timeout_ms() :: pos_integer()
  def transport_call_timeout_ms, do: 5_000

  @doc "Timeout for force-close operations (default: 500ms)."
  @spec transport_force_close_timeout_ms() :: pos_integer()
  def transport_force_close_timeout_ms, do: 500

  @doc "Timeout for headless transport without subscribers (default: 5,000ms)."
  @spec transport_headless_timeout_ms() :: pos_integer()
  def transport_headless_timeout_ms, do: 5_000

  @doc "Delay before finalizing exit to drain remaining output (default: 25ms)."
  @spec transport_finalize_delay_ms() :: pos_integer()
  def transport_finalize_delay_ms, do: 25

  @doc "Maximum stdout lines drained per batch (default: 200)."
  @spec transport_max_lines_per_batch() :: pos_integer()
  def transport_max_lines_per_batch, do: 200

  # ── MCP timeouts ────────────────────────────────────────────────────────

  @doc "MCP `initialize` handshake timeout (default: 10,000ms)."
  @spec mcp_init_timeout_ms() :: pos_integer()
  def mcp_init_timeout_ms, do: 10_000

  @doc "MCP `tools/list` and `resources/list` timeout (default: 30,000ms)."
  @spec mcp_list_timeout_ms() :: pos_integer()
  def mcp_list_timeout_ms, do: 30_000

  @doc "MCP `tools/call` timeout (default: 60,000ms)."
  @spec mcp_call_timeout_ms() :: pos_integer()
  def mcp_call_timeout_ms, do: 60_000

  @doc "Default number of retries for MCP tool calls (default: 3)."
  @spec mcp_default_retries() :: non_neg_integer()
  def mcp_default_retries, do: 3

  @doc "MCP notification send timeout (default: 10,000ms)."
  @spec mcp_notification_timeout_ms() :: pos_integer()
  def mcp_notification_timeout_ms, do: 10_000

  @doc "Timeout for app-server MCP server requests like list/reload (default: 30,000ms)."
  @spec mcp_server_request_timeout_ms() :: pos_integer()
  def mcp_server_request_timeout_ms, do: 30_000

  # ── App-server timeouts ─────────────────────────────────────────────────

  @doc "App-server initialization/ready timeout (default: 10,000ms)."
  @spec app_server_init_timeout_ms() :: pos_integer()
  def app_server_init_timeout_ms, do: 10_000

  @doc "App-server JSON-RPC request timeout (default: 30,000ms)."
  @spec app_server_request_timeout_ms() :: pos_integer()
  def app_server_request_timeout_ms, do: 30_000

  @doc "Approval callback timeout (default: 30,000ms)."
  @spec approval_timeout_ms() :: pos_integer()
  def approval_timeout_ms, do: 30_000

  # ── Tool defaults ───────────────────────────────────────────────────────

  @doc "Shell command execution timeout (default: 60,000ms)."
  @spec shell_timeout_ms() :: pos_integer()
  def shell_timeout_ms, do: 60_000

  @doc "Maximum shell command output before truncation (default: 10,000 bytes)."
  @spec shell_max_output_bytes() :: pos_integer()
  def shell_max_output_bytes, do: 10_000

  @doc "Default maximum results for file search tool (default: 100)."
  @spec file_search_max_results() :: pos_integer()
  def file_search_max_results, do: 100

  @doc "Default maximum results for web search tool (default: 10)."
  @spec web_search_max_results() :: pos_integer()
  def web_search_max_results, do: 10

  # ── OAuth/HTTP timeouts ─────────────────────────────────────────────────

  @doc "HTTP timeout for OAuth token requests (default: 10,000ms)."
  @spec oauth_http_timeout_ms() :: pos_integer()
  def oauth_http_timeout_ms, do: 10_000

  @doc "OAuth token refresh skew — refresh this many ms before expiry (default: 30,000ms)."
  @spec oauth_refresh_skew_ms() :: pos_integer()
  def oauth_refresh_skew_ms, do: 30_000

  @doc "HTTP timeout for remote model list fetches (default: 10,000ms)."
  @spec remote_models_http_timeout_ms() :: pos_integer()
  def remote_models_http_timeout_ms, do: 10_000

  @doc "Session apply patch timeout (default: 60,000ms)."
  @spec sessions_apply_timeout_ms() :: pos_integer()
  def sessions_apply_timeout_ms, do: 60_000

  # ── Retry/backoff ───────────────────────────────────────────────────────

  @doc "Base delay for exponential backoff (default: 100ms)."
  @spec backoff_base_delay_ms() :: pos_integer()
  def backoff_base_delay_ms, do: 100

  @doc "Maximum backoff delay for exponential backoff (default: 5,000ms)."
  @spec backoff_max_ms() :: pos_integer()
  def backoff_max_ms, do: 5_000

  @doc "Maximum exponent for exponential backoff (default: 20)."
  @spec backoff_max_exponent() :: pos_integer()
  def backoff_max_exponent, do: 20

  @doc "Default maximum retry attempts for `Codex.Retry` (default: 4)."
  @spec retry_max_attempts() :: pos_integer()
  def retry_max_attempts, do: 4

  @doc "Base delay for `Codex.Retry` backoff (default: 200ms)."
  @spec retry_base_delay_ms() :: pos_integer()
  def retry_base_delay_ms, do: 200

  @doc "Maximum delay cap for `Codex.Retry` backoff (default: 10,000ms)."
  @spec retry_max_delay_ms() :: pos_integer()
  def retry_max_delay_ms, do: 10_000

  @doc """
  Default delay when rate-limited without an explicit Retry-After header.

  Overridable at runtime:

      config :codex_sdk, rate_limit_default_delay_ms: 120_000
  """
  @spec rate_limit_default_delay_ms() :: pos_integer()
  def rate_limit_default_delay_ms do
    Application.get_env(:codex_sdk, :rate_limit_default_delay_ms, 60_000)
  end

  @doc """
  Maximum delay for rate-limit backoff.

  Overridable at runtime:

      config :codex_sdk, rate_limit_max_delay_ms: 600_000
  """
  @spec rate_limit_max_delay_ms() :: pos_integer()
  def rate_limit_max_delay_ms do
    Application.get_env(:codex_sdk, :rate_limit_max_delay_ms, 300_000)
  end

  @doc """
  Multiplier for exponential rate-limit backoff.

  Overridable at runtime:

      config :codex_sdk, rate_limit_multiplier: 3.0
  """
  @spec rate_limit_multiplier() :: float()
  def rate_limit_multiplier do
    Application.get_env(:codex_sdk, :rate_limit_multiplier, 2.0)
  end

  # ── Buffer/size limits ──────────────────────────────────────────────────

  @doc "Default pop timeout for `StreamQueue` and `RunResultStreaming` (default: 5,000ms)."
  @spec stream_queue_pop_timeout_ms() :: pos_integer()
  def stream_queue_pop_timeout_ms, do: 5_000

  @doc "Default maximum agent turns for `RunConfig` (default: 10)."
  @spec max_agent_turns() :: pos_integer()
  def max_agent_turns, do: 10

  # ── URLs ────────────────────────────────────────────────────────────────

  @doc "Default OpenAI API base URL."
  @spec openai_api_base_url() :: String.t()
  def openai_api_base_url, do: "https://api.openai.com/v1"

  @doc "Default OpenAI Realtime WebSocket URL."
  @spec openai_realtime_ws_url() :: String.t()
  def openai_realtime_ws_url, do: "wss://api.openai.com/v1/realtime"

  @doc "Default sessions storage directory."
  @spec sessions_dir() :: String.t()
  def sessions_dir, do: Path.expand("~/.codex/sessions")

  # ── Model defaults ─────────────────────────────────────────────────────

  @doc "Default model for API auth contexts."
  @spec default_api_model() :: String.t()
  def default_api_model, do: "gpt-5.3-codex"

  @doc "Default model for ChatGPT auth contexts."
  @spec default_chatgpt_model() :: String.t()
  def default_chatgpt_model, do: "gpt-5.3-codex"

  @doc "Cache TTL for remote model list in seconds (default: 300 — 5 min)."
  @spec remote_models_cache_ttl_seconds() :: pos_integer()
  def remote_models_cache_ttl_seconds, do: 300

  # ── Protocol constants ──────────────────────────────────────────────────

  @doc "MCP protocol version string."
  @spec mcp_protocol_version() :: String.t()
  def mcp_protocol_version, do: "2025-06-18"

  @doc "JSON-RPC version."
  @spec jsonrpc_version() :: String.t()
  def jsonrpc_version, do: "2.0"

  @doc "Delimiter for qualified MCP tool names."
  @spec mcp_tool_name_delimiter() :: String.t()
  def mcp_tool_name_delimiter, do: "__"

  @doc "Maximum length for qualified MCP tool names."
  @spec mcp_max_tool_name_length() :: pos_integer()
  def mcp_max_tool_name_length, do: 64

  # ── File paths ──────────────────────────────────────────────────────────

  @doc "System-level config file path (default: `/etc/codex/config.toml`)."
  @spec system_config_path() :: String.t()
  def system_config_path, do: "/etc/codex/config.toml"

  @doc "Markers used to find project root (default: `[\".git\"]`)."
  @spec project_root_markers() :: [String.t()]
  def project_root_markers, do: [".git"]

  # ── Files/attachments ──────────────────────────────────────────────────

  @doc """
  Time-to-live for file attachments (default: 86,400,000ms — 24 hours).

  Overridable at runtime:

      config :codex_sdk, attachment_ttl_ms: 3_600_000
  """
  @spec attachment_ttl_ms() :: pos_integer()
  def attachment_ttl_ms do
    Application.get_env(:codex_sdk, :attachment_ttl_ms, 86_400_000)
  end

  @doc """
  Interval between attachment cleanup sweeps (default: 60,000ms — 1 minute).

  Overridable at runtime:

      config :codex_sdk, attachment_cleanup_interval_ms: 120_000
  """
  @spec attachment_cleanup_interval_ms() :: pos_integer()
  def attachment_cleanup_interval_ms do
    Application.get_env(:codex_sdk, :attachment_cleanup_interval_ms, 60_000)
  end

  # ── Audio/voice ─────────────────────────────────────────────────────────

  @doc "PCM16 audio sample rate in Hz (default: 24,000)."
  @spec pcm16_sample_rate() :: pos_integer()
  def pcm16_sample_rate, do: 24_000

  @doc "PCM16 bytes per sample (default: 2)."
  @spec pcm16_bytes_per_sample() :: pos_integer()
  def pcm16_bytes_per_sample, do: 2

  @doc "G.711 audio sample rate in Hz (default: 8,000)."
  @spec g711_sample_rate() :: pos_integer()
  def g711_sample_rate, do: 8_000

  @doc "G.711 bytes per sample (default: 1)."
  @spec g711_bytes_per_sample() :: pos_integer()
  def g711_bytes_per_sample, do: 1

  @doc "Default voice input sample rate in Hz (default: 24,000)."
  @spec voice_default_sample_rate() :: pos_integer()
  def voice_default_sample_rate, do: 24_000

  @doc "Default TTS audio buffer size in bytes (default: 120)."
  @spec tts_buffer_size() :: pos_integer()
  def tts_buffer_size, do: 120

  @doc "TTS stream receive timeout (default: 30,000ms)."
  @spec tts_stream_timeout_ms() :: pos_integer()
  def tts_stream_timeout_ms, do: 30_000

  @doc "Default STT model name."
  @spec stt_model() :: String.t()
  def stt_model, do: "gpt-4o-transcribe"

  @doc "Default TTS model name."
  @spec tts_model() :: String.t()
  def tts_model, do: "gpt-4o-mini-tts"

  @doc "Default TTS voice."
  @spec tts_default_voice() :: atom()
  def tts_default_voice, do: :ash

  @doc "Default STT turn detection configuration."
  @spec stt_default_turn_detection() :: map()
  def stt_default_turn_detection, do: %{"type" => "semantic_vad"}

  @doc "Default TTS instructions for partial-sentence streaming."
  @spec tts_default_instructions() :: String.t()
  def tts_default_instructions do
    "You will receive partial sentences. Do not complete the sentence just read out the text."
  end

  # ── Telemetry ───────────────────────────────────────────────────────────

  @doc "OpenTelemetry handler ID."
  @spec telemetry_otel_handler_id() :: String.t()
  def telemetry_otel_handler_id, do: "codex-otel-tracing"

  @doc "Default originator tag for telemetry metadata."
  @spec telemetry_default_originator() :: atom()
  def telemetry_default_originator, do: :sdk

  @doc "Default OpenTelemetry processor name."
  @spec telemetry_processor_name() :: atom()
  def telemetry_processor_name, do: :codex_sdk_processor

  # ── Client identity ────────────────────────────────────────────────────

  @doc "Client name sent during MCP initialization."
  @spec client_name() :: String.t()
  def client_name, do: "codex-elixir"

  @doc "Client version sent during MCP/app-server initialization."
  @spec client_version() :: String.t()
  def client_version do
    case Application.spec(:codex_sdk, :vsn) do
      nil -> "0.0.0"
      vsn -> to_string(vsn)
    end
  end

  # ── Preserved env keys ─────────────────────────────────────────────────

  @doc "Environment variable keys preserved when running with a cleared environment."
  @spec preserved_env_keys() :: [String.t()]
  def preserved_env_keys do
    ~w(HOME USER LOGNAME PATH LANG LC_ALL TMPDIR CODEX_HOME XDG_CONFIG_HOME XDG_CACHE_HOME)
  end

  # ── Default transport ───────────────────────────────────────────────────

  @doc """
  Default transport for thread options.

  Overridable at runtime:

      config :codex_sdk, default_transport: :exec
  """
  @spec default_transport() :: :exec | {:app_server, pid()}
  def default_transport do
    Application.get_env(:codex_sdk, :default_transport, :exec)
  end
end
