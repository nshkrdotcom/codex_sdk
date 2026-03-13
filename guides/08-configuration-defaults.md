# Configuration Defaults

The `Codex.Config.Defaults` module is the single source of truth for every
tunable constant in the Codex SDK. Instead of scattering magic numbers across
modules, all defaults live in one place and are referenced via zero-arity
function calls.

## How It Works

Every default is a public, zero-arity function with a `@doc` and `@spec`:

```elixir
Codex.Config.Defaults.exec_timeout_ms()
#=> 3_600_000

Codex.Config.Defaults.openai_api_base_url()
#=> "https://api.openai.com/v1"
```

Consuming modules reference these functions either directly or through module
attributes:

```elixir
# Direct call
timeout = Defaults.mcp_call_timeout_ms()

# Module attribute (resolved at compile time)
@default_timeout_ms Defaults.mcp_call_timeout_ms()
```

## Runtime Overrides

A subset of defaults support runtime override via `Application.get_env/3`.
These are clearly documented on each function. Override them in
`config/runtime.exs`:

```elixir
config :codex_sdk,
  rate_limit_default_delay_ms: 120_000,
  rate_limit_max_delay_ms: 600_000,
  rate_limit_multiplier: 3.0,
  attachment_ttl_ms: 3_600_000,
  attachment_cleanup_interval_ms: 120_000,
  default_transport: :exec
```

## Defaults Reference

### Transport Timeouts

| Function | Default | Description |
|----------|---------|-------------|
| `exec_timeout_ms/0` | 3,600,000 | Overall exec process timeout (1 hour) |
| `transport_close_grace_ms/0` | 2,000 | Grace period before escalating close |
| `transport_shutdown_grace_ms/0` | 250 | Grace period before kill |
| `transport_kill_grace_ms/0` | 250 | Grace period before demonitor |
| `transport_max_buffer_size/0` | 1,048,576 | Max stdout buffer (1 MiB) |
| `transport_max_stderr_buffer_size/0` | 262,144 | Max stderr buffer (256 KiB) |
| `transport_call_timeout_ms/0` | 5,000 | GenServer call timeout |
| `transport_force_close_timeout_ms/0` | 500 | Force-close timeout |
| `transport_headless_timeout_ms/0` | 5,000 | Headless transport timeout |
| `transport_finalize_delay_ms/0` | 25 | Finalize exit drain delay |
| `transport_max_lines_per_batch/0` | 200 | Max stdout lines per drain batch |

### MCP Timeouts

| Function | Default | Description |
|----------|---------|-------------|
| `mcp_init_timeout_ms/0` | 10,000 | Initialize handshake timeout |
| `mcp_list_timeout_ms/0` | 30,000 | tools/list, resources/list timeout |
| `mcp_call_timeout_ms/0` | 60,000 | tools/call timeout |
| `mcp_default_retries/0` | 3 | Default retry count |
| `mcp_notification_timeout_ms/0` | 10,000 | Notification send timeout |
| `mcp_server_request_timeout_ms/0` | 30,000 | App-server MCP request timeout |

### App-Server Timeouts

| Function | Default | Description |
|----------|---------|-------------|
| `app_server_init_timeout_ms/0` | 10,000 | Connection init timeout |
| `app_server_request_timeout_ms/0` | 30,000 | JSON-RPC request timeout |
| `approval_timeout_ms/0` | 30,000 | Approval callback timeout |

### Tool Defaults

| Function | Default | Description |
|----------|---------|-------------|
| `shell_timeout_ms/0` | 60,000 | Shell command timeout |
| `shell_max_output_bytes/0` | 10,000 | Max shell output before truncation |
| `file_search_max_results/0` | 100 | File search max results |
| `web_search_max_results/0` | 10 | Web search max results |

### OAuth / HTTP Timeouts

| Function | Default | Description |
|----------|---------|-------------|
| `oauth_http_timeout_ms/0` | 10,000 | OAuth token request timeout |
| `oauth_refresh_skew_ms/0` | 30,000 | Refresh before expiry threshold |
| `remote_models_http_timeout_ms/0` | 10,000 | Model list HTTP timeout |
| `sessions_apply_timeout_ms/0` | 60,000 | Session apply timeout |

### Retry / Backoff

| Function | Default | Runtime Key |
|----------|---------|-------------|
| `backoff_base_delay_ms/0` | 100 | — |
| `backoff_max_ms/0` | 5,000 | — |
| `backoff_max_exponent/0` | 20 | — |
| `retry_max_attempts/0` | 4 | — |
| `retry_base_delay_ms/0` | 200 | — |
| `retry_max_delay_ms/0` | 10,000 | — |
| `rate_limit_default_delay_ms/0` | 60,000 | `:rate_limit_default_delay_ms` |
| `rate_limit_max_delay_ms/0` | 300,000 | `:rate_limit_max_delay_ms` |
| `rate_limit_multiplier/0` | 2.0 | `:rate_limit_multiplier` |

### URLs

| Function | Default |
|----------|---------|
| `openai_api_base_url/0` | `"https://api.openai.com/v1"` |
| `openai_realtime_ws_url/0` | `"wss://api.openai.com/v1/realtime"` |
| `sessions_dir/0` | `~/.codex/sessions` |

### Model Defaults

| Function | Default |
|----------|---------|
| `default_api_model/0` | `"gpt-5.3-codex"` |
| `default_chatgpt_model/0` | `"gpt-5.3-codex"` |
| `remote_models_cache_ttl_seconds/0` | 300 |

### Protocol Constants

| Function | Default |
|----------|---------|
| `mcp_protocol_version/0` | `"2025-06-18"` |
| `jsonrpc_version/0` | `"2.0"` |
| `mcp_tool_name_delimiter/0` | `"__"` |
| `mcp_max_tool_name_length/0` | 64 |

### Files / Attachments

| Function | Default | Runtime Key |
|----------|---------|-------------|
| `attachment_ttl_ms/0` | 86,400,000 | `:attachment_ttl_ms` |
| `attachment_cleanup_interval_ms/0` | 60,000 | `:attachment_cleanup_interval_ms` |

### Audio / Voice

| Function | Default |
|----------|---------|
| `pcm16_sample_rate/0` | 24,000 |
| `pcm16_bytes_per_sample/0` | 2 |
| `g711_sample_rate/0` | 8,000 |
| `g711_bytes_per_sample/0` | 1 |
| `voice_default_sample_rate/0` | 24,000 |
| `tts_buffer_size/0` | 120 |
| `tts_stream_timeout_ms/0` | 30,000 |
| `stt_model/0` | `"gpt-4o-transcribe"` |
| `tts_model/0` | `"gpt-4o-mini-tts"` |
| `tts_default_voice/0` | `:ash` |
| `stt_default_turn_detection/0` | `%{"type" => "semantic_vad"}` |
| `tts_default_instructions/0` | *(partial-sentence streaming prompt)* |

### Telemetry

| Function | Default |
|----------|---------|
| `telemetry_otel_handler_id/0` | `"codex-otel-tracing"` |
| `telemetry_default_originator/0` | `:sdk` |
| `telemetry_processor_name/0` | `:codex_sdk_processor` |

### Client Identity

| Function | Default |
|----------|---------|
| `client_name/0` | `"codex-elixir"` |
| `client_version/0` | Application version or `"0.0.0"` |

### Other

| Function | Default | Runtime Key |
|----------|---------|-------------|
| `preserved_env_keys/0` | 10 standard env keys | — |
| `stream_queue_pop_timeout_ms/0` | 5,000 | — |
| `max_agent_turns/0` | 10 | — |
| `system_config_path/0` | `/etc/codex/config.toml` | — |
| `project_root_markers/0` | `[".git"]` | — |
| `default_transport/0` | `:exec` | `:default_transport` |
