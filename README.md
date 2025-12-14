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

An idiomatic Elixir SDK for embedding OpenAI's Codex agent in your workflows and applications. This SDK wraps the `codex-rs` executable, providing a complete, production-ready interface with streaming support, comprehensive event handling, and robust testing utilities.

## Features

- **End-to-End Codex Lifecycle**: Spawn, resume, and manage full Codex threads with rich turn instrumentation.
- **Streaming & Structured Output**: Real-time events plus first-class JSON schema handling for deterministic parsing.
- **File & Attachment Pipeline**: Secure temp file registry, change events, and fixture harvesting helpers.
- **Approval Hooks & Sandbox Policies**: Dynamic or static approval flows with registry-backed persistence.
- **Tooling & MCP Integration**: Built-in registry for Codex tool manifests and MCP client helpers.
- **Observability-Ready**: Telemetry spans, OTLP exporters gated by environment flags, and usage stats.
- **Deterministic Testing**: Supertester-powered OTP test suite, contract fixtures, and live CLI validation.
- **Developer Experience**: Mix tasks for parity verification, rich docs, runnable examples, and CI-friendly checks.

## Installation

Add `codex_sdk` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:codex_sdk, "~> 0.2.5"}
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

Alternatively, set `CODEX_API_KEY` (or `OPENAI_API_KEY`) before starting your BEAM node. The SDK
automatically falls back to your CLI login if no API key is set, reading tokens from `CODEX_HOME`
(default `~/.codex/auth.json`) or legacy credential files. If neither an API key nor an authenticated
CLI session is available, Codex executions will fail with upstream authentication errors—the SDK
does not perform additional login flows.
```

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

# Live model defaults + compaction/usage handling (requires CODEX_API_KEY)
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

### Configuration Options

```elixir
# Codex-level options
{:ok, codex_options} =
  Codex.Options.new(
    api_key: System.fetch_env!("CODEX_API_KEY"),
    codex_path_override: "/custom/path/to/codex",
    telemetry_prefix: [:codex, :sdk],
    model: "o1"
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

# Exec controls: inject env, set cancellation token/timeout (forwarded to codex exec)
turn_options = %{
  env: %{"CODEX_DEMO_ENV" => "from-sdk"},
  cancellation_token: "demo-token-123",
  timeout_ms: 120_000
}

{:ok, stream} =
  Codex.Thread.run_streamed(thread, "List three files and echo $CODEX_DEMO_ENV", turn_options)
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

Query `Codex.Files.metrics/0` for staging stats, force cleanup with `Codex.Files.force_cleanup/0`,
and leverage `scripts/harvest_python_fixtures.py` to import parity fixtures from the Python SDK.

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
`tls_certificate_check` warnings on systems without the helper installed. See
`docs/observability-runbook.md` for advanced setup instructions.

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

## Testing

The SDK uses [Supertester](https://hex.pm/packages/supertester) for robust, deterministic OTP testing:

### Test & Quality Commands

```bash
mix test
mix test --cover
# Only the live-tagged tests (hits real codex CLI)
CODEX_TEST_LIVE=true mix test --only live --include live
# Full test suite + live-tagged tests
CODEX_TEST_LIVE=true mix test --include live
mix codex.verify
mix codex.verify --dry-run
mix codex.parity
MIX_ENV=test mix credo --strict
mix format --check-formatted
MIX_ENV=dev mix dialyzer
```

`mix codex.verify` orchestrates compile/format/test checks (pass `--dry-run` to preview), while
`mix codex.parity` reports harvested Python fixtures—refresh them via
`scripts/harvest_python_fixtures.py`.

### Test Features

- **Zero `Process.sleep`**: All tests use proper OTP synchronization
- **Fully Async**: All tests run with `async: true`
- **Mock Support**: Tests work with mocked `codex-rs` output
- **Live Testing**: Optional `:live` ExUnit suite hitting real CLI (`CODEX_TEST_LIVE=true mix test --only live --include live`)
- **Chaos Engineering**: Resilience testing for process crashes
- **Performance Assertions**: SLA verification and leak detection
- **Parity Fixtures**: Python fixture harvesting via `scripts/harvest_python_fixtures.py`

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

HexDocs hosts the complete documentation set referenced in `mix.exs`:

- **Guides**: [docs/01.md](docs/01.md) (intro), [docs/02-architecture.md](docs/02-architecture.md), and [docs/03-implementation-plan.md](docs/03-implementation-plan.md)
- **Testing & Quality**: [docs/04-testing-strategy.md](docs/04-testing-strategy.md), [docs/08-tdd-implementation-guide.md](docs/08-tdd-implementation-guide.md), and [docs/observability-runbook.md](docs/observability-runbook.md)
- **API & Examples**: [docs/05-api-reference.md](docs/05-api-reference.md), [docs/06-examples.md](docs/06-examples.md), and [docs/fixtures.md](docs/fixtures.md)
- **Python Parity**: [docs/07-python-parity-plan.md](docs/07-python-parity-plan.md) and [docs/python-parity-checklist.md](docs/python-parity-checklist.md)
- **Design Dossiers**: All files under `docs/design/` cover attachments, error handling, telemetry, sandbox approvals, and more
- **Phase Notes**: Iteration notes and prompts under `docs/20251018/` track ongoing parity milestones
- **Changelog**: [CHANGELOG.md](CHANGELOG.md) summarises release history

## Project Status

**Current Version**: 0.2.5 (Quiet tests + tools registry race fix)

### v0.2.5 Highlights

- Tests run quietly by default (log capture + console logger level tuned for test)
- Fixed a race in tool registry resets that could intermittently fail in async tests

### v0.2.4 Highlights

- Examples now default to `gpt-5.1-codex-mini` and `run_all.sh` continues past failures with a summary
- Fixed `codex exec --output-schema` example schema and improved example error messages
- Exec env handling hardened so CLI-login auth works reliably when env overrides are absent

### v0.2.3 Highlights

- Forwarded Codex CLI execution knobs (sandbox/cd/add-dir/skip-git, web search, approval policy, network access) and `OPENAI_BASE_URL`
- Added optional `clear_env?` per-turn switch to clear inherited environment for codex subprocesses
- Updated port gap analysis docs to match the actual wired integration surface

### v0.2.2 Highlights

- Added `auto_previous_response_id` to `Codex.RunConfig` plus `last_response_id` on turn results (forward-compatible with future `response_id` support)
- Clarified OTEL export layers: Elixir-side OTLP exporter vs codex-rs `[otel]` config.toml exporter
- Fixed tool registration to load metadata modules before resolving tool names

### v0.2.1 Highlights

- Auth fallback to Codex CLI login when `CODEX_API_KEY` is absent; live two-turn walkthrough example added
- Resumption now uses `codex exec … resume <thread_id>`; `/new` resets threads and early-exit sessions are not persisted
- App-server event coverage for token usage, turn diffs, and compaction notices; streaming example surfaces live usage/diff updates alongside items

### v0.2.0 Highlights

- Core thread lifecycle with streaming, resumption, and structured output decoding
- Comprehensive event and item structs mirroring Codex's JSON protocol
- GenServer-based `Codex.Exec` process supervision with resilient Port management
- Approval policies/hooks, tool registry, and sandbox-aware error handling
- File staging registry, parity fixtures, and runnable examples for every workflow
- Observability instrumentation with OTLP export gating and approval telemetry
- Mix tasks (`mix codex.verify`, `mix codex.parity`) plus Supertester-powered contract suite

### What's Next

- Python parity tracking and contract validation (see [docs/07-python-parity-plan.md](docs/07-python-parity-plan.md))
- Phase notes for additional tooling integrations under `docs/20251018/`
- Feedback-driven enhancements surfaced via GitHub Issues

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`mix test`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- OpenAI team for the Codex CLI and agent technology
- Elixir community for excellent OTP tooling and libraries
- [Gemini Ex](https://github.com/nshkrdotcom/gemini_ex) for SDK inspiration
- [Supertester](https://github.com/nshkrdotcom/supertester) for robust testing utilities

## Related Projects

- **[OpenAI Codex](https://github.com/openai/codex)** - The official Codex CLI
- **[Codex TypeScript SDK](https://github.com/openai/codex/tree/main/sdk/typescript)** - Official TypeScript SDK
- **[Gemini Ex](https://github.com/nshkrdotcom/gemini_ex)** - Elixir client for Google's Gemini AI

---

<p align="center">Made with ❤️ and Elixir</p>
