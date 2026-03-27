<p align="center">
  <img src="assets/codex_sdk.svg" alt="Codex SDK Logo" width="200" height="200">
</p>

# Codex SDK for Elixir

[![CI](https://github.com/nshkrdotcom/codex_sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/nshkrdotcom/codex_sdk/actions/workflows/ci.yml)
[![Elixir](https://img.shields.io/badge/elixir-1.18.3-purple.svg)](https://elixir-lang.org)
[![OTP](https://img.shields.io/badge/otp-27.3.3-blue.svg)](https://www.erlang.org)
[![Hex.pm](https://img.shields.io/hexpm/v/codex_sdk.svg)](https://hex.pm/packages/codex_sdk)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-purple.svg)](https://hexdocs.pm/codex_sdk)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/nshkrdotcom/codex_sdk/blob/main/LICENSE)

An idiomatic Elixir SDK for embedding OpenAI's Codex agent in your workflows and applications. This SDK wraps the `codex-rs` executable, providing a complete, production-ready interface with streaming support and comprehensive event handling.

## Documentation Menu

- `README.md` - installation, quick start, and runtime boundaries
- `guides/01-getting-started.md` - first threads, turns, and sessions
- `guides/02-architecture.md` - transport layering and ownership boundaries
- `guides/03-api-guide.md` - public modules and common call patterns
- `guides/07-models-and-reasoning.md` - shared catalog projections and reasoning controls
- `guides/08-configuration-defaults.md` - config precedence and default resolution

## Features

- **End-to-End Codex Lifecycle**: Spawn, resume, and manage full Codex threads with rich turn instrumentation.
- **Multi-Transport Support**: Default `:exec` compatibility selector for the core-backed exec JSONL lane (`codex exec --json`) plus stateful app-server JSON-RPC via managed local stdio children or managed remote websockets.
- **CLI Passthrough and PTY Sessions**: `Codex.CLI` can launch root `codex`, `cloud`, `completion`, `features`, `mcp`, `sandbox`, `resume`, `fork`, `app-server`, and other command-surface workflows directly, including remote-root and websocket-auth app-server flags.
- **Native OAuth**: `Codex.OAuth` provides SDK-managed browser/device login, refresh, status, and logout with upstream-compatible `auth.json` persistence or memory-only sessions.
- **Upstream Compatibility**: Mirrors Codex CLI flags (profile/OSS/full-auto/color/search/config overrides/review/resume) and handles app-server protocol drift (e.g. MCP list method rename fallbacks).
- **Streaming & Structured Output**: Real-time events, per-thread output schemas, reasoning summary/content preservation, and typed app-server deltas.
- **File & Attachment Pipeline**: Secure temp file registry and change events.
- **Approval Hooks & Sandbox Policies**: Dynamic or static approval flows with registry-backed persistence.
- **Collaboration & Personality Controls**: Collaboration modes, personality overrides, and web search mode toggles.
- **Tooling & MCP Integration**: Built-in registry for Codex tool manifests, MCP client helpers, and elicitation handling.
- **Observability-Ready**: Telemetry spans, OTLP exporters gated by environment flags, usage stats, and rate limit snapshots.
- **Realtime API Support**: Full integration with OpenAI Realtime API for bidirectional voice interactions with WebSocket streaming.
- **Voice Pipeline**: Non-realtime STT -> Workflow -> TTS pipeline with streaming audio support and multi-turn conversations.

## Installation

Add `codex_sdk` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:codex_sdk, "~> 0.15.0"}
  ]
end
```

## Prerequisites

You must have the `codex` CLI installed. Install it via npm or Homebrew:

```bash
# Using npm
npm install -g @openai/codex

# Using Homebrew
brew install codex
```

The SDK does not vendor `codex-rs`; it shells out to the `codex` executable on your system. Path
resolution follows this order:

1. `codex_path_override` supplied in `Codex.Options.new/1`
2. `CODEX_PATH` environment variable
3. `System.find_executable("codex")`

Make sure the binary at the resolved location is executable and kept up to date.

For authentication, sign in with your ChatGPT account (this stores credentials for the CLI):

```bash
codex
# Select "Sign in with ChatGPT"
```

Alternatively, set `CODEX_API_KEY` before starting your BEAM node. For normal CLI-backed SDK
execution, auth resolution is:

1. `CODEX_API_KEY`
2. `auth.json` `OPENAI_API_KEY`
3. ChatGPT OAuth tokens stored under `CODEX_HOME` (default `~/.codex/auth.json`, with legacy credential file support)

The SDK now also exposes native OAuth login via `Codex.OAuth`:

```elixir
{:ok, result} =
  Codex.OAuth.login(
    storage: :file,
    interactive?: true
  )
```

Persistent `Codex.OAuth` login writes upstream-compatible `auth.json` and respects upstream
`auth_mode`. Memory-only OAuth is also available for host-managed and app-server external auth
flows. `openai_base_url` does not change the OAuth issuer; use `auth_issuer` only when you need
to override the login authority itself.

Environment-aware OAuth behavior matches current native-app guidance:

- local desktop prefers browser auth with PKCE + loopback callback
- WSL starts with the browser path, then falls back to device code when the callback is unreachable
- SSH/headless/container environments prefer device code
- CI and other non-interactive environments never auto-start login; existing credentials are used or the call fails clearly

ChatGPT plan types are normalized before they surface through SDK auth/status
structs or app-server external-auth forwarding. In particular, `hc` and
`enterprise` normalize to `"enterprise"`, while `education` and `edu`
normalize to `"edu"`.

If `cli_auth_credentials_store = "keyring"` is set in config and keyring support is unavailable,
the SDK logs a warning and skips file-based tokens (remote model fetch falls back to bundled models).
When `cli_auth_credentials_store = "auto"` and keyring is unavailable, the SDK falls back to file-based auth.

When an API key is supplied, the SDK forwards it as both `CODEX_API_KEY` and `OPENAI_API_KEY`
to the codex subprocess to align with provider expectations.

Base URL precedence is: explicit `:base_url` in `Codex.Options.new/1`, then layered
`openai_base_url` from `config.toml`, then `OPENAI_BASE_URL`, then the OpenAI default
(`https://api.openai.com/v1`). User-defined `[model_providers]` entries extend the built-in
provider set, but reserved built-ins such as `openai`, `ollama`, and `lmstudio` cannot be
redefined.

Custom trust roots use `CODEX_CA_CERTIFICATE` first and `SSL_CERT_FILE` second. Blank values are
ignored. The same PEM bundle is applied consistently to Codex CLI subprocesses, direct HTTP
clients, remote model fetches, MCP HTTP/OAuth, realtime websockets, and voice HTTP requests.

## Centralized Model Selection

`codex_sdk` no longer owns the active model catalog, fallback rules, or default
selection policy. That authority now lives in `cli_subprocess_core`.

The authoritative path is:

- `CliSubprocessCore.ModelRegistry.resolve/3`
- `CliSubprocessCore.ModelRegistry.validate/2`
- `CliSubprocessCore.ModelRegistry.default_model/2`
- `CliSubprocessCore.ModelRegistry.build_arg_payload/3`
- `CliSubprocessCore.ModelInput.normalize/3`

`Codex.Options.new/1` now delegates mixed-input normalization to
`CliSubprocessCore.ModelInput.normalize/3`, then projects the current `model`
and `reasoning_effort` from the authoritative shared `model_payload`.
`Codex.Models` is now a read-only projection of the shared core catalog. It no
longer owns a separate catalog or a separate fallback/defaulting path.

Operationally, that means:

- explicit request wins first
- environment override comes next
- provider default and remote default are core-owned, not SDK-owned
- missing provider, missing model, placeholder model input, and invalid
  reasoning effort all fail through the core error contract

## Local Ollama Through The Shared Core Contract

`codex_sdk` now consumes the core-owned Codex OSS payload for local Ollama.

Use:

```elixir
{:ok, opts} =
  Codex.Options.new(%{
    model: "llama3.2",
    provider_backend: :oss,
    oss_provider: "ollama"
  })
```

That causes the shared core registry to:

- validate the Ollama runtime
- validate the local model id
- keep `gpt-oss:20b` as the default validated OSS model when no explicit model
  is supplied
- return a payload that renders `--oss --local-provider ollama --model llama3.2`

The SDK does not infer those flags on its own.
- CLI argument rendering only emits `--model` from a non-empty resolved value

If `ollama_base_url:` is supplied, that endpoint is carried inside the
payload-owned env overrides as `CODEX_OSS_BASE_URL`. The exec and app-server
transports both consume that payload data directly instead of keeping a second
raw base-url path alive downstream.

When the chosen local model is outside Codex's built-in model metadata catalog,
the upstream CLI may warn that it is using fallback metadata. That is an
upstream degraded-mode distinction, not a hard model rejection in `codex_sdk`.

For the stateful app-server transport, the same resolved payload is rendered into
supported `codex app-server --config ...` startup overrides plus `thread/start`
`modelProvider` selection. The SDK does not pass unsupported exec-only OSS flags
to `codex app-server`.

`./examples/run_all.sh --ollama` uses that same route. It runs the CLI-backed
example suite against local Ollama and skips the direct OpenAI realtime/voice
examples, which are a separate subsystem and are not Ollama-backed.

Use `Codex.Models.default_model/0`, `Codex.Models.list_visible/1`, and
`Codex.Models.default_reasoning_effort/1` as convenience readers over that
shared contract.

See the [OpenAI Codex documentation](https://github.com/openai/codex) for more authentication options.

## Quick Start

### Basic Usage

```elixir
# Start a new conversation
{:ok, thread} = Codex.start_thread()

# Run a turn and get results
{:ok, result} = Codex.Thread.run(thread, "Explain the purpose of GenServers in Elixir")

# Access the final response
IO.puts(result.final_response)

# Inspect all items (messages, reasoning, commands, file changes, etc.)
IO.inspect(result.items)

# Continue the conversation
{:ok, next_result} = Codex.Thread.run(thread, "Give me an example")
```

### App-server Transport (Optional)

The SDK defaults to the `:exec` compatibility selector for the core-backed exec
JSONL lane. To use the stateful app-server transport:

```elixir
{:ok, codex_opts} = Codex.Options.new(%{api_key: System.fetch_env!("CODEX_API_KEY")})
{:ok, conn} = Codex.AppServer.connect(codex_opts)

{:ok, thread} =
  Codex.start_thread(codex_opts, %{
    transport: {:app_server, conn},
    working_directory: "/project"
  })

{:ok, result} = Codex.Thread.run(thread, "List the available skills for this repo")

{:ok, %{"data" => skills}} = Codex.AppServer.skills_list(conn, cwds: ["/project"])
```

When you need experimental app-server fields such as `approvals_reviewer` or
granular approval policies, create the connection with
`Codex.AppServer.connect(codex_opts, experimental_api: true)`.

When the managed `codex app-server` child should run against an isolated repo or
temporary Codex home, pass launch overrides to `connect/2` itself:

```elixir
tmp_home = Path.join(System.tmp_dir!(), "codex-sdk-app-server-home")

{:ok, conn} =
  Codex.AppServer.connect(codex_opts,
    cwd: "/project",
    process_env: %{
      "CODEX_HOME" => tmp_home,
      "HOME" => Path.dirname(tmp_home),
      "USERPROFILE" => Path.dirname(tmp_home)
    }
  )
```

`cwd` and `process_env` apply to the app-server child process. Per-thread working
directories still belong on `working_directory` / `cwd` thread params.

For a managed remote app-server websocket instead of a local `codex app-server`
child, use `Codex.AppServer.connect_remote/2`:

```elixir
{:ok, conn} =
  Codex.AppServer.connect_remote(
    "wss://app-server.example/ws",
    auth_token_env: "CODEX_REMOTE_AUTH_TOKEN",
    client_name: "my_app",
    experimental_api: true
  )
```

`connect_remote/2` keeps the same pid contract as `connect/2`, so the existing
`Codex.AppServer.*` request helpers, `disconnect/1`, `alive?/1`, `subscribe/2`,
`unsubscribe/1`, and `respond/3` work unchanged. Bearer auth headers are only
attached for `wss://` or loopback `ws://` endpoints; plain non-loopback
`ws://` plus `auth_token` or `auth_token_env` is rejected. Remote OAuth only
supports `oauth: [storage: :memory]`; persistent child-login preflight
(`:file` / `:auto`) is not available because remote mode does not spawn a local
child or child `CODEX_HOME`.

`connect/2` also supports OAuth-aware child auth bootstrapping:

```elixir
{:ok, conn} =
  Codex.AppServer.connect(codex_opts,
    experimental_api: true,
    process_env: %{"CODEX_HOME" => tmp_home},
    oauth: [
      mode: :auto,
      storage: :memory,
      auto_refresh: true
    ]
  )
```

For `oauth: [storage: :file | :auto]`, the SDK resolves auth against the effective child
`CODEX_HOME` before launching the child. For `oauth: [storage: :memory]`, it starts the child,
logs in with external `chatgptAuthTokens`, and attaches a connection-owned refresh responder.
Set `auto_refresh: false` when you want to handle `account/chatgptAuthTokens/refresh` requests
yourself.

Multi-modal input is supported on app-server transport:

```elixir
input = [
  %{type: :text, text: "Explain this screenshot"},
  %{type: :local_image, path: "/tmp/screenshot.png"}
]

{:ok, result} = Codex.Thread.run(thread, input)
```

Note: the `:exec` compatibility lane still accepts text input only; list inputs
return `{:error, {:unsupported_input, :exec}}`.

App-server-only APIs include:

- `Codex.AppServer.thread_list/2`, `thread_archive/2`, `thread_read/3`, `thread_fork/3`, `thread_rollback/3`, `thread_loaded_list/2`
- `Codex.AppServer.model_list/2`, `config_read/2`, `config_write/4`, `config_batch_write/3`, `config_requirements/1`
- `Codex.AppServer.experimental_feature_list/2`, `experimental_feature_enablement_set/2`
- `Codex.AppServer.fs_read_file/2`, `fs_write_file/3`, `fs_create_directory/3`, `fs_get_metadata/2`, `fs_read_directory/2`, `fs_remove/3`, `fs_copy/4`
- `Codex.AppServer.plugin_list/2`, `plugin_read/3`, `plugin_install/4`, `plugin_uninstall/3`
- `Codex.AppServer.skills_config_write/3`, `collaboration_mode_list/1`, `apps_list/2`
- `Codex.AppServer.turn_interrupt/3`
- `Codex.AppServer.thread_shell_command/3` (thread-bound `!` workflow)
- `Codex.AppServer.fuzzy_file_search/3` (legacy v1 helper used by `@` file search)
- `Codex.AppServer.command_write_stdin/4` (interactive command stdin)
- `Codex.AppServer.Account.*` and `Codex.AppServer.Mcp.*` endpoints (including MCP reload)
- Approvals via `Codex.AppServer.subscribe/2` + `Codex.AppServer.respond/3`

On app-server transport, thread options now forward current upstream routing fields such as
`ephemeral`, `service_name`, and `service_tier`; turn options can override `service_tier`
per `Codex.Thread.run/3`. Plugin response maps also preserve newer upstream auth metadata such
as `needsAuth`, and subscriptions adapt `mcpServer/startupStatus/updated` into typed
`Codex.Events` structs.

Runnable app-server demos now include `examples/live_app_server_filesystem.exs` for `fs/*`
and `examples/live_app_server_plugins.exs` for `plugin/list` + `plugin/read` using a disposable
repo-local marketplace fixture plus an isolated temporary `CODEX_HOME`, rather than your real
plugin config; that example now also prints `needsAuth` when the connected build includes it.
`examples/live_app_server_approvals.exs` uses the same child-process isolation pattern to enable
the under-development approval features only inside a temporary `CODEX_HOME`, so it can exercise
live command/file/permissions approval flows without mutating your real Codex settings or writing
inside this repository.

App-server v2 input blocks support `text`, `image`, `localImage`, `skill`, and `mention`.
Legacy app-server v1 conversation flows are available via `Codex.AppServer.V1`.

Experimental feature enablement is forwarded without a stale local allowlist:

```elixir
{:ok, %{"data" => features}} = Codex.AppServer.experimental_feature_list(conn)

{:ok, _} =
  Codex.AppServer.experimental_feature_enablement_set(conn,
    apps: true,
    plugins: false
  )
```

The SDK forwards the `enablement` map as given and lets the server validate the
current supported keys.

### Raw CLI Passthrough and Interactive Sessions

Use `Codex.CLI.run/2` when you want literal command-surface parity with the upstream terminal client, and `Codex.CLI.interactive/2` or `Codex.CLI.start/2` when you need a long-running or PTY-backed session.

Under the hood, `Codex.CLI.run/2` and the synchronous wrapper functions ride
the shared `CliSubprocessCore.Command` lane. `Codex.CLI.Session`,
`Codex.AppServer`, and `Codex.MCP.Transport.Stdio` preserve their public Codex
entrypoints while mapping raw PTY, stdio transport, stdin, stderr, interrupt,
and exit lifecycle onto `CliSubprocessCore.RawSession`.

The ownership line is now:

- `cli_subprocess_core` owns all Codex subprocess lifecycle, transport, and
  `erlexec` interaction
- `codex_sdk` owns Codex-native semantics, typed events, request/response
  mapping, app-server APIs, MCP helpers, realtime, and voice
- realtime and voice remain provider-owned because they call OpenAI APIs
  directly instead of spawning Codex CLI subprocesses

When `codex_sdk` is installed alongside `agent_session_manager`, ASM
auto-detects the runtime kit and activates `ASM.Extensions.ProviderSDK.Codex`
in `ASM.Extensions.ProviderSDK.available_extensions/0` and
`ASM.Extensions.ProviderSDK.capability_report/0`. That ASM seam is only a
bridge into Codex-native helpers such as app-server entrypoints; the actual
app-server, MCP, realtime, and voice APIs remain here.

```elixir
{:ok, codex_opts} = Codex.Options.new(%{})

# Safe one-shot command wrappers
{:ok, completion} = Codex.CLI.completion("zsh", codex_opts: codex_opts)
IO.puts(completion.stdout)

{:ok, features} = Codex.CLI.features_list(codex_opts: codex_opts)
IO.puts(features.stdout)

# Arbitrary raw command surface
{:ok, result} =
  Codex.CLI.run(
    ["cloud", "list", "--json"],
    codex_opts: codex_opts
  )

IO.puts(result.stdout)

# Prompt-mode root codex session over a PTY
{:ok, session} =
  Codex.CLI.interactive(
    "Summarize this repository in three bullets.",
    codex_opts: codex_opts
  )

:ok = Codex.CLI.Session.close_input(session)
{:ok, session_result} = Codex.CLI.Session.collect(session)
IO.puts(session_result.stdout)
```

This layer is also the simplest way to reach CLI-only workflows such as `codex completion`, `codex cloud`, `codex execpolicy`, `codex features`, `codex mcp-server`, and the root interactive client without dropping down to `System.cmd/3` yourself.

Current upstream parity helpers also include:

- `Codex.CLI.interactive/2`, `resume/2`, and `fork/2` accept `remote:` and `remote_auth_token_env:`
- `Codex.CLI.resume/2` accepts `include_non_interactive: true`
- `Codex.CLI.app_server/1` forwards websocket auth flags: `ws_auth`, `ws_token_file`, `ws_shared_secret_file`, `ws_issuer`, `ws_audience`, and `ws_max_clock_skew_seconds`

`ws_auth` atoms normalize to upstream CLI values such as
`:capability_token -> capability-token` and
`:signed_bearer_token -> signed-bearer-token`.

### Streaming Responses

For real-time processing of events as they occur:

```elixir
{:ok, thread} = Codex.start_thread()

{:ok, stream} = Codex.Thread.run_streamed(
  thread,
  "Analyze this codebase and suggest improvements"
)

# Process events as they arrive
for event <- stream do
  case event do
    %Codex.Events.ItemStarted{item: item} ->
      IO.puts("New item: #{item.type}")

    %Codex.Events.ItemCompleted{item: %{type: "agent_message", text: text}} ->
      IO.puts("Response: #{text}")

    %Codex.Events.TurnCompleted{usage: usage} ->
      IO.puts("Tokens used: #{usage.input_tokens + usage.output_tokens}")

    _ ->
      :ok
  end
end
```

### Structured Output

Request JSON responses conforming to a specific schema:

```elixir
schema = %{
  "type" => "object",
  "properties" => %{
    "summary" => %{"type" => "string"},
    "issues" => %{
      "type" => "array",
      "items" => %{
        "type" => "object",
        "properties" => %{
          "severity" => %{"type" => "string", "enum" => ["low", "medium", "high"]},
          "description" => %{"type" => "string"},
          "file" => %{"type" => "string"}
        },
        "required" => ["severity", "description"]
      }
    }
  },
  "required" => ["summary", "issues"]
}

{:ok, thread} = Codex.start_thread()

{:ok, result} = Codex.Thread.run(
  thread,
  "Analyze the code quality of this project",
  output_schema: schema
)

# Parse the JSON response
{:ok, data} = Jason.decode(result.final_response)
IO.inspect(data["issues"])
```

### Runnable Examples

The repository ships with standalone scripts under `examples/` that you can execute via `mix run`. Live scripts (prefixed `live_`) hit the real Codex CLI using your existing CLI login—no extra API key wiring needed. To run everything sequentially:

```bash
./examples/run_all.sh
```

Examples that start Codex turns prefer `reasoning_effort: :low`; the SDK will coerce that to a higher supported level when the selected model requires it.

Or run individual scripts:

```bash
# Basic blocking turn and item traversal
mix run examples/basic_usage.exs

# Streaming patterns (real-time, progressive, stateful)
mix run examples/streaming.exs progressive

# Live model defaults + compaction/usage handling (CLI login or CODEX_API_KEY)
mix run examples/live_usage_and_compaction.exs "summarize recent changes"

# Live exec controls (env injection, cancellation token, timeout)
mix run examples/live_exec_controls.exs "list files and print CODEX_DEMO_ENV"

# Structured output decoding and struct mapping
mix run examples/structured_output.exs struct

# Conversation/resume workflow helpers
mix run examples/conversation_and_resume.exs save-resume

# Concurrency + collaboration demos
mix run examples/concurrency_and_collaboration.exs parallel lib/codex/thread.ex lib/codex/exec.ex

# Auto-run tool bridging (forwards outputs/failures to codex exec)
mix run examples/tool_bridging_auto_run.exs

# Live two-turn session using CLI login or CODEX_API_KEY
mix run examples/live_session_walkthrough.exs "your prompt here"

# Live tooling stream: shows shell + MCP events and falls back to last agent message
mix run examples/live_tooling_stream.exs "optional prompt"

# Live telemetry stream: prints thread/turn ids, source metadata, usage deltas, diffs, and compaction (low reasoning, fast prompt)
mix run examples/live_telemetry_stream.exs

# Live CLI demo (requires authenticated codex CLI or CODEX_API_KEY)
mix run examples/live_cli_demo.exs "What is the capital of France?"

# Live Codex CLI passthrough helpers
mix run examples/live_cli_passthrough.exs completion zsh

# Live PTY-backed prompt-mode root session
mix run examples/live_cli_session.exs "Summarize this repository in three bullets."
```


### Realtime Voice Interactions

For bidirectional voice interactions using the OpenAI Realtime API:
- Auth precedence for realtime/voice API keys is:
  `CODEX_API_KEY` -> `auth.json` `OPENAI_API_KEY` -> `OPENAI_API_KEY`.

`Codex.Realtime.Diagnostics.probe_text_turn/1` now uses a minimal
schema-compatible probe and treats `unknown_parameter`-style schema drift as a
protocol-incompatible skip reason instead of a hard failure. `Codex.Realtime.Session`
also defers follow-up `response.create` calls until the active response reaches
`response.done`, so overlapping user input and tool output no longer trigger
premature create requests.

```elixir
alias Codex.Realtime

# Create a realtime agent
agent = Realtime.agent(
  name: "VoiceAssistant",
  instructions: "You are a helpful voice assistant. Keep responses brief."
)

# Configure session options
config = %Codex.Realtime.Config.RunConfig{
  model_settings: %Codex.Realtime.Config.SessionModelSettings{
    voice: "alloy",
    turn_detection: %Codex.Realtime.Config.TurnDetectionConfig{
      type: :semantic_vad,
      eagerness: :medium
    }
  }
}

# Start a realtime session
{:ok, session} = Realtime.run(agent, config: config)

# Subscribe to events
Realtime.subscribe(session, self())

# Send audio and receive responses (commit on final chunk)
Realtime.send_audio(session, audio_data, commit: true)
```

`Realtime.Session` also traps linked WebSocket exits and keeps processing other session
messages while tool calls are running.

### Voice Pipeline (Non-Realtime)

For STT -> Workflow -> TTS processing:

```elixir
alias Codex.Voice.{Pipeline, SimpleWorkflow, Config}

# Create a simple workflow
workflow = SimpleWorkflow.new(
  fn text -> ["You said: #{text}. How can I help?"] end,
  greeting: "Hello! I'm ready to listen."
)

# Configure the pipeline
config = %Config{
  workflow_name: "VoiceDemo",
  tts_settings: %Config.TTSSettings{voice: :nova}
}

# Create and run the pipeline
{:ok, pipeline} = Pipeline.start_link(workflow: workflow, config: config)
{:ok, result} = Pipeline.run(pipeline, audio_input)

# Process streamed audio output
for event <- result do
  case event do
    %Codex.Voice.Events.VoiceStreamEventAudio{data: data} ->
      # Handle audio chunk
      play_audio(data)
    _ -> :ok
  end
end
```

See `examples/realtime_*.exs` and `examples/voice_*.exs` for comprehensive demos.

### Resuming Threads

Threads are persisted under `$CODEX_HOME/sessions` (default `~/.codex/sessions`). Resume previous
conversations:

```elixir
thread_id = "thread_abc123"
{:ok, thread} = Codex.resume_thread(thread_id)

{:ok, result} = Codex.Thread.run(thread, "Continue from where we left off")
```

Resume the most recent session (equivalent to `codex exec resume --last`):

```elixir
{:ok, thread} = Codex.resume_thread(:last)
{:ok, result} = Codex.Thread.run(thread, "Continue from where we left off")
```

### Session Helpers

The CLI writes session logs under `$CODEX_HOME/sessions` (default `~/.codex/sessions`). The SDK
can list them and apply or undo diffs locally:

```elixir
{:ok, sessions} = Codex.Sessions.list_sessions()

{:ok, result} = Codex.Sessions.apply(diff, cwd: "/path/to/repo")
{:ok, _undo} = Codex.Sessions.undo(ghost_snapshot, cwd: "/path/to/repo")
```

### Configuration Options

```elixir
# Codex-level options
{:ok, codex_options} =
  Codex.Options.new(
    api_key: System.fetch_env!("CODEX_API_KEY"),
    codex_path_override: "/custom/path/to/codex",
    telemetry_prefix: [:codex, :sdk],
    model: "o1",
    reasoning_effort: :high,  # :none | :minimal | :low | :medium | :high | :xhigh
    model_personality: :friendly,
    review_model: Codex.Models.default_model(),
    tool_output_token_limit: 512,
    history: %{persistence: "local", max_bytes: 1_000_000},
    config: %{"model_reasoning_summary" => "concise"}  # global --config baseline
  )

# Thread-level options
{:ok, thread_options} =
  Codex.Thread.Options.new(
    metadata: %{project: "codex_sdk"},
    labels: %{environment: "dev"},
    auto_run: true,
    sandbox: :strict,
    approval_timeout_ms: 45_000,
    ephemeral: true,          # app-server thread/fork lifecycle hint
    service_name: "my_app",   # app-server routing hint
    service_tier: :flex,      # :auto | :default | :flex | :priority
    web_search_mode: :cached,  # :disabled | :cached | :live (explicit :disabled forces disable override)
    personality: :pragmatic,   # :friendly | :pragmatic | :none (works consistently on exec/app-server)
    collaboration_mode: :plan  # :plan | :pair_programming | :code | :default | :execute | :custom (app-server)
  )

{:ok, thread} = Codex.start_thread(codex_options, thread_options)

# Run-level options (validated by Codex.RunConfig.new/1)
run_options = %{
  run_config: %{
    auto_previous_response_id: true
  }
}

{:ok, result} = Codex.Thread.run(thread, "Your prompt", run_options)
IO.inspect(result.last_response_id)
# Note: last_response_id remains nil until codex exec emits response_id fields.

# Turn-level options
turn_options = %{output_schema: my_json_schema, personality: :friendly, service_tier: :priority}

{:ok, result} = Codex.Thread.run(thread, "Your prompt", turn_options)

# Exec controls: inject env, set cancellation token/timeout/idle timeout (forwarded to codex exec)
turn_options = %{
  env: %{"CODEX_DEMO_ENV" => "from-sdk"},
  cancellation_token: "demo-token-123",
  timeout_ms: 120_000,
  stream_idle_timeout_ms: 300_000
}

# The SDK also sets CODEX_INTERNAL_ORIGINATOR_OVERRIDE=codex_sdk_elixir
# unless you provide your own value in `env`.

{:ok, stream} =
  Codex.Thread.run_streamed(thread, "List three files and echo $CODEX_DEMO_ENV", turn_options)

# Opt-in retry and rate limit handling
{:ok, thread_opts} =
  Codex.Thread.Options.new(
    retry: true,
    retry_opts: [max_attempts: 3],
    rate_limit: true,
    rate_limit_opts: [max_attempts: 3]
  )
```

### Config Overrides

Options-level, thread-level, and turn-level config overrides are forwarded as
`--config key=value` flags to the Codex CLI (exec transport). For app-server transport,
typed derived settings plus options-level config overrides are merged into the structured
config payload when unset. Four layers of precedence apply for exec — later wins:

1. **Options-level global** — `Codex.Options.new(config: ...)`
2. **Derived** — automatically generated from typed `Codex.Options` and `Codex.Thread.Options` fields
3. **Thread-level** — `Codex.Thread.Options.config_overrides`
4. **Turn-level** — `config_overrides` in turn opts passed to `Thread.run/3`

Nested maps are auto-flattened to dotted-path keys:

```elixir
# These two are equivalent:
config_overrides: %{"features" => %{"web_search_request" => true}}
config_overrides: [{"features.web_search_request", true}]
```

Override values are validated at runtime and must be TOML-compatible primitives:
strings, booleans, integers/floats, arrays, and nested maps. Unsupported values
(`nil`, tuples, PIDs, functions, etc.) return an error before the CLI is invoked.

When you explicitly disable web search (`web_search_enabled: false` or
`web_search_mode: :disabled`), the SDK emits `web_search="disabled"` so that
thread-level intent overrides existing CLI config. When you leave defaults
untouched, the SDK now mirrors current Codex CLI behavior: cached web search
for normal local runs, and live web search when you opt into full-access
sandboxing (`:danger_full_access`, `:permissive`, or
`dangerously_bypass_approvals_and_sandbox: true`).

### Approval Hooks

Codex ships with approval policies and hooks so you can review potentially destructive actions
before the agent executes them. Policies are provided per-thread:

```elixir
policy = Codex.Approvals.StaticPolicy.deny(reason: "manual review required")

{:ok, thread_opts} =
  Codex.Thread.Options.new(
    sandbox: :strict,
    approval_policy: policy,
    approval_timeout_ms: 60_000
  )

{:ok, thread} = Codex.start_thread(%Codex.Options{}, thread_opts)
```

To integrate with external workflow tools, implement the `Codex.Approvals.Hook` behaviour and
set it as the `approval_hook`:

```elixir
defmodule MyApp.ApprovalHook do
  @behaviour Codex.Approvals.Hook

  def review_tool(event, context, _opts) do
    # Route to Slack/Jira/etc. and await a decision
    if MyApp.RiskEngine.requires_manual_review?(event, context) do
      {:deny, "pending review"}
    else
      :allow
    end
  end
end

{:ok, thread_opts} = Codex.Thread.Options.new(approval_hook: MyApp.ApprovalHook)
{:ok, thread} = Codex.start_thread(%Codex.Options{}, thread_opts)
```

Hooks can be synchronous or async (see `Codex.Approvals.Hook` for callback semantics), and all
decisions emit telemetry so you can audit approvals externally.

Codex respects upstream safe-command markers: tool events flagged with `requires_approval: false`
bypass approval gating automatically, keeping low-risk workspace actions fast while still blocking
requests that require review.

For app-server file-change approvals, hooks can return `{:allow, grant_root: "/path"}` to accept
the proposed root for the current session.

App-server permission approvals use structured grant payloads rather than string decisions.
Hooks can implement `review_permissions/3` and return `:allow`, `{:allow, permissions: ..., scope: :turn | :session}`,
or `{:deny, reason}`. App-server streams now also surface `%Codex.Events.GuardianApprovalReviewStarted{}`,
`%Codex.Events.GuardianApprovalReviewCompleted{}`, and `%Codex.Events.ServerRequestResolved{}` when
the connected Codex build emits guardian review and request-resolution notifications. Use
`approvals_reviewer: :user | :guardian_subagent` on thread options to control upstream review routing.
The SDK also emits `%Codex.Events.CommandApprovalRequested{}` and
`%Codex.Events.FileApprovalRequested{}` for app-server request approvals, preserving upstream
fields such as `approval_id`, `command_actions`, `network_approval_context`,
`additional_permissions`, `available_decisions`, and `grant_root` in normalized snake_case.
These app-server approval fields are experimental upstream, so connect with
`experimental_api: true` before using them. For live request-permissions flows,
use a granular approval policy with `request_permissions: true`, but note that upstream keeps
`request_permissions_tool`, `exec_permission_approvals`, and `guardian_approval` disabled by
default on stock CLI installs. The SDK accepts both
the local inline shape (`%{type: :granular, request_permissions: true}`) and the
upstream external-tagged shape (`%{granular: %{request_permissions: true}}`); malformed
granular maps now fail fast instead of being silently dropped.

Tool-call events can also arrive pre-approved via `approved_by_policy` (or `approved`) from the
CLI; the SDK mirrors that bypass and skips hooks while still emitting telemetry. Sandbox warnings
are normalized so Windows paths dedupe cleanly (e.g., `C:/Temp` and `C:\\Temp` coalesce). See
`examples/sandbox_warnings_and_approval_bypass.exs` for a runnable walkthrough.

### File Attachments & Registries

Stage attachments once and reuse them across turns or threads with the built-in registry:

```elixir
{:ok, attachment} = Codex.Files.stage("reports/summary.md", ttl_ms: :infinity)

thread_opts =
  %Codex.Thread.Options{}
  |> Codex.Files.attach(attachment)

{:ok, thread} = Codex.start_thread(%Codex.Options{}, thread_opts)
```

Query `Codex.Files.metrics/0` for staging stats and force cleanup with `Codex.Files.force_cleanup/0`.
`Codex.Files.force_cleanup/0`, `Codex.Files.reset!/0`, and `Codex.Files.metrics/0` return
`{:error, reason}` if the registry is unavailable.
Use `Codex.Files.list_staged_result/0` for explicit `{:ok, list} | {:error, reason}` responses;
`Codex.Files.list_staged/0` remains available as a compatibility helper that falls back to `[]` on
startup errors.
Staged files are runtime-scoped; the registry clears the staging directory on startup, so re-stage
attachments after restarts.

### MCP Tool Discovery

The SDK provides MCP client helpers for discovering and invoking tools from MCP servers:

```elixir
# Connect to a stdio MCP server
{:ok, transport} =
  Codex.MCP.Transport.Stdio.start_link(
    command: "npx",
    args: ["-y", "mcp-server"]
  )

{:ok, client} =
  Codex.MCP.Client.initialize(
    {Codex.MCP.Transport.Stdio, transport},
    client: "codex-elixir",
    version: "0.1.0",
    server_name: "my_server"
  )

# List tools with filtering
{:ok, tools, client} = Codex.MCP.Client.list_tools(client,
  allow: ["read_file", "write_file"],
  deny: ["dangerous_tool"]
)

# List tools with qualified names (mcp__server__tool format)
{:ok, tools, client} = Codex.MCP.Client.list_tools(client, qualify?: true)

# Each tool includes:
# - "name" - original tool name
# - "qualified_name" - fully qualified name (e.g., "mcp__my_server__read_file")
# - "server_name" - server identifier
```

`Codex.MCP.Transport.StreamableHTTP` provides JSON-RPC over HTTP with bearer/OAuth
auth support for remote MCP servers.
Transport failures are normalized to `{:error, reason}` tuples.

Tool name qualification now sanitizes each server/tool component to ASCII alphanumerics plus `_`
and `-` before joining them for OpenAI-facing tool names. Original MCP server/tool names are
preserved for actual MCP calls. Names exceeding 64 characters are truncated with a SHA1 hash
suffix for disambiguation:

```elixir
Codex.MCP.Client.qualify_tool_name("server1", "tool_a")
#=> "mcp__server1__tool_a"

Codex.MCP.Client.qualify_tool_name("server.one", "tool.two-three")
#=> "mcp__server_one__tool_two-three"

# Long names are truncated with SHA1 suffix
Codex.MCP.Client.qualify_tool_name("srv", String.duplicate("a", 80))
#=> 64-character string with SHA1 hash suffix
```

Results are cached by default; bypass with `cache?: false`. See `Codex.MCP.Client` for
full documentation and `examples/live_mcp_and_sessions.exs` for a runnable demo.

### Shell Hosted Tool

The SDK provides a fully-featured shell command execution tool with approval integration,
timeout handling, and output truncation:

```elixir
alias Codex.Tools
alias Codex.Tools.ShellTool

# Register with default settings (60s timeout, 10KB max output)
{:ok, _} = Tools.register(ShellTool)

# Execute a simple command
{:ok, result} = Tools.invoke("shell", %{"command" => ["ls", "-la"]}, %{})
# => %{"output" => "...", "exit_code" => 0, "success" => true}

# With working directory
{:ok, result} = Tools.invoke("shell", %{"command" => ["pwd"], "workdir" => "/tmp"}, %{})

# With custom timeout and output limits
{:ok, _} = Tools.register(ShellTool,
  timeout_ms: 30_000,
  max_output_bytes: 5000
)

# With approval callback for sensitive commands
approval = fn cmd, _ctx ->
  if String.contains?(cmd, "rm"), do: {:deny, "rm not allowed"}, else: :ok
end

{:ok, _} = Tools.register(ShellTool, approval: approval)
{:error, {:approval_denied, "rm not allowed"}} =
  Tools.invoke("shell", %{"command" => ["rm", "file"]}, %{})
```

For custom execution, provide a custom executor:

```elixir
custom_executor = fn %{"command" => cmd}, _ctx, _meta ->
  formatted = if is_list(cmd), do: Enum.join(cmd, " "), else: cmd
  {:ok, %{"output" => "custom: #{formatted}", "exit_code" => 0}}
end

{:ok, _} = Tools.register(ShellTool, executor: custom_executor)
```

For string shell scripts, use the `shell_command` tool:

```elixir
alias Codex.Tools.ShellCommandTool

{:ok, _} = Tools.register(ShellCommandTool)
{:ok, result} = Tools.invoke("shell_command", %{"command" => "ls -la", "workdir" => "/tmp"}, %{})
```

Additional hosted tools include `write_stdin` (unified exec sessions via app-server) and
`view_image` (local image attachments gated by `features.view_image_tool` or
`Thread.Options.view_image_tool_enabled`).

See `examples/shell_tool.exs` for a complete demonstration.

### FileSearch Hosted Tool

The SDK provides a local filesystem search tool with glob pattern matching and
content search capabilities:

```elixir
alias Codex.Tools
alias Codex.Tools.FileSearchTool

# Register with default settings
{:ok, _} = Tools.register(FileSearchTool)

# Find all Elixir files recursively
{:ok, result} = Tools.invoke("file_search", %{"pattern" => "lib/**/*.ex"}, %{})
# => %{"count" => 42, "files" => [%{"path" => "lib/foo.ex"}, ...]}

# Search file content with regex
{:ok, result} = Tools.invoke("file_search", %{
  "pattern" => "**/*.ex",
  "content" => "defmodule"
}, %{})
# => %{"count" => 10, "files" => [%{"path" => "lib/foo.ex", "matches" => [...]}]}

# Case-insensitive content search
{:ok, result} = Tools.invoke("file_search", %{
  "pattern" => "**/*.ex",
  "content" => "ERROR",
  "case_sensitive" => false
}, %{})

# Limit results
{:ok, result} = Tools.invoke("file_search", %{
  "pattern" => "**/*",
  "max_results" => 20
}, %{})

# Custom base path
{:ok, _} = Tools.register(FileSearchTool, base_path: "/project")
```

Supported glob patterns:
- `*.ex` - All `.ex` files in base directory
- `**/*.ex` - All `.ex` files recursively
- `lib/**/*.{ex,exs}` - All Elixir files under lib/

See `examples/file_search_tool.exs` for more examples.

### MCP Tool Invocation

Invoke tools on MCP servers with built-in retry logic, approval callbacks, and telemetry:

```elixir
# Basic invocation with default retries (3) and exponential backoff
{:ok, result} = Codex.MCP.Client.call_tool(client, "echo", %{"text" => "hello"})

# Custom retry and timeout settings
{:ok, result} = Codex.MCP.Client.call_tool(client, "fetch", %{"url" => url},
  retries: 5,
  timeout_ms: 30_000,
  backoff: fn attempt -> Process.sleep(attempt * 200) end
)

# With approval callback (for sensitive operations)
{:ok, result} = Codex.MCP.Client.call_tool(client, "write_file", args,
  approval: fn tool, args, context ->
    if authorized?(context.user, tool), do: :ok, else: {:deny, "unauthorized"}
  end,
  context: %{user: current_user}
)
```

Telemetry events are emitted for observability:
- `[:codex, :mcp, :tool_call, :start]` - When a call begins
- `[:codex, :mcp, :tool_call, :success]` - On successful completion
- `[:codex, :mcp, :tool_call, :failure]` - On failure after retries exhausted

### Custom Prompts and Skills

List and expand custom prompts from `$CODEX_HOME/prompts`, and load skills when
`features.skills` is enabled:

```elixir
{:ok, prompts} = Codex.Prompts.list()
{:ok, expanded} = Codex.Prompts.expand(Enum.at(prompts, 0), "FILE=lib/app.ex")

{:ok, conn} = Codex.AppServer.connect(codex_opts)
{:ok, %{"data" => skills}} = Codex.Skills.list(conn, skills_enabled: true)
{:ok, content} = Codex.Skills.load(hd(hd(skills)["skills"]), skills_enabled: true)
```

### Retry Logic

The SDK provides comprehensive retry utilities via `Codex.Retry` for handling transient failures:

```elixir
alias Codex.Retry

# Basic retry with defaults (4 attempts, exponential backoff, 200ms base delay)
{:ok, result} = Retry.with_retry(fn -> make_api_call() end)

# Custom configuration
{:ok, result} = Retry.with_retry(
  fn -> risky_operation() end,
  max_attempts: 5,
  base_delay_ms: 100,
  max_delay_ms: 5_000,
  strategy: :exponential,
  jitter: true,
  on_retry: fn attempt, error ->
    Logger.warning("Retry #{attempt}: #{inspect(error)}")
  end
)

# Different backoff strategies
Retry.with_retry(fun, strategy: :linear)      # 100, 200, 300, 400ms...
Retry.with_retry(fun, strategy: :constant)    # 100, 100, 100, 100ms...
Retry.with_retry(fun, strategy: :exponential) # 100, 200, 400, 800ms... (default)

# Custom backoff function
Retry.with_retry(fun, strategy: fn attempt -> attempt * 50 end)

# Custom retry predicate
Retry.with_retry(fun, retry_if: fn
  :my_transient_error -> true
  _ -> false
end)

# Stream retry (retries entire stream creation on failure)
stream = Retry.with_stream_retry(fn -> make_streaming_request() end)
Enum.each(stream, &process_item/1)
```

Default retryable errors include: `:timeout`, `:econnrefused`, `:econnreset`, `:closed`,
`:nxdomain`, 5xx HTTP errors, 429 rate limits, stream errors, and `Codex.TransportError`
with `retryable?: true`. See `examples/retry_example.exs` for more patterns.

### Telemetry & OTLP Exporting

OpenTelemetry exporting is disabled by default. To ship traces/metrics to a collector, set
`CODEX_OTLP_ENABLE=1` along with the endpoint (and optional headers) before starting your
application:

```bash
export CODEX_OTLP_ENABLE=1
export CODEX_OTLP_ENDPOINT="https://otel.example.com:4318"
export CODEX_OTLP_HEADERS="authorization=Bearer abc123"

mix run examples/basic_usage.exs
```

When the flag is not set (default), the SDK runs without booting the OTLP exporter—avoiding
`tls_certificate_check` warnings on systems without the helper installed.

The Codex CLI (`codex-rs`) has its own OpenTelemetry **log** exporter, configured separately via
`$CODEX_HOME/config.toml` (default `~/.codex/config.toml`) under `[otel]`. This is independent of
the Elixir SDK exporter above.

```toml
[otel]
environment = "staging"
exporter = "otlp-grpc"
log_user_prompt = false

[otel.exporter."otlp-grpc"]
endpoint = "https://otel.example.com:4317"
```

See `codex/docs/config.md` for the full upstream reference. To point Codex at an isolated config
directory from the SDK, pass `env: %{"CODEX_HOME" => "/path/to/codex_home"}` in turn options for
exec transport, or `Codex.AppServer.connect(codex_opts, process_env: %{"CODEX_HOME" => ...})`
for a managed app-server child.

## Architecture

The SDK follows a layered architecture built on OTP principles:

- **`Codex`**: Main entry point for starting and resuming threads
- **`Codex.Thread`**: Manages individual conversation threads and turn execution
- **`Codex.Exec`**: Public exec JSONL API that runs on a session-oriented runtime kit
- **`Codex.Runtime.Exec`**: Session-oriented runtime kit that starts core CLI sessions and projects core events back into `%Codex.Events{}`
- **`Codex.Events`**: Comprehensive event type definitions
- **`Codex.Items`**: Thread item structs (messages, commands, file changes, etc.)
- **`Codex.Options`**: Configuration structs for all levels
- **`Codex.Config.Overrides`**: Config override serialization, nested map flattening, and TOML value validation
- **`CliSubprocessCore.Session`**: Shared common CLI session engine used by the exec JSONL lane
- **`Codex.Runtime.Env`**: Subprocess environment construction (sets `CODEX_INTERNAL_ORIGINATOR_OVERRIDE`)
- **`Codex.Config.BaseURL`**: Base URL resolution with option → env → default precedence
- **`Codex.Config.OptionNormalizers`**: Shared reasoning summary, verbosity, and history validation
- **`Codex.Realtime`**: Bidirectional voice via OpenAI Realtime API (WebSocket)
- **`Codex.Voice`**: Non-realtime STT → Workflow → TTS pipeline
- **`Codex.OutputSchemaFile`**: Helper for managing JSON schema temporary files

### Process Model

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│ Codex.Thread    │  (manages turn state)
└────────┬────────┘
         │
         ▼
┌──────────────────┐
│  Codex.Exec      │  (public exec API)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Codex.Runtime.   │  (runtime kit over core session API)
│ Exec             │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ CliSubprocess    │  (shared session + raw transport core)
│ Core.Session     │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   codex-rs       │  (OpenAI's Codex CLI)
└──────────────────┘
```

## Event Types

The SDK provides structured events for all Codex operations:

### Thread Events

- `ThreadStarted` - New thread initialized with thread_id
- `TurnStarted` - Agent begins processing a prompt
- `TurnCompleted` - Turn finished with usage statistics
- `TurnFailed` - Turn encountered an error

### Session and Control Events

- `SessionConfigured` - Session bootstrap details and initial messages
- `ContextCompacted` - Compaction summary after auto-compaction
- `ThreadRolledBack` - Thread rollback summary
- `RequestUserInput` - Tool-driven user input request
- `ElicitationRequest` - MCP elicitation request
- `UndoStarted` / `UndoCompleted` - Undo lifecycle events
- `EnteredReviewMode` / `ExitedReviewMode` - Review mode lifecycle updates
- `ConfigWarning` - Config warnings emitted by the server

### Item Events

- `ItemStarted` - New item added to thread
- `ItemUpdated` - Item state changed
- `ItemCompleted` - Item reached terminal state

### Item Types

- **`AgentMessage`** - Text or JSON response from the agent
- **`Reasoning`** - Agent's reasoning summary
- **`CommandExecution`** - Shell command execution with output
- **`FileChange`** - File modifications (add, update, delete)
- **`McpToolCall`** - Model Context Protocol tool invocations
- **`WebSearch`** - Web search queries and results
- **`TodoList`** - Agent's running task list
- **`Error`** - Non-fatal error items

## Examples

See the `examples/` directory for comprehensive demonstrations. A quick index:

- **`basic_usage.exs`** - First turn, follow-ups, and result inspection
- **`streaming.exs`** - Real-time turn streaming (progressive and stateful modes)
- **`structured_output.exs`** - JSON schema enforcement and decoding helpers
- **`conversation_and_resume.exs`** - Persisting, resuming, and replaying conversations
- **`concurrency_and_collaboration.exs`** - Multi-turn concurrency patterns
- **`approval_hook_example.exs`** - Custom approval hook wiring and telemetry inspection
- **`sandbox_warnings_and_approval_bypass.exs`** - Normalized sandbox warnings and policy-approved bypass demo
- **`tool_bridging_auto_run.exs`** - Auto-run tool bridging with retries and failure reporting
- **`live_cli_demo.exs`** - Live CLI walkthrough (uses CLI auth)
- **`live_cli_passthrough.exs`** - Direct wrappers for `completion`, `features`, `login status`, and arbitrary raw `codex` commands
- **`live_cli_session.exs`** - PTY-backed root `codex` prompt mode via `Codex.CLI.interactive/2`
- **`live_oauth_login.exs`** - Native OAuth status/login/refresh demo with an isolated temporary `CODEX_HOME`; prints the browser URL before waiting, supports `--browser`, `--device`, and `--no-browser`, and can optionally show memory-mode app-server auth
- **`live_app_server_approvals.exs`** - Command/file/permissions approvals over app-server, using a disposable workspace plus temporary `CODEX_HOME` to exercise under-development approval features without mutating your real settings
- **`live_collaboration_modes.exs`** - `experimentalApi` collaboration mode presets and a live turn that uses the server-advertised preset settings (falling back only when the server omits a field), with an explicit skip when the connected build rejects or omits `collaborationMode/list`
- **`live_subagent_host_controls.exs`** - Live subagent workflow over app-server that enables `features.multi_agent`, exercises the full `Codex.Subagents` helper surface, and drives `spawn_agent`, `send_input`, `resume_agent`, `wait`, and `close_agent`
- **`live_personality.exs`** - Personality overrides (friendly, pragmatic, none)
- **`live_config_overrides.exs`** - Nested config override auto-flattening plus layered `openai_base_url` / `model_providers` parity demo
- **`live_options_config_overrides.exs`** - Options-level global config overrides, precedence, validation, and reserved provider notes
- **`live_thread_management.exs`** - Thread read/fork/rollback/loaded list workflows
- **`live_web_search_modes.exs`** - Web search mode toggles with disabled/live validation and cached-mode event reporting
- **`live_rate_limits.exs`** - Rate limit snapshot reporting from token usage events
- **`live_session_walkthrough.exs`**, **`live_exec_controls.exs`**, **`live_tooling_stream.exs`**, **`live_telemetry_stream.exs`**, **`live_usage_and_compaction.exs`** - Additional live examples that stream, track usage, and show approvals/tooling flows
- **`live_realtime_voice.exs`** - Full realtime voice interaction demo with event handling and CA env notes
- **`realtime_basic.exs`**, **`realtime_tools.exs`**, **`realtime_handoffs.exs`** - Realtime API examples for sessions, tools, handoffs, and CA env notes
- **`voice_pipeline.exs`**, **`voice_multi_turn.exs`**, **`voice_with_agent.exs`** - Voice pipeline examples for STT/TTS workflows with CA env notes

Run examples with:

```bash
mix run examples/basic_usage.exs

# Live CLI example (requires authenticated codex CLI)
mix run examples/live_cli_demo.exs "What is the capital of France?"

# Run all live examples in sequence
./examples/run_all.sh
```


## Documentation

- **API Reference**: Generated docs available via `mix docs` or on [HexDocs](https://hexdocs.pm/codex_sdk)
- **Changelog**: [CHANGELOG.md](CHANGELOG.md) summarises release history
- **Repo Appendix**: `sentience/` contains optional repo folklore documents

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- OpenAI team for the Codex CLI and agent technology
- Elixir community for excellent OTP tooling and libraries
- [Gemini Ex](https://github.com/nshkrdotcom/gemini_ex) for SDK inspiration

## Related Projects

- **[OpenAI Codex](https://github.com/openai/codex)** - The official Codex CLI
- **[Codex TypeScript SDK](https://github.com/openai/codex/tree/main/sdk/typescript)** - Official TypeScript SDK

---

<p align="center">Made with ❤️ and Elixir</p>

## Model Selection Contract

`/home/home/p/g/n/codex_sdk` no longer owns active model-selection policy. The only authoritative resolver/defaulting/validation path is `/home/home/p/g/n/cli_subprocess_core` through `CliSubprocessCore.ModelRegistry.resolve/3`, `CliSubprocessCore.ModelRegistry.validate/2`, and `CliSubprocessCore.ModelRegistry.default_model/2`.

`Codex.Options` and the runtime execution path now consume the resolved payload returned by core and only render transport arguments from that payload. Any older references in this document to local bundled catalogs such as `priv/models.json` should be treated as historical packaging details, not policy authority.
