# API Reference

Complete API documentation for all modules in the Elixir Codex SDK.

## Module Overview

| Module | Purpose |
|--------|---------|
| `Codex` | Main entry point for starting and resuming threads |
| `Codex.Thread` | Manages conversation threads and turn execution |
| `Codex.Transport` | Transport behaviour for turn execution |
| `Codex.AppServer` | Stateful app-server JSON-RPC connection + v2 request APIs |
| `Codex.AppServer.V1` | Legacy app-server compatibility helpers for v1 conversation APIs |
| `Codex.Agent` | Reusable agent definition (instructions, tools, hooks) |
| `Codex.RunConfig` | Per-run overrides (max_turns, history behavior, hooks) |
| `Codex.AgentRunner` | Multi-turn runner coordinating threads and tool invocations |
| `Codex.Exec` | Exec JSONL subprocess wrapper (`codex exec --json`) |
| `Codex.Sessions` | Session file utilities plus apply/undo helpers |
| `Codex.Events` | Event type definitions |
| `Codex.Items` | Thread item type definitions |
| `Codex.Options` | Configuration structs |
| `Codex.Protocol.*` | Protocol enums and payload helpers (collaboration modes, request_user_input, rate limits) |
| `Codex.OutputSchemaFile` | JSON schema file management |

---

## Transports

The SDK supports both upstream external transports:

- **Exec JSONL (default)**: `codex exec --json`
- **App-server JSON-RPC (optional)**: `codex app-server` (newline-delimited JSON over stdio)

Select transport per-thread via `Codex.Thread.Options.transport`:

```elixir
{:ok, conn} = Codex.AppServer.connect(codex_opts)
{:ok, thread} = Codex.start_thread(codex_opts, %{transport: {:app_server, conn}})
```

For legacy v1 app-server deployments, use `Codex.AppServer.V1` request helpers for
conversation APIs.

## Codex

Main entry point for the Codex SDK. Use this module to create new threads or resume existing ones.

### Functions

#### `start_thread/2`

Creates a new conversation thread with the Codex agent.

**Signature**:
```elixir
@spec start_thread(Codex.Options.t(), Codex.Thread.Options.t()) ::
  {:ok, Codex.Thread.t()} | {:error, term()}
```

**Parameters**:
- `codex_opts` (optional): Global Codex options. Defaults to `%Codex.Options{}`
- `thread_opts` (optional): Thread-specific options. Defaults to `%Codex.Thread.Options{}`

**Returns**:
- `{:ok, thread}`: New thread struct ready for turn execution
- `{:error, reason}`: Configuration error

**Examples**:
```elixir
# Start with defaults
{:ok, thread} = Codex.start_thread()

# Start with custom API key
codex_opts = %Codex.Options{api_key: "sk-..."}
{:ok, thread} = Codex.start_thread(codex_opts)

# Start with thread options
thread_opts = %Codex.Thread.Options{
  sandbox: :read_only,
  working_directory: "/path/to/project"
}
{:ok, thread} = Codex.start_thread(%Codex.Options{}, thread_opts)
```

---

#### `resume_thread/3`

Resumes an existing conversation thread from its persisted session.

**Signature**:
```elixir
@spec resume_thread(String.t() | :last, Codex.Options.t(), Codex.Thread.Options.t()) ::
  {:ok, Codex.Thread.t()} | {:error, term()}
```

**Parameters**:
- `thread_id`: ID of the thread to resume (from `~/.codex/sessions`) or `:last` for the most recent session
- `codex_opts` (optional): Global Codex options
- `thread_opts` (optional): Thread-specific options

**Returns**:
- `{:ok, thread}`: Thread struct with existing thread_id
- `{:error, reason}`: Thread not found or configuration error

**Examples**:
```elixir
# Resume with thread ID
{:ok, thread} = Codex.resume_thread("thread_abc123")

# Resume the most recent session
{:ok, thread} = Codex.resume_thread(:last)

# Resume with custom options
codex_opts = %Codex.Options{base_url: "https://custom.api"}
{:ok, thread} = Codex.resume_thread("thread_abc123", codex_opts)
```

**Notes**:
- Threads are persisted in `~/.codex/sessions` by codex-rs
- Thread history and context are automatically restored
- The thread_id is available after the first turn completes

---

## Agents and Runner

`Codex.Thread.run/3` delegates to a multi-turn runner that can be configured with reusable agents and per-run settings.

### `Codex.Agent`

Represents a reusable agent definition with fields for `instructions` or `prompt`, optional `handoffs`, `tools`, guardrail lists, hooks, and optional `model` or `model_settings` overrides. New fields mirror the agent runner ADRs:

- `handoff_description` and `handoffs` (lists of downstream `Codex.Agent` or `Codex.Handoff.wrap/2` structs) describe delegation targets
- `tool_use_behavior` controls when tool outputs end a run (`:run_llm_again` default, `:stop_on_first_tool`, `%{stop_at_tool_names: [...]}`, or a callback)
- `reset_tool_choice` resets tool choice hints after a tool call (default: true)

Build via `Codex.Agent.new/1` with maps, keyword lists, or an existing struct.

`Codex.Handoff.wrap/2` turns an agent into a handoff tool with optional input filters and history nesting controls; `Codex.AgentRunner.get_handoffs/2` filters enabled handoffs using the provided context. Guardrails can be created with `Codex.Guardrail.new/1` and `Codex.ToolGuardrail.new/1`; when supplied on the agent/run config they run before turns, after final outputs, and around tool calls, raising `Codex.GuardrailError` on rejections/tripwires.

### `Codex.RunConfig`

Per-run overrides built with `Codex.RunConfig.new/1`. Defaults: `max_turns: 10`, `nest_handoff_history: true`, `auto_previous_response_id: false`, optional `model` override, tracing metadata (`workflow`, `group`, `trace_id`, `trace_include_sensitive_data`, `tracing_disabled`), guardrail placeholders, and a `call_model_input_filter` hook slot (not yet wired). Validation ensures `max_turns` is a positive integer. The optional `file_search` field seeds hosted file search calls with `vector_store_ids`, `filters`, `ranking_options`, and `include_search_results` (run-level values override thread defaults). `conversation_id` and `previous_response_id` are recorded on thread metadata and used for future chaining; when `auto_previous_response_id` is enabled and a backend emits `response_id`, the runner updates `previous_response_id` automatically (currently `nil` on `codex exec --json`).

### `Codex.AgentRunner`

Low-level entry point for multi-turn execution. Accepts a thread, input, and options that may include `:agent`, `:run_config`, `:max_turns`, and per-turn flags (e.g., `output_schema`). `Codex.Thread.run/3` and `Codex.Thread.run_streamed/3` are facades over this runner.

Example:
```elixir
{:ok, thread} = Codex.start_thread()
{:ok, result} =
  Codex.AgentRunner.run(thread, "Summarize docs",
    run_config: %{max_turns: 5},
    agent: %{instructions: "Be concise"}
  )
```

---

## Codex.Thread

Manages individual conversation threads and turn execution. Threads maintain state across multiple turns.

### Type: `t()`

```elixir
@type t() :: %Codex.Thread{
  thread_id: String.t() | nil,
  codex_opts: Codex.Options.t(),
  thread_opts: Codex.Thread.Options.t()
}
```

**Fields**:
- `thread_id`: Unique thread identifier (nil until first turn completes)
- `codex_opts`: Global Codex configuration
- `thread_opts`: Thread-specific configuration

### Functions

#### `run/3`

Executes a multi-turn run and returns the complete result (blocking mode). Internally uses the agent runner and will follow continuation tokens until completion or `max_turns` is reached.

**Signature**:
```elixir
@spec run(t(), String.t() | [map()], map() | keyword()) ::
  {:ok, Codex.Turn.Result.t()} | {:error, term()}
```

**Parameters**:
- `thread`: Thread struct from `Codex.start_thread/2` or `Codex.resume_thread/3`
- `input`: Prompt text or app-server `UserInput` blocks (text/image/localImage)
- `opts` (optional): Per-turn options (e.g., `output_schema`, `env`, `attachments`) plus runner settings (`:agent`, `:run_config`, or `:max_turns`)

**Returns**:
- `{:ok, result}`: Complete turn result with items, response, and usage
- `{:error, {:max_turns_exceeded, max_turns, context}}`: Run exceeded the allowed turn count
- `{:error, {:turn_failed, error}}`: Agent encountered an error
- `{:error, reason}`: Other error (process, configuration, etc.)

**Examples**:
```elixir
# Basic usage
{:ok, thread} = Codex.start_thread()
{:ok, result} = Codex.Thread.run(thread, "Explain GenServers")

IO.puts(result.final_response)
# => "GenServers are..."

# With structured output
schema = %{
  "type" => "object",
  "properties" => %{
    "summary" => %{"type" => "string"},
    "key_points" => %{
      "type" => "array",
      "items" => %{"type" => "string"}
    }
  }
}

turn_opts = %{output_schema: schema}
{:ok, result} = Codex.Thread.run(thread, "Summarize GenServers", turn_opts)

{:ok, data} = Jason.decode(result.final_response)
IO.inspect(data["key_points"])

# Continue conversation
{:ok, result2} = Codex.Thread.run(thread, "Give me an example")

# Override turn limit
{:ok, result} = Codex.Thread.run(thread, "Try multiple steps", %{max_turns: 5})
```

**Behavior**:
- Blocks until the run completes or `max_turns` is hit (default: 10)
- Accumulates events and usage across turns
- Invokes registered tools automatically when codex requests them
- Thread struct is updated with thread_id after first turn; subsequent calls reuse it for context
- App-server transport accepts `UserInput` block lists; exec JSONL requires text input

---

#### `run_streamed/3`

Executes a turn and returns a streaming result wrapper. Semantic events are exposed via
`Codex.RunResultStreaming.events/1` and raw Codex events via `raw_events/1`.

**Signature**:
```elixir
@spec run_streamed(t(), String.t() | [map()], map() | keyword()) ::
  {:ok, Codex.RunResultStreaming.t()} | {:error, term()}
```

**Parameters**:
- `thread`: Thread struct
- `input`: Prompt text or app-server `UserInput` blocks
- `opts` (optional): Turn-specific options plus optional runner settings (`:agent`, `:run_config`)

**Returns**:
- `{:ok, result}`: `Codex.RunResultStreaming` with semantic and raw event streams plus cancellation controls
- `{:error, reason}`: Configuration or process error

**Examples**:
```elixir
# Basic streaming
{:ok, thread} = Codex.start_thread()
{:ok, result} = Codex.Thread.run_streamed(thread, "Analyze this codebase")

for event <- Codex.RunResultStreaming.raw_events(result) do
  case event do
    %Codex.Events.ItemStarted{item: item} ->
      IO.puts("Started: #{item.type}")

    %Codex.Events.ItemCompleted{item: %{type: :agent_message, text: text}} ->
      IO.puts("Response: #{text}")

    %Codex.Events.ItemCompleted{item: %{type: :command_execution} = cmd} ->
      IO.puts("Command: #{cmd.command} (exit: #{cmd.exit_code})")

    %Codex.Events.TurnCompleted{usage: usage} ->
      IO.puts("Tokens: #{usage.input_tokens + usage.output_tokens}")

    _ ->
      :ok
  end
end

# Process first N events
{:ok, stream_result} = Codex.Thread.run_streamed(thread, "Generate 100 files")
first_10 = stream_result |> Codex.RunResultStreaming.raw_events() |> Enum.take(10)

# Filter specific events
{:ok, stream_result} = Codex.Thread.run_streamed(thread, "Fix bugs")
commands =
  stream_result
  |> Codex.RunResultStreaming.raw_events()
  |> Stream.filter(fn
    %Codex.Events.ItemCompleted{item: %{type: :command_execution}} -> true
    _ -> false
  end)
  |> Enum.to_list()
```

**Behavior**:
- Returns immediately with stream
- Events yielded as they arrive from codex-rs
- Stream is lazy (events fetched on demand)
- Automatic cleanup when stream completes or is halted
- Thread struct must be updated with thread_id from `ThreadStarted` event

---

#### `run_auto/3`

Executes an auto-run loop, retrying turn execution while the Codex engine exposes a continuation token.

**Signature**:
```elixir
@spec run_auto(t(), String.t(), keyword()) ::
  {:ok, Codex.Turn.Result.t()} | {:error, term()}
```

**Parameters**:
- `thread`: Thread struct from `Codex.start_thread/2`
- `input`: Prompt or instruction for the agent
- `opts` (keyword):
  - `:max_attempts` (default: `3`) — maximum auto-run attempts
  - `:backoff` (default: exponential backoff) — unary function invoked before each retry
  - `:turn_opts` (default: `%{}`) — forwarded to each `run/3` attempt

**Returns**:
- `{:ok, result}`: Completed turn with aggregated events, usage, and `attempts` count
- `{:error, {:max_attempts_reached, max, context}}`: Continuation persisted after exhausting attempts
- `{:error, reason}`: Underlying execution failure

**Examples**:
```elixir
{:ok, thread} = Codex.start_thread()

# Automatically resolve continuation tokens until completion
{:ok, result} = Codex.Thread.run_auto(thread, "Generate release notes")

result.attempts
# => 2

result.thread.usage
# => %{"input_tokens" => 42, "output_tokens" => 35, ...}

# Custom retry policy (no sleep) with explicit max attempts
opts = [max_attempts: 5, backoff: fn _ -> :ok end]
case Codex.Thread.run_auto(thread, "Execute plan", opts) do
  {:ok, result} -> IO.inspect(result.final_response)
  {:error, {:max_attempts_reached, _, %{continuation: token}}} ->
    Logger.warn("manual follow-up required: #{token}")
end
```

**Behavior**:
- Invokes `run/3` sequentially while continuation tokens are present
- Applies backoff between attempts; default uses exponential sleep
- Aggregates usage metrics and events across attempts
- Returns updated thread with continuation token cleared on success

---

## Codex.Exec

GenServer that manages the `codex-rs` process lifecycle. This module is typically used internally by `Codex.Thread`, but can be used directly for advanced use cases.

Additional exec helpers:

- `Codex.Exec.review/2` and `Codex.Exec.review_stream/2` run `codex exec review` with a review target (uncommitted, base branch, commit, or custom prompt).
- Thread/turn options like `profile`, `oss`, `local_provider`, `full_auto`, `dangerously_bypass_approvals_and_sandbox`, `output_last_message`, and `color` are forwarded as CLI flags.
- `config_overrides` maps to `-c key=value` overrides (TOML parsing on the codex side), with runtime validation for TOML-compatible values.
- `Codex.resume_thread(:last)` maps to `codex exec resume --last`.

Example:

```elixir
{:ok, result} =
  Codex.Exec.review({:base_branch, "main"}, %{
    codex_opts: codex_opts,
    timeout_ms: 300_000
  })
```

---

## Codex.Sessions

Utilities for inspecting CLI session files and replaying Codex diffs locally.

### `list_sessions/1`

Lists session entries from `~/.codex/sessions` (or a custom `:sessions_dir`). Each entry includes
`metadata` for unrecognized fields so new upstream metadata is preserved.

```elixir
{:ok, sessions} = Codex.Sessions.list_sessions()
```

### `apply/2`

Applies a unified diff string or a list of file change items using `git apply`.

```elixir
{:ok, result} = Codex.Sessions.apply(diff, cwd: "/path/to/repo")
```

Options:
- `:cwd` — repository root (defaults to current directory)
- `:timeout_ms` — command timeout (default: 60s)
- `:preflight` / `:dry_run` — validate without applying changes

### `undo/2`

Restores a ghost snapshot using a `%Codex.Items.GhostSnapshot{}` or raw ghost commit map:

```elixir
{:ok, result} = Codex.Sessions.undo(ghost_snapshot, cwd: "/path/to/repo")
```

The helper restores tracked files and removes untracked files created after the snapshot,
while preserving preexisting untracked paths recorded in the snapshot metadata.

---

## Codex.Tools

The tool registry supports a Python-style, decorator-inspired tooling API. Tools can be registered dynamically and invoked automatically during auto-run cycles when the agent requests an external capability.

### `register/2`

Registers a tool module that implements `Codex.Tool`.

```elixir
@spec register(module(), keyword()) :: {:ok, Codex.Tools.Handle.t()} | {:error, term()}
```

- `:name` — identifier used by Codex events (defaults to module metadata or underscored module name)
- `:description`, `:schema` — optional metadata merged with tool-provided metadata

### `invoke/3`

Invokes a registered tool with decoded arguments and contextual data.

```elixir
@spec invoke(String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
```

Context includes the current thread struct, event metadata, and any custom entries stored under `Thread.Options.metadata` (mirroring Python's tool context).

### `deregister/1`

Removes a registered tool.

### `metrics/0`

Returns an in-memory snapshot of invocation counters per tool.

```elixir
@spec metrics() :: %{optional(String.t()) => %{success: non_neg_integer(), failure: non_neg_integer(), last_latency_ms: non_neg_integer(), total_latency_ms: non_neg_integer(), last_error: term() | nil}}
```

Useful for lightweight observability without relying on external telemetry backends.

### `reset_metrics/0`

Clears all accumulated metrics.

```elixir
@spec reset_metrics() :: :ok
```

Clears accumulated metrics for fresh tracking.

### Telemetry

Every invocation emits `:telemetry` events using the following namespaces:

- `[:codex, :tool, :start]` — dispatched prior to executing a tool, with metadata including `:tool`, `:call_id`, `:attempt`, and `:retry?`
- `[:codex, :tool, :success]` — emitted on success with the same metadata plus the returned `:output`; measurements include `:duration` in native units
- `[:codex, :tool, :failure]` — emitted on failures with the same measurements and an `:error` entry describing the failure

### Codex.FunctionTool

Function-backed tools can be defined with `use Codex.FunctionTool`, which generates a JSON schema from the supplied parameter definitions and handles enablement/error hooks:

```elixir
defmodule Math.Add do
  use Codex.FunctionTool,
    name: "add_numbers",
    description: "Adds two numbers",
    parameters: %{left: :number, right: :number},
    enabled?: fn _ctx -> true end,
    on_error: fn reason, _ctx -> {:ok, %{message: inspect(reason)}} end,
    handler: fn %{"left" => left, "right" => right}, _ctx ->
      {:ok, %{"sum" => left + right}}
    end
end
```

Schemas are strict by default (`"additionalProperties": false`) and can be overridden via the `:schema` option. `:enabled?` gates invocation, while `:on_error` can turn failures into usable outputs.

### Codex.ToolOutput

Tools may return structured outputs using `%Codex.ToolOutput.Text{}`, `%Codex.ToolOutput.Image{}`, or `%Codex.ToolOutput.FileContent{}` (or the `text/1`, `image/1`, and `file/1` helpers). Outputs are normalized to codex-friendly input items (`input_text`, `input_image`, `input_file`) by the runner before being forwarded back to the model. File payloads support `file_id`, `file_url`, inline `data`, `filename`, and `mime_type`; image payloads support `url`/`file_id` plus `detail`. Lists of outputs are flattened and deduplicated to avoid resending the same file/image inputs across continuations. Passing a `%Codex.Files.Attachment{}` automatically produces an `input_file` item with the staged file encoded as base64 alongside the attachment checksum id.

### Hosted tools

Hosted capabilities mirror the Python SDK wrappers and are exposed as tool modules:

- `Codex.Tools.ShellTool` — runs argv-style shell commands (`command: ["bash", "-lc", "..."]`), supports `workdir`, `timeout_ms`, `max_output_bytes`, and optional `:approval` hooks (legacy string commands are still accepted)
- `Codex.Tools.ShellCommandTool` — runs string shell scripts (`command: "ls -la"`), supports `login`, `workdir`, and `timeout_ms` under the `shell_command` tool name
- `Codex.Tools.WriteStdinTool` — writes to unified exec sessions (app-server transport only), requires `session_id`
- `Codex.Tools.ApplyPatchTool` — applies `*** Begin Patch` edits via `input` and preserves unified diff fallback via `patch` (add/delete/update/move + dry-run)
- `Codex.Tools.ViewImageTool` — attaches local images as `input_image` outputs, gated by `features.view_image_tool` or `Thread.Options.view_image_tool_enabled`
- `Codex.Tools.ComputerTool` — performs computer actions guarded by a `:safety` callback and optional approval hook, delegated to an `:executor`
- `Codex.Tools.FileSearchTool` — searches local files by glob pattern and content, with case-insensitive and max results options
- `Codex.Tools.VectorStoreSearchTool` / `Codex.Tools.WebSearchTool` — dispatch search calls through a `:searcher` callback while carrying configured filters/vector store IDs (plus ranking options and `include_search_results` pulled from thread/run `file_search` config); `web_search` requests are gated by `features.web_search_request`
- `Codex.Tools.ImageGenerationTool` / `Codex.Tools.CodeInterpreterTool` — call provided `:generator` / `:runner` callbacks

Defaults for hosted file search can be set on `Thread.Options.file_search` or `RunConfig.file_search`; request arguments supplied by the model still win.

SDK-only extensions (not present in the upstream codex CLI): `ComputerTool`, `VectorStoreSearchTool`, `ImageGenerationTool`, and `CodeInterpreterTool`.

Register them like any other tool, passing callbacks in registration metadata:

```elixir
{:ok, _} =
  Codex.Tools.register(Codex.Tools.ShellTool,
    executor: &MyShell.exec/3,
    timeout_ms: 1_000
  )
```

---

## Codex.Files

Staging and attachment helpers that keep file workflows deterministic.

- `stage/2` — copies a source file into the staging directory, returning `%Codex.Files.Attachment{}` with checksum, size, and persistence metadata.
- `attach/2` — appends a staged attachment to `Codex.Thread.Options`, deduplicating by checksum.
- `list_staged_result/0` — explicit `{:ok, [attachment]} | {:error, reason}` listing API.
- `list_staged/0` / `cleanup!/0` / `reset!/0` — compatibility helpers to inspect and manage staged files.

Staged files are scoped to the current runtime; the registry clears the staging directory on
startup, so re-stage attachments after restarts.

On the exec JSONL transport (`codex exec --json`), attachments are forwarded as images via repeated `--image <path>` flags. The upstream exec CLI does not currently support arbitrary non-image file attachments.
Returning a `%Codex.Files.Attachment{}` from a tool (or passing one to `Codex.ToolOutput.normalize/1`) yields an `input_file` payload with the checksum as `file_id` and the staged contents base64-encoded.

---

## Realtime and Voice

Realtime and voice APIs from the Python SDK are not yet available in Elixir. The stub modules `Codex.Realtime` and `Codex.Voice` return `{:error, %Codex.Error{kind: :unsupported_feature}}` with descriptive messages to make the gap explicit until support lands.

---

## Codex.Approvals.StaticPolicy

Provides a lightweight approval policy used to gate tool invocations or sandbox-sensitive operations.

- `allow/1` — always approves (`StaticPolicy.allow(reason: "optional")`).
- `deny/1` — always denies with a custom reason.
- `review_tool/3` — invoked by `Codex.Thread.run_auto/3` to determine whether a requested tool may execute.

---

## Codex.MCP.Client

JSON-RPC client for MCP-compatible servers (stdio or streamable HTTP).

- `initialize/2` — sends `initialize`, records advertised capabilities, then emits `notifications/initialized`.
- `handshake/2` — backwards-compatible alias for `initialize/2`.
- `capabilities/1` — returns the negotiated capability list used to seed the tool registry.
- `list_tools/2` — fetches tool metadata via `tools/list`, caches responses by default, and supports `allow`/`deny`/`filter` options plus `cache?: false` to bypass cached entries.
- `list_resources/2` — fetches resources via `resources/list`.
- `list_prompts/2` — fetches prompts via `prompts/list`.
- `call_tool/4` — invokes a tool via `tools/call` with `retries`/`backoff` and optional `approval` callback.

### MCP transports

- `Codex.MCP.Transport.Stdio` — launches stdio MCP servers with the same default env whitelist as upstream Codex.
- `Codex.MCP.Transport.StreamableHTTP` — JSON-RPC over streamable HTTP with optional bearer/OAuth auth.

---

## Codex.MCP.Config

Helpers for managing MCP server configuration via app-server config APIs.

- `list_servers/2` — reads `mcp_servers` entries from `config/read`.
- `add_server/4` — writes `mcp_servers.<name>` entries via `config/value/write`.
- `remove_server/3` — clears `mcp_servers.<name>` entries via `config/value/write`.

---

## Codex.Skills

Skill discovery and loading helpers gated by `features.skills`.

- `list/2` — calls `skills/list` when enabled.
- `load/2` — loads skill file contents from the `path` field.

---

## Codex.Prompts

Custom prompt discovery and expansion helpers for `$CODEX_HOME/prompts`.

- `list/1` — discovers prompt files, parses frontmatter, and returns prompt metadata + content.
- `expand/2` — expands `$1..$9`, `$ARGUMENTS`, and `$KEY` placeholders with positional or `KEY=value` args.

### Hosted MCP tool

`Codex.Tools.HostedMcpTool` wraps an MCP client for use inside the tool registry. Register it with a `:client` and `:tool` plus optional `:retries`, `:backoff`, or `:approval` fields to mirror Python's hosted MCP wrapper.

---

## Codex.Session

Behaviour for persisting conversation history between runs. The built-in `Codex.Session.Memory` adapter stores entries in an Agent for short-lived runs.

- `session` / `session_input_callback` — configure on `RunConfig` to load history before a run and optionally transform the input. Callbacks receive the input and loaded history.
- `conversation_id` / `previous_response_id` — optional identifiers stored on thread metadata and persisted alongside session entries (optionally updated by `auto_previous_response_id` when the backend provides a `response_id`).

---

## Codex.Telemetry

Helper module for emitting telemetry and wiring default logging.

- `emit/3` — dispatches telemetry events (`:telemetry.execute`).
- `attach_default_logger/1` — logs thread start/stop/exception events with configurable log level.

## Error Types

- `Codex.Error` — normalized error struct for exec and turn failures (returned as `{:exec_failed, %Codex.Error{}}` or `{:turn_failed, %Codex.Error{}}`).
- `Codex.TransportError` — low-level exec errors from `Codex.Exec` streams; includes `exit_status` and optional `stderr`.
- `Codex.ApprovalError` — returned when an approval policy denies a tool invocation, exposing `tool` and `reason` fields.

### Functions

#### `start_link/1`

Starts an Exec GenServer and spawns the codex-rs process.

**Signature**:
```elixir
@spec start_link(keyword()) :: GenServer.on_start()
```

**Options**:
- `:input` (required): Input prompt for the turn
- `:codex_path` (optional): Path to codex binary
- `:thread_id` (optional): Existing thread ID to resume
- `:base_url` (optional): OpenAI API base URL
- `:api_key` (optional): OpenAI API key
- `:model` (optional): Model name
- `:sandbox_mode` (optional): Sandbox mode (`:read_only`, `:workspace_write`, `:danger_full_access`)
- `:working_directory` (optional): Working directory for agent
- `:skip_git_repo_check` (optional): Skip Git repository check
- `:output_schema_file` (optional): Path to JSON schema file

**Returns**:
- `{:ok, pid}`: GenServer process ID
- `{:error, reason}`: Spawn or configuration error

**Examples**:
```elixir
# Basic usage
{:ok, pid} = Codex.Exec.start_link(
  input: "Hello, Codex",
  codex_path: "/usr/local/bin/codex"
)

# With all options
{:ok, pid} = Codex.Exec.start_link(
  input: "Analyze code",
  codex_path: "/usr/local/bin/codex",
  thread_id: "thread_abc123",
  api_key: "sk-...",
  model: "o1",
  sandbox_mode: :read_only,
  working_directory: "/path/to/project",
  output_schema_file: "/tmp/schema.json"
)
```

---

#### `run_turn/2`

Starts turn execution and returns a reference for event tracking.

**Signature**:
```elixir
@spec run_turn(pid()) :: reference()
```

**Parameters**:
- `pid`: Exec GenServer process ID

**Returns**:
- `reference()`: Unique reference for this turn

**Usage**:
```elixir
{:ok, pid} = Codex.Exec.start_link(input: "example input")
ref = Codex.Exec.run_turn(pid)

# Receive events
receive do
  {:event, ^ref, event} ->
    IO.inspect(event)
  {:done, ^ref} ->
    IO.puts("Turn complete")
  {:error, ^ref, error} ->
    IO.puts("Error: #{inspect(error)}")
end
```

---

## Codex.Events

Event type definitions for all events emitted during turn execution.

### Event Types

#### `ThreadStarted`

Emitted when a new thread is started.

**Type**:
```elixir
@type t() :: %Codex.Events.ThreadStarted{
  type: :thread_started,
  thread_id: String.t()
}
```

**Fields**:
- `type`: Always `:thread_started`
- `thread_id`: Unique identifier for the thread (format: `"thread_*"`)

**Example**:
```elixir
%Codex.Events.ThreadStarted{
  type: :thread_started,
  thread_id: "thread_abc123xyz"
}
```

---

#### `TurnStarted`

Emitted when a turn begins processing.

**Type**:
```elixir
@type t() :: %Codex.Events.TurnStarted{
  type: :turn_started
}
```

---

#### `TurnCompleted`

Emitted when a turn completes successfully.

**Type**:
```elixir
@type t() :: %Codex.Events.TurnCompleted{
  type: :turn_completed,
  usage: Codex.Events.Usage.t()
}
```

**Fields**:
- `type`: Always `:turn_completed`
- `usage`: Token usage statistics

App-server `turn/completed` notifications also carry `status` and `error`; the SDK exposes them on
`Codex.Events.TurnCompleted`.

**Usage Type**:
```elixir
@type usage() :: %Codex.Events.Usage{
  input_tokens: non_neg_integer(),
  cached_input_tokens: non_neg_integer(),
  output_tokens: non_neg_integer()
}
```

**Example**:
```elixir
%Codex.Events.TurnCompleted{
  type: :turn_completed,
  usage: %Codex.Events.Usage{
    input_tokens: 1500,
    cached_input_tokens: 500,
    output_tokens: 800
  }
}
```

---

#### `TurnFailed`

Emitted when a turn fails with an error.

**Type**:
```elixir
@type t() :: %Codex.Events.TurnFailed{
  type: :turn_failed,
  error: Codex.Events.ThreadError.t()
}
```

**Error Type**:
```elixir
@type thread_error() :: %Codex.Events.ThreadError{
  message: String.t()
}
```

---

#### `ThreadTokenUsageUpdated`

Emitted when the app server publishes in-flight token usage totals.

**Type**:
```elixir
@type t() :: %Codex.Events.ThreadTokenUsageUpdated{
  thread_id: String.t() | nil,
  turn_id: String.t() | nil,
  usage: map(),
  delta: map() | nil
}
```

**Fields**:
- `thread_id`: Explicit thread identifier provided by Codex
- `turn_id`: Turn identifier when available
- `usage`: Cumulative token usage so far
- `delta`: Optional incremental token counts

---

#### `TurnDiffUpdated`

Diff metadata streamed alongside turn progress.

**Type**:
```elixir
@type t() :: %Codex.Events.TurnDiffUpdated{
  thread_id: String.t() | nil,
  turn_id: String.t() | nil,
  diff: map() | String.t()
}
```

---

#### `TurnPlanUpdated`

Plan metadata streamed from the app-server.

**Type**:
```elixir
@type t() :: %Codex.Events.TurnPlanUpdated{
  thread_id: String.t() | nil,
  turn_id: String.t() | nil,
  explanation: String.t() | nil,
  plan: [%{step: String.t(), status: :pending | :in_progress | :completed}]
}
```

---

#### `TurnCompaction`

Signals that Codex compacted a turn's history, often to trim token usage.

**Type**:
```elixir
@type t() :: %Codex.Events.TurnCompaction{
  thread_id: String.t() | nil,
  turn_id: String.t() | nil,
  compaction: map(),
  stage: :started | :completed | :failed | :unknown | String.t()
}
```

---

#### App-server delta events

The app-server transport emits additional typed deltas:

- `Codex.Events.CommandOutputDelta` and `Codex.Events.FileChangeOutputDelta` for streaming tool output
- `Codex.Events.TerminalInteraction` for interactive stdin writes
- `Codex.Events.ReasoningSummaryDelta`, `Codex.Events.ReasoningSummaryPartAdded`, and `Codex.Events.ReasoningDelta` for reasoning streams
- `Codex.Events.McpToolCallProgress` for MCP tool progress messages
- `Codex.Events.AccountUpdated`, `Codex.Events.AccountRateLimitsUpdated`, `Codex.Events.AccountLoginCompleted`, `Codex.Events.McpServerOauthLoginCompleted`, and `Codex.Events.WindowsWorldWritableWarning` for account/system updates
- `Codex.Events.RawResponseItemCompleted` for raw response items (ghost snapshots, compaction, etc.)
- `Codex.Events.DeprecationNotice` for deprecation warnings

#### `Error`

General error notification emitted by Codex.

**Type**:
```elixir
@type t() :: %Codex.Events.Error{
  message: String.t(),
  thread_id: String.t() | nil,
  turn_id: String.t() | nil
}
```

---

#### `ItemStarted`

Emitted when a new item is added to the thread.

**Type**:
```elixir
@type t() :: %Codex.Events.ItemStarted{
  type: :item_started,
  item: Codex.Items.t(),
  thread_id: String.t() | nil,
  turn_id: String.t() | nil
}
```

---

#### `ItemUpdated`

Emitted when an item's state changes.

**Type**:
```elixir
@type t() :: %Codex.Events.ItemUpdated{
  type: :item_updated,
  item: Codex.Items.t(),
  thread_id: String.t() | nil,
  turn_id: String.t() | nil
}
```

---

#### `ItemCompleted`

Emitted when an item reaches a terminal state.

**Type**:
```elixir
@type t() :: %Codex.Events.ItemCompleted{
  type: :item_completed,
  item: Codex.Items.t(),
  thread_id: String.t() | nil,
  turn_id: String.t() | nil
}
```

---

## Codex.Items

Thread item type definitions representing different actions and artifacts.

### Item Types

#### `AgentMessage`

Text or JSON response from the agent.

**Type**:
```elixir
@type t() :: %Codex.Items.AgentMessage{
  id: String.t(),
  type: :agent_message,
  text: String.t(),
  parsed: map() | list() | nil
}
```

**Fields**:
- `id`: Unique item identifier
- `type`: Always `:agent_message`
- `text`: Response text (natural language or JSON when using output schema)
- `parsed`: Decoded payload when an output schema is supplied (otherwise `nil`)

**Example**:
```elixir
%Codex.Items.AgentMessage{
  id: "msg_abc123",
  type: :agent_message,
  text: "GenServers are process abstractions in Elixir...",
  parsed: nil
}
```

---

#### `Reasoning`

Agent's reasoning summary.

**Type**:
```elixir
@type t() :: %Codex.Items.Reasoning{
  id: String.t(),
  type: :reasoning,
  text: String.t(),
  summary: [String.t()],
  content: [String.t()]
}
```

`summary` captures structured reasoning summaries; `content` holds raw reasoning blocks when available.

**Example**:
```elixir
%Codex.Items.Reasoning{
  id: "reasoning_1",
  type: :reasoning,
  text: "To fix this issue, I need to first understand the error, then locate the relevant code...",
  summary: ["Understand the error", "Locate the code"],
  content: ["Raw reasoning chunk"]
}
```

---

#### `CommandExecution`

Shell command executed by the agent.

**Type**:
```elixir
@type t() :: %Codex.Items.CommandExecution{
  id: String.t(),
  type: :command_execution,
  command: String.t(),
  aggregated_output: String.t(),
  exit_code: integer() | nil,
  status: :in_progress | :completed | :failed | :declined
}
```

**Fields**:
- `command`: Command line that was executed
- `aggregated_output`: Combined stdout and stderr
- `exit_code`: Exit status (nil while running, integer when complete)
- `status`: Current status of execution

**Example**:
```elixir
%Codex.Items.CommandExecution{
  id: "cmd_1",
  type: :command_execution,
  command: "ls -la",
  aggregated_output: "...\nREADME.md\nlib\n",
  exit_code: 0,
  status: :completed
}
```

---

#### `FileChange`

File modifications made by the agent.

**Type**:
```elixir
@type t() :: %Codex.Items.FileChange{
  id: String.t(),
  type: :file_change,
  changes: [file_update_change()],
  status: :in_progress | :completed | :failed | :declined
}
```

**Change Type**:
```elixir
@type file_update_change() :: %{
  path: String.t(),
  kind: :add | :delete | :update
}
```

**Example**:
```elixir
%Codex.Items.FileChange{
  id: "patch_1",
  type: :file_change,
  changes: [
    %{path: "lib/my_app.ex", kind: :update},
    %{path: "lib/new_module.ex", kind: :add}
  ],
  status: :completed
}
```

---

#### `McpToolCall`

Model Context Protocol tool invocation.

**Type**:
```elixir
@type t() :: %Codex.Items.McpToolCall{
  id: String.t(),
  type: :mcp_tool_call,
  server: String.t(),
  tool: String.t(),
  arguments: map() | list() | nil,
  result: map() | nil,
  error: map() | nil,
  status: :in_progress | :completed | :failed
}
```

**Example**:
```elixir
%Codex.Items.McpToolCall{
  id: "mcp_1",
  type: :mcp_tool_call,
  server: "database_server",
  tool: "query_records",
  arguments: %{"query" => "SELECT * FROM users"},
  result: %{"content" => [%{"type" => "text", "text" => "ok"}]},
  status: :completed
}
```

---

#### `WebSearch`

Web search query and results.

**Type**:
```elixir
@type t() :: %Codex.Items.WebSearch{
  id: String.t(),
  type: :web_search,
  query: String.t()
}
```

---

#### `TodoList`

Agent's running task list.

**Type**:
```elixir
@type t() :: %Codex.Items.TodoList{
  id: String.t(),
  type: :todo_list,
  items: [todo_item()]
}
```

**Todo Item Type**:
```elixir
@type todo_item() :: %{
  text: String.t(),
  completed: boolean()
}
```

**Example**:
```elixir
%Codex.Items.TodoList{
  id: "todo_1",
  type: :todo_list,
  items: [
    %{text: "Analyze codebase", completed: true},
    %{text: "Identify issues", completed: true},
    %{text: "Propose fixes", completed: false}
  ]
}
```

---

#### `Error`

Non-fatal error item.

**Type**:
```elixir
@type t() :: %Codex.Items.Error{
  id: String.t(),
  type: :error,
  message: String.t()
}
```

---

## Codex.Options

Configuration structs for different levels of the SDK.

### `Codex.Options`

Global Codex configuration.

**Type**:
```elixir
@type t() :: %Codex.Options{
  codex_path_override: String.t() | nil,
  base_url: String.t() | nil,
  api_key: String.t() | nil,
  telemetry_prefix: [atom()],
  model: String.t() | nil,
  reasoning_effort: Codex.Models.reasoning_effort() | nil,
  model_personality: :friendly | :pragmatic | :none | nil,
  model_reasoning_summary: String.t() | nil,
  model_verbosity: String.t() | nil,
  model_context_window: pos_integer() | nil,
  model_supports_reasoning_summaries: boolean() | nil,
  model_auto_compact_token_limit: pos_integer() | nil,
  review_model: String.t() | nil,
  history_persistence: String.t() | nil,
  history_max_bytes: non_neg_integer() | nil,
  hide_agent_reasoning: boolean(),
  tool_output_token_limit: pos_integer() | nil,
  agent_max_threads: pos_integer() | nil,
  config_overrides: [
    String.t()
    | {String.t(), String.t() | boolean() | integer() | float() | list() | map()}
  ]
}
```

**Fields**:
- `codex_path_override`: Custom path to codex binary (defaults to system PATH)
- `base_url`: OpenAI API base URL (precedence: explicit option, then `OPENAI_BASE_URL`, then official default)
- `api_key`: OpenAI API key (overrides `CODEX_API_KEY`; optional if CLI login is present)
- `telemetry_prefix`: Telemetry prefix for metrics/events (defaults to `[:codex]`)
- `model`: Model override (defaults to `Codex.Models.default_model/0`)
- `reasoning_effort`: Reasoning effort override (`:none`, `:minimal`, `:low`, `:medium`, `:high`, or `:xhigh`; defaults to `Codex.Models.default_reasoning_effort/1`)
- `model_personality`: Personality preference (`:friendly`, `:pragmatic`, or `:none`)
- `model_reasoning_summary`: Reasoning summary setting (`auto`, `concise`, `detailed`, `none`)
- `model_verbosity`: Response verbosity (`low`, `medium`, `high`)
- `model_context_window`: Context window size override, in tokens
- `model_supports_reasoning_summaries`: Force-enable reasoning summaries for non-default models
- `model_auto_compact_token_limit`: Auto-compaction token threshold
- `review_model`: Model override for review mode runs
- `history_persistence`: History persistence mode override (mirrors `history.persistence`)
- `history_max_bytes`: History size cap in bytes (mirrors `history.max_bytes`)
- `hide_agent_reasoning`: Hide reasoning summaries even when supported
- `tool_output_token_limit`: Token cap for tool outputs (per turn)
- `agent_max_threads`: Limit for max concurrent agent threads
- `config_overrides` / `config`: Global config override bag flattened into `--config` flags before derived/thread/turn overrides; use TOML-compatible values only (strings, booleans, numbers, arrays, nested maps)

**Example**:
```elixir
%Codex.Options{
  codex_path_override: "/custom/path/to/codex",
  base_url: "https://api.openai.com",
  api_key: System.get_env("CODEX_API_KEY"),
  config_overrides: [{"model_reasoning_summary", "concise"}]
}
```

---

### `Codex.Thread.Options`

Thread-specific configuration.

**Type**:
```elixir
@type t() :: %Codex.Thread.Options{
  metadata: map(),
  labels: map(),
  auto_run: boolean(),
  transport: :exec | {:app_server, pid()},
  approval_policy: module() | nil,
  approval_hook: module() | nil,
  approval_timeout_ms: pos_integer(),
  sandbox:
    :default
    | :strict
    | :permissive
    | :read_only
    | :workspace_write
    | :danger_full_access
    | :external_sandbox
    | {:external_sandbox, :enabled | :restricted}
    | String.t(),
  sandbox_policy: map() | atom() | nil,
  working_directory: String.t() | nil,
  additional_directories: [String.t()],
  skip_git_repo_check: boolean(),
  network_access_enabled: boolean() | nil,
  web_search_enabled: boolean(),
  web_search_mode: :disabled | :cached | :live,
  personality: :friendly | :pragmatic | :none | nil,
  collaboration_mode: Codex.Protocol.CollaborationMode.t() | nil,
  compact_prompt: String.t() | nil,
  show_raw_agent_reasoning: boolean(),
  output_schema: map() | nil,
  apply_patch_freeform_enabled: boolean() | nil,
  view_image_tool_enabled: boolean() | nil,
  unified_exec_enabled: boolean() | nil,
  skills_enabled: boolean() | nil,
  ask_for_approval: atom() | String.t() | nil,
  attachments: [map()],
  file_search: Codex.FileSearch.t() | nil,
  profile: String.t() | nil,
  oss: boolean(),
  local_provider: String.t() | nil,
  full_auto: boolean(),
  dangerously_bypass_approvals_and_sandbox: boolean(),
  output_last_message: String.t() | nil,
  color: :auto | :always | :never | String.t() | nil,
  config_overrides: [
    String.t()
    | {String.t() | atom(), String.t() | boolean() | integer() | float() | list() | map()}
  ],
  history_persistence: String.t() | nil,
  history_max_bytes: non_neg_integer() | nil,
  model: String.t() | nil,
  model_provider: String.t() | nil,
  model_reasoning_summary: String.t() | nil,
  model_verbosity: String.t() | nil,
  model_context_window: pos_integer() | nil,
  model_supports_reasoning_summaries: boolean() | nil,
  request_max_retries: pos_integer() | nil,
  stream_max_retries: pos_integer() | nil,
  stream_idle_timeout_ms: pos_integer() | nil,
  config: map() | nil,
  base_instructions: String.t() | nil,
  developer_instructions: String.t() | nil,
  shell_environment_policy: map() | nil,
  retry: boolean() | nil,
  retry_opts: keyword() | nil,
  rate_limit: boolean() | nil,
  rate_limit_opts: keyword() | nil,
  experimental_raw_events: boolean()
}
```

**Fields**:
- `metadata`: Arbitrary per-thread metadata stored on the thread and passed to tool contexts (commonly includes `:tool_context` or approval hints)
- `labels`: Optional label map merged with server metadata
- `auto_run`: Enable CLI-driven auto-run (default: false)
- `transport`: `:exec` or `{:app_server, pid()}` for JSON-RPC transport
- `approval_policy` / `approval_hook` / `approval_timeout_ms`: Approval gating for tool calls
- `sandbox`: Exec CLI sandbox mode (e.g. `:strict`, `:workspace_write`, `:external_sandbox`)
- `sandbox_policy`: App-server sandbox policy override (`type`, `writable_roots`, `network_access`)
- `working_directory`: Working directory passed to codex (`--cd` / `cwd`)
- `additional_directories`: Extra writable roots (`--add-dir`)
- `skip_git_repo_check`: Allow running outside a Git repo
- `network_access_enabled`: Workspace-write network access override for exec (`--config sandbox_workspace_write.network_access=...`)
- `web_search_enabled`: Legacy web search toggle (deprecated; use `web_search_mode`); explicit `false` emits `web_search="disabled"`
- `web_search_mode`: Web search mode override (`:disabled`, `:cached`, `:live`); explicit `:disabled` emits `web_search="disabled"` while untouched defaults emit nothing
- `personality`: Thread-level personality override (`:friendly`, `:pragmatic`, `:none`), serialized consistently across exec and app-server transports
- `collaboration_mode`: Collaboration mode preset for app-server turns (`:plan`, `:pair_programming`, `:execute`, or `:custom`)
- `compact_prompt`: Override prompt used for context compaction
- `show_raw_agent_reasoning`: Emit raw reasoning content in reasoning items
- `output_schema`: Default JSON schema for structured outputs (turn options override)
- `apply_patch_freeform_enabled`: Enable the freeform apply_patch tool (`features.apply_patch_freeform`)
- `view_image_tool_enabled`: Enable the view_image tool (`features.view_image_tool`)
- `unified_exec_enabled`: Enable unified exec tool (`features.unified_exec`)
- `skills_enabled`: Enable skills discovery/injection (`features.skills`)
- `ask_for_approval`: Approval policy hint for app-server turns
- `attachments`: List of `%Codex.Files.Attachment{}` forwarded to the codex binary
- `file_search`: Default file search config (`vector_store_ids`, `filters`, `ranking_options`, `include_search_results`) merged with per-run overrides
- `profile`: Config profile name (`--profile`)
- `oss` / `local_provider`: OSS provider flags (`--oss`, `--local-provider`)
- `full_auto` / `dangerously_bypass_approvals_and_sandbox`: Execution-mode shortcuts (mutually exclusive)
- `output_last_message`: File path for `--output-last-message`
- `color`: Output color mode (`--color`)
- `config_overrides`: Generic `-c key=value` overrides (strings, `{key, value}` pairs, or nested maps that are auto-flattened to dotted paths)
- `config_overrides` value validation: only TOML-compatible values are accepted (`nil` and unsupported terms error early)
- `history_persistence` / `history_max_bytes`: History persistence configuration forwarded via config overrides
- `model` / `model_provider`: App-server thread model overrides
- `model_reasoning_summary` / `model_verbosity`: Reasoning summary + verbosity settings forwarded via config overrides
- `model_context_window`: Context window override (tokens)
- `model_supports_reasoning_summaries`: Force reasoning summary support for non-default models
- `request_max_retries` / `stream_max_retries` / `stream_idle_timeout_ms`: Per-provider network tuning overrides (config)
- `config`: App-server config override map
- `base_instructions` / `developer_instructions`: App-server instruction overrides
- `shell_environment_policy`: CLI shell env policy overrides (`shell_environment_policy.*`)
- `retry` / `retry_opts`: Enable transport retries (uses `Codex.Retry`)
- `rate_limit` / `rate_limit_opts`: Enable rate-limit handling (uses `Codex.RateLimit`)
- `experimental_raw_events`: App-server raw response item toggle

**Example**:
```elixir
%Codex.Thread.Options{
  metadata: %{tool_context: %{project: "docs"}},
  attachments: [%Codex.Files.Attachment{...}],
  file_search: %{vector_store_ids: ["vs_default"], include_search_results: true},
  config_overrides: ["features.web_search_request=true"]
}
```

---

### Turn options

Turn-specific configuration passed as a map or keyword list.

**Type**:
```elixir
@type t() :: %{
  optional(:output_schema) => map() | nil,
  optional(:config_overrides) => map() | keyword() | [String.t()] | nil,
  optional(:sandbox_policy) => map() | atom() | nil,
  optional(:model) => String.t() | nil,
  optional(:approval_policy) => atom() | String.t() | nil,
  optional(:cwd) => String.t() | nil,
  optional(:effort) => atom() | String.t() | nil,
  optional(:summary) => atom() | String.t() | nil,
  optional(:env) => map() | keyword() | nil,
  optional(:clear_env?) => boolean() | nil,
  optional(:cancellation_token) => String.t() | nil,
  optional(:timeout_ms) => pos_integer() | nil,
  optional(:stream_idle_timeout_ms) => pos_integer() | nil,
  optional(:retry) => boolean() | nil,
  optional(:retry_opts) => keyword() | map() | nil,
  optional(:rate_limit) => boolean() | nil,
  optional(:rate_limit_opts) => keyword() | map() | nil
}
```

**Fields**:
- `output_schema`: JSON schema for structured output (nil for natural language)
- `config_overrides`: Exec `-c key=value` overrides (strings or key/value pairs)
- `config_overrides` value validation: only TOML-compatible values are accepted (`nil` and unsupported terms error early)
- `sandbox_policy`: App-server sandbox policy override
- `model` / `approval_policy` / `cwd`: App-server per-turn overrides
- `effort` / `summary`: App-server reasoning overrides
- `env` / `clear_env?`: Exec env overrides and optional env clearing; SDK sets `CODEX_INTERNAL_ORIGINATOR_OVERRIDE=codex_sdk_elixir` unless overridden in `env`
- `cancellation_token`: Exec cancellation token
- `timeout_ms`: Exec overall timeout (blocking)
- `stream_idle_timeout_ms`: Exec stream idle timeout
- `retry` / `retry_opts`: Opt-in retry handling for transports
- `rate_limit` / `rate_limit_opts`: Opt-in rate limit handling for transports

**Example**:
```elixir
turn_opts = %{
  output_schema: %{
    "type" => "object",
    "properties" => %{
      "summary" => %{"type" => "string"},
      "status" => %{"type" => "string", "enum" => ["ok", "error"]}
    },
    "required" => ["summary", "status"]
  }
}
```

---

## Codex.OutputSchemaFile

Utility for managing JSON schema temporary files.

### Functions

#### `create/1`

Creates a temporary file with the JSON schema.

**Signature**:
```elixir
@spec create(map() | nil) :: {:ok, {String.t() | nil, function()}} | {:error, term()}
```

**Parameters**:
- `schema`: JSON schema map or nil

**Returns**:
- `{:ok, {path, cleanup}}`: Path to temp file and cleanup function
- `{:error, reason}`: Error creating file

**Examples**:
```elixir
# With schema
schema = %{"type" => "object", "properties" => %{}}
{:ok, {path, cleanup}} = Codex.OutputSchemaFile.create(schema)

# Use path...

# Clean up
cleanup.()

# Without schema
{:ok, {nil, cleanup}} = Codex.OutputSchemaFile.create(nil)
cleanup.()  # No-op
```

**Notes**:
- Creates temp directory in system tmp folder
- Writes JSON to `schema.json` in that directory
- Cleanup function removes entire directory
- Cleanup is idempotent (safe to call multiple times)
- Used internally by `Codex.Thread`

---

## Type Aliases

### `Codex.Turn.Result`

Result of a completed turn (from `run/3`).

**Type**:
```elixir
@type t() :: %Codex.Turn.Result{
  thread: Codex.Thread.t(),
  events: [Codex.Events.t()],
  final_response: Codex.Items.AgentMessage.t() | map() | nil,
  usage: map() | nil,
  raw: map(),
  attempts: non_neg_integer(),
  last_response_id: String.t() | nil
}
```

**Fields**:
- `thread`: Updated thread struct containing continuation & metadata
- `events`: Events emitted during the turn
- `final_response`: Last agent message (typed struct with optional `parsed` payload)
- `usage`: Token usage statistics (nil if turn failed before completion)
- `raw`: Underlying exec metadata (`events`, CLI flags, etc.)
- `attempts`: Number of attempts performed (useful for auto-run)
- `last_response_id`: Last backend response identifier when surfaced (currently `nil` on `codex exec --json`)

**Helpers**:

- `Codex.Turn.Result.json/1` — returns `{:ok, map()}` when structured output was decoded, or an error tuple (`{:error, :not_structured}` / `{:error, {:invalid_json, reason}}`).

---

## Common Patterns

### Error Handling

```elixir
case Codex.Thread.run(thread, input) do
  {:ok, result} ->
    process_result(result)

  {:error, {:turn_failed, error}} ->
    Logger.error("Turn failed: #{error.message}")
    {:error, :turn_failed}

  {:error, {:process, reason}} ->
    Logger.error("Process error: #{inspect(reason)}")
    {:error, :process_error}

  {:error, reason} ->
    Logger.error("Unknown error: #{inspect(reason)}")
    {:error, :unknown}
end
```

### Streaming with Pattern Matching

```elixir
{:ok, stream} = Codex.Thread.run_streamed(thread, input)

Enum.reduce(stream, %{commands: [], files: []}, fn
  %ItemCompleted{item: %{type: :command_execution} = cmd}, acc ->
    %{acc | commands: [cmd | acc.commands]}

  %ItemCompleted{item: %{type: :file_change} = file}, acc ->
    %{acc | files: [file | acc.files]}

  _, acc ->
    acc
end)
```

### Structured Output with Validation

```elixir
schema = %{
  "type" => "object",
  "properties" => %{
    "status" => %{"type" => "string", "enum" => ["success", "failure"]},
    "data" => %{"type" => "object"}
  },
  "required" => ["status"]
}

turn_opts = %{output_schema: schema}
{:ok, result} = Codex.Thread.run(thread, "Check system status", turn_opts)

case Jason.decode(result.final_response) do
  {:ok, %{"status" => "success", "data" => data}} ->
    process_data(data)

  {:ok, %{"status" => "failure"}} ->
    handle_failure()

  {:error, _} ->
    {:error, :invalid_json}
end
```

---

## Migration from TypeScript SDK

For developers familiar with the TypeScript SDK:

| TypeScript | Elixir |
|------------|--------|
| `new Codex()` | `Codex` module (no instance needed) |
| `codex.startThread()` | `Codex.start_thread()` |
| `codex.resumeThread(id)` | `Codex.resume_thread(id)` |
| `await thread.run(input)` | `Codex.Thread.run(thread, input)` |
| `await thread.runStreamed(input)` | `Codex.Thread.run_streamed(thread, input)` |
| `for await (const event of events)` | `Enum.each(stream, fn event -> ... end)` |
| `CodexOptions` | `%Codex.Options{}` |
| `ThreadOptions` | `%Codex.Thread.Options{}` |
| `TurnOptions` | map/keyword (e.g., `%{output_schema: schema}`) |

---

## See Also

- [Getting Started](01-getting-started.md)
- [Architecture Guide](02-architecture.md)
- [Examples](04-examples.md)
- [App-server Transport](05-app-server-transport.md)
