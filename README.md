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

## Features

- **End-to-End Codex Lifecycle**: Spawn, resume, and manage full Codex threads with rich turn instrumentation.
- **Multi-Transport Support**: Default exec JSONL (`codex exec --json`) plus stateful app-server JSON-RPC over stdio (`codex app-server`) with multi-modal `UserInput` blocks.
- **Upstream Compatibility**: Mirrors Codex CLI flags (profile/OSS/full-auto/color, config overrides, review/resume) and handles app-server protocol drift (e.g. MCP list method rename fallbacks).
- **Streaming & Structured Output**: Real-time events plus reasoning summary/content preservation and typed app-server deltas.
- **File & Attachment Pipeline**: Secure temp file registry and change events.
- **Approval Hooks & Sandbox Policies**: Dynamic or static approval flows with registry-backed persistence.
- **Tooling & MCP Integration**: Built-in registry for Codex tool manifests and MCP client helpers.
- **Observability-Ready**: Telemetry spans, OTLP exporters gated by environment flags, and usage stats.

## Installation

Add `codex_sdk` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:codex_sdk, "~> 0.5.0"}
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

Alternatively, set `CODEX_API_KEY` before starting your BEAM node. The SDK prefers `CODEX_API_KEY`,
then `auth.json` `OPENAI_API_KEY`, and otherwise falls back to your CLI login tokens stored under
`CODEX_HOME` (default `~/.codex/auth.json`, with legacy credential file support). If neither an API
key nor an authenticated CLI session is available, Codex executions will fail with upstream
authentication errors—the SDK does not perform additional login flows.

If `cli_auth_credentials_store = "keyring"` is set in config and keyring support is unavailable,
the SDK logs a warning and skips file-based tokens (remote model fetch falls back to bundled models).
When `cli_auth_credentials_store = "auto"` and keyring is unavailable, the SDK falls back to file-based auth.

When an API key is supplied, the SDK forwards it as both `CODEX_API_KEY` and `OPENAI_API_KEY`
to the codex subprocess to align with provider expectations.
```

Model defaults are auth-aware:
- ChatGPT login: `gpt-5.2-codex` (prefers `codex-auto-balanced` when remote models are enabled and available)
- API key auth: `gpt-5.1-codex-max`

Remote models are gated behind `features.remote_models = true` in the effective Codex config (system `/etc/codex/config.toml`, user `$CODEX_HOME/config.toml`, and `.codex/config.toml` layers between `cwd` and the project root; root markers default to `.git` and are configurable via `project_root_markers`). When enabled, the SDK merges the remote `/models` list (or bundled `models.json`) with local presets and keeps `gpt-5.2-codex` available.

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

The SDK defaults to exec JSONL for backwards compatibility. To use the stateful app-server transport:

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

Multi-modal input is supported on app-server transport:

```elixir
input = [
  %{type: :text, text: "Explain this screenshot"},
  %{type: :local_image, path: "/tmp/screenshot.png"}
]

{:ok, result} = Codex.Thread.run(thread, input)
```

Note: exec JSONL transport still accepts text input only; list inputs return `{:error, {:unsupported_input, :exec}}`.

App-server-only APIs include:

- `Codex.AppServer.thread_list/2`, `thread_archive/2`
- `Codex.AppServer.model_list/2`, `config_read/2`, `config_write/4`, `config_batch_write/3`
- `Codex.AppServer.turn_interrupt/3`
- `Codex.AppServer.fuzzy_file_search/3` (legacy v1 helper used by `@` file search)
- `Codex.AppServer.command_write_stdin/4` (interactive command stdin)
- `Codex.AppServer.Account.*` and `Codex.AppServer.Mcp.*` endpoints
- Approvals via `Codex.AppServer.subscribe/2` + `Codex.AppServer.respond/3`

Note: app-server v2 does not support sending `UserInput::Skill` directly; use `skills/list` and inject skill content as text if you need emulation.
Legacy app-server v1 conversation flows are available via `Codex.AppServer.V1`.

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
```


### Resuming Threads

Threads are persisted in `~/.codex/sessions`. Resume previous conversations:

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

The CLI writes session logs under `~/.codex/sessions`. The SDK can list them and
apply or undo diffs locally:

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
    history: %{persistence: "local", max_bytes: 1_000_000}
  )

# Thread-level options
{:ok, thread_options} =
  Codex.Thread.Options.new(
    metadata: %{project: "codex_sdk"},
    labels: %{environment: "dev"},
    auto_run: true,
    sandbox: :strict,
    approval_timeout_ms: 45_000
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
turn_options = %{output_schema: my_json_schema}

{:ok, result} = Codex.Thread.run(thread, "Your prompt", turn_options)

# Exec controls: inject env, set cancellation token/timeout/idle timeout (forwarded to codex exec)
turn_options = %{
  env: %{"CODEX_DEMO_ENV" => "from-sdk"},
  cancellation_token: "demo-token-123",
  timeout_ms: 120_000,
  stream_idle_timeout_ms: 300_000
}

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

Tool name qualification follows the OpenAI convention (`^[a-zA-Z0-9_-]+$`). Names exceeding
64 characters are truncated with a SHA1 hash suffix for disambiguation:

```elixir
Codex.MCP.Client.qualify_tool_name("server1", "tool_a")
#=> "mcp__server1__tool_a"

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
directory from the SDK, pass `env: %{"CODEX_HOME" => "/path/to/codex_home"}` in turn options.

## Architecture

The SDK follows a layered architecture built on OTP principles:

- **`Codex`**: Main entry point for starting and resuming threads
- **`Codex.Thread`**: Manages individual conversation threads and turn execution
- **`Codex.Exec`**: GenServer that manages the `codex-rs` OS process via Port
- **`Codex.Events`**: Comprehensive event type definitions
- **`Codex.Items`**: Thread item structs (messages, commands, file changes, etc.)
- **`Codex.Options`**: Configuration structs for all levels
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
│  Codex.Exec      │  (GenServer - manages codex-rs process)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   Port (stdin/   │  (IPC with codex-rs via JSONL)
│    stdout)       │
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
- **`live_session_walkthrough.exs`**, **`live_exec_controls.exs`**, **`live_tooling_stream.exs`**, **`live_telemetry_stream.exs`**, **`live_usage_and_compaction.exs`** - Additional live examples that stream, track usage, and show approvals/tooling flows

Run examples with:

```bash
mix run examples/basic_usage.exs

# Live CLI example (requires authenticated codex CLI)
mix run examples/live_cli_demo.exs "What is the capital of France?"

# Run all live examples in sequence
./examples/run_all.sh
```


## Documentation

HexDocs hosts the prerelease documentation set referenced in `mix.exs`:

- **Guides**: [docs/01.md](docs/01.md), [docs/02-architecture.md](docs/02-architecture.md), and [docs/09-app-server-transport.md](docs/09-app-server-transport.md)
- **Reference**: [docs/05-api-reference.md](docs/05-api-reference.md) and [docs/06-examples.md](docs/06-examples.md)
- **Changelog**: [CHANGELOG.md](CHANGELOG.md) summarises release history

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
