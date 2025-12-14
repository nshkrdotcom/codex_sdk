# Implementation Recommendations for Unported Features

**Date**: 2025-12-13
**Purpose**: Detailed implementation guidance for filling gaps in the Elixir SDK

---

## 0. CODEX CLI OPTION FORWARDING (MEDIUM PRIORITY)

Several TypeScript SDK options are forwarded to `codex exec` via CLI flags and environment variables.
The Elixir subprocess wrapper now forwards the main parity set as well.

### 0.1 Base URL (`OPENAI_BASE_URL`) (DONE)

TypeScript sets `OPENAI_BASE_URL = baseUrl` in the subprocess environment. Elixir forwards
`Codex.Options.base_url` via `OPENAI_BASE_URL`.

**Status**: Implemented in `lib/codex/exec.ex`.

### 0.2 ThreadOptions parity (sandbox/cd/add-dir/skip-git/network/web_search/approval_policy) (DONE)

TypeScript forwards these knobs to the CLI:
- `--sandbox <mode>`
- `--cd <path>`
- `--add-dir <path>` (repeatable)
- `--skip-git-repo-check`
- `--config sandbox_workspace_write.network_access=...`
- `--config features.web_search_request=...`
- `--config approval_policy="..."`

**Status**: Implemented via `Codex.Thread.Options` + forwarding in `lib/codex/exec.ex`.

### 0.3 Optional hardening: clear environment (`clear_env?`)

Erlexec inherits the parent environment by default. If you want to avoid accidental leakage of
environment variables into the `codex` subprocess, you can opt into clearing the environment per
turn.

**Option**: `turn_opts[:clear_env?]` (boolean)
- `false` (default): inherit parent env + add/override with the provided env map
- `true`: pass erlexec `{:env, [:clear | ...]}` to clear env first, then re-add a minimal safe set
  (`HOME`, `PATH`, etc.) plus the Codex-specific env vars (`OPENAI_BASE_URL`, API key, originator)

**Implementation**: `lib/codex/exec.ex` builds an env spec including `:clear` when `clear_env?` is true.

## 1. SESSION BACKENDS (MEDIUM PRIORITY)

### 1.1 ETS Session Backend

**File**: `lib/codex/session/ets.ex`

```elixir
defmodule Codex.Session.ETS do
  @moduledoc """
  ETS-backed session storage.

  Persists across processes but not across VM restarts.
  Good for development and short-lived production sessions.
  """

  @behaviour Codex.Session

  @table_name :codex_sessions

  defstruct [:session_id, :table]

  def start_link(opts \\ []) do
    table = opts[:table] || @table_name
    :ets.new(table, [:named_table, :public, :set])
    {:ok, %__MODULE__{table: table}}
  end

  @impl true
  def load(%{session_id: id, table: table}) do
    case :ets.lookup(table, id) do
      [{^id, items}] -> {:ok, items}
      [] -> {:ok, []}
    end
  end

  @impl true
  def save(%{session_id: id, table: table} = state, entry) do
    {:ok, items} = load(state)
    :ets.insert(table, {id, items ++ [entry]})
    :ok
  end

  @impl true
  def clear(%{session_id: id, table: table}) do
    :ets.delete(table, id)
    :ok
  end
end
```

### 1.2 DETS Session Backend

**File**: `lib/codex/session/dets.ex`

```elixir
defmodule Codex.Session.DETS do
  @moduledoc """
  DETS-backed session storage.

  Persists to disk across VM restarts.
  Good for simple file-based persistence.
  """

  @behaviour Codex.Session

  defstruct [:session_id, :table, :file_path]

  def open(session_id, opts \\ []) do
    file_path = opts[:file_path] || Path.join(System.tmp_dir!(), "codex_sessions.dets")
    {:ok, table} = :dets.open_file(:codex_sessions, [file: String.to_charlist(file_path)])
    {:ok, %__MODULE__{session_id: session_id, table: table, file_path: file_path}}
  end

  def close(%{table: table}) do
    :dets.close(table)
  end

  @impl true
  def load(%{session_id: id, table: table}) do
    case :dets.lookup(table, id) do
      [{^id, items}] -> {:ok, items}
      [] -> {:ok, []}
    end
  end

  @impl true
  def save(%{session_id: id, table: table} = state, entry) do
    {:ok, items} = load(state)
    :dets.insert(table, {id, items ++ [entry]})
    :dets.sync(table)
    :ok
  end

  @impl true
  def clear(%{session_id: id, table: table}) do
    :dets.delete(table, id)
    :dets.sync(table)
    :ok
  end
end
```

### 1.3 Redis Session Backend (Optional Dep)

**File**: `lib/codex/session/redis.ex`

```elixir
defmodule Codex.Session.Redis do
  @moduledoc """
  Redis-backed session storage.

  Requires `redix` dependency:

      {:redix, "~> 1.2", optional: true}
  """

  @behaviour Codex.Session

  defstruct [:session_id, :conn, :prefix, :ttl]

  def connect(session_id, opts \\ []) do
    url = opts[:url] || System.get_env("REDIS_URL", "redis://localhost:6379")
    prefix = opts[:prefix] || "codex:session:"
    ttl = opts[:ttl] || :infinity

    case Redix.start_link(url) do
      {:ok, conn} ->
        {:ok, %__MODULE__{session_id: session_id, conn: conn, prefix: prefix, ttl: ttl}}
      error -> error
    end
  end

  defp key(%{session_id: id, prefix: prefix}), do: "#{prefix}#{id}"

  @impl true
  def load(%{conn: conn} = state) do
    case Redix.command(conn, ["GET", key(state)]) do
      {:ok, nil} -> {:ok, []}
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  @impl true
  def save(%{conn: conn, ttl: ttl} = state, entry) do
    {:ok, items} = load(state)
    new_items = items ++ [entry]
    json = Jason.encode!(new_items)

    cmd = case ttl do
      :infinity -> ["SET", key(state), json]
      ttl_ms -> ["SET", key(state), json, "PX", ttl_ms]
    end

    case Redix.command(conn, cmd) do
      {:ok, "OK"} -> :ok
      error -> error
    end
  end

  @impl true
  def clear(%{conn: conn} = state) do
    case Redix.command(conn, ["DEL", key(state)]) do
      {:ok, _} -> :ok
      error -> error
    end
  end
end
```

---

## 2. LIFECYCLE HOOKS (MEDIUM PRIORITY)

Elixir already has `hooks` fields on `Codex.Agent` and `Codex.RunConfig`, but they are not invoked by
the current runner implementation. This section describes how to formalize + wire hook callbacks to
match Python’s `RunHooks`/`AgentHooks` behavior.

### 2.1 Hooks Behavior Definition

**File**: `lib/codex/hooks.ex`

```elixir
defmodule Codex.Hooks do
  @moduledoc """
  Lifecycle hooks for agent execution.

  ## Example

      defmodule MyHooks do
        @behaviour Codex.Hooks

        @impl true
        def on_agent_start(context, agent) do
          IO.puts("Starting agent: \#{agent.name}")
          :ok
        end

        @impl true
        def on_tool_end(context, agent, tool, result) do
          Logger.info("Tool \#{tool} completed", result: result)
          :ok
        end
      end
  """

  @type context :: map()
  @type agent :: Codex.Agent.t()
  @type tool :: String.t()
  @type result :: any()

  @doc "Called before LLM invocation"
  @callback on_llm_start(context, agent, system_prompt :: String.t(), input_items :: list()) ::
              :ok | {:error, term()}

  @doc "Called after LLM response"
  @callback on_llm_end(context, agent, response :: map()) ::
              :ok | {:error, term()}

  @doc "Called when agent starts execution"
  @callback on_agent_start(context, agent) ::
              :ok | {:error, term()}

  @doc "Called when agent produces output"
  @callback on_agent_end(context, agent, output :: any()) ::
              :ok | {:error, term()}

  @doc "Called during agent handoff"
  @callback on_handoff(context, from_agent :: agent, to_agent :: agent) ::
              :ok | {:error, term()}

  @doc "Called before tool invocation"
  @callback on_tool_start(context, agent, tool) ::
              :ok | {:error, term()}

  @doc "Called after tool execution"
  @callback on_tool_end(context, agent, tool, result) ::
              :ok | {:error, term()}

  @optional_callbacks [
    on_llm_start: 4,
    on_llm_end: 3,
    on_agent_start: 2,
    on_agent_end: 3,
    on_handoff: 3,
    on_tool_start: 3,
    on_tool_end: 4
  ]

  @doc "Run hooks safely, catching errors"
  def run(hooks, callback, args) when is_atom(callback) do
    case hooks do
      nil -> :ok
      module when is_atom(module) ->
        if function_exported?(module, callback, length(args)) do
          try do
            apply(module, callback, args)
          rescue
            e -> {:error, {:hook_error, callback, e}}
          end
        else
          :ok
        end
      _ -> :ok
    end
  end
end
```

### 2.2 Integration in AgentRunner

Add hook invocations to `Codex.AgentRunner`:

```elixir
# In run_turn/4:
defp run_turn(thread, input, agent, opts) do
  context = opts[:context] || %{}
  hooks = agent.hooks || opts[:hooks]

  # Before agent starts
  Codex.Hooks.run(hooks, :on_agent_start, [context, agent])

  # Before LLM call
  Codex.Hooks.run(hooks, :on_llm_start, [context, agent, agent.instructions, input])

  result = Codex.Thread.run_turn(thread, input, opts)

  # After LLM response
  Codex.Hooks.run(hooks, :on_llm_end, [context, agent, result])

  # After agent produces output
  Codex.Hooks.run(hooks, :on_agent_end, [context, agent, result.final_response])

  result
end
```

---

## 3. HOSTED TOOL WRAPPERS (MEDIUM PRIORITY)

The Elixir SDK already includes callback-driven hosted tool wrappers in
`lib/codex/tools/hosted_tools.ex`:
`Codex.Tools.{ShellTool,ApplyPatchTool,ComputerTool,FileSearchTool,WebSearchTool,ImageGenerationTool,CodeInterpreterTool,HostedMcpTool}`.

The remaining gap is providing *default implementations* (or clear BYO documentation) that match
Python’s out-of-the-box behavior.

### 3.1 Web Search Tool

**Module**: `Codex.Tools.WebSearchTool` (already exists)

**What’s missing**: a default `:searcher` implementation (Python performs real web search out of the box).

**Recommendation**:
- Provide a default search backend (or explicitly document BYO).
- The wrapper expects a `:searcher` callback in `context.metadata`.

Example usage:

```elixir
{:ok, _handle} = Codex.Tools.register(Codex.Tools.WebSearchTool)

context = %{
  metadata: %{
    searcher: fn %{"query" => q}, _context ->
      {:ok, %{query: q, results: []}}
    end
  }
}

Codex.Tools.invoke("web_search", %{"query" => "site:example.com codex"}, context)
```

### 3.2 Code Interpreter Tool

**Module**: `Codex.Tools.CodeInterpreterTool` (already exists)

**What’s missing**: a default `:runner` implementation.

**Recommendation**:
- Provide a default runner (or document BYO) and treat timeouts/resource limits explicitly.
- The wrapper expects a `:runner` callback in `context.metadata`.

### 3.3 Apply Patch Tool

**Module**: `Codex.Tools.ApplyPatchTool` (already exists)

**What’s missing**: a built-in patch application engine.

**Recommendation**:
- Add an “apply diff” implementation similar to Python’s `apply_diff` + structured patch operations.
- Or clearly document that callers must supply an `:editor` callback in `context.metadata`.

Example BYO editor:

```elixir
{:ok, _handle} = Codex.Tools.register(Codex.Tools.ApplyPatchTool)

context = %{
  metadata: %{
    editor: fn %{"patch" => patch}, _context ->
      # Apply patch here (custom implementation)
      {:ok, %{accepted: true, bytes: byte_size(patch)}}
    end
  }
}

Codex.Tools.invoke("apply_patch", %{"patch" => "---\\n+++\\n"}, context)
```

---

## 4. IMAGE INPUT TYPE (LOW-MEDIUM PRIORITY)

Elixir already supports passing local images to the `codex` CLI via `Codex.Files` staging +
`Thread.Options.attachments` (translated to `--image` flags). The remaining gap vs the TypeScript SDK
is API ergonomics: TypeScript supports a per-turn `UserInput[]` union that can inline
`{type: "local_image", path: ...}` alongside text segments.

### 4.1 Update Input Type

**In**: `lib/codex/thread.ex`

```elixir
@type user_input ::
  String.t()
  | %{type: :text, text: String.t()}
  | %{type: :local_image, path: String.t()}
  | [user_input()]

defp normalize_input(input) when is_binary(input), do: input
defp normalize_input(%{type: :text, text: text}), do: text
defp normalize_input(%{type: :local_image, path: path}) do
  # Add to attachments or convert to CLI flag
  {:image, path}
end
defp normalize_input(inputs) when is_list(inputs) do
  Enum.map(inputs, &normalize_input/1)
end
```

### 4.2 Handle in Exec

No change required for attachments: Elixir already appends `--image` flags for `Codex.Files.Attachment`
values in `Codex.Exec.attachment_args/1`. This section is only needed if you add a new per-turn image
input API.

## 5. REALTIME/VOICE (HIGH PRIORITY - FUTURE)

### 5.1 Basic Structure

**File**: `lib/codex/realtime/session.ex`

```elixir
defmodule Codex.Realtime.Session do
  @moduledoc """
  WebSocket-based realtime audio session.

  Requires `websockex` or `mint_web_socket` dependency.
  """

  use GenServer

  defstruct [
    :conn,
    :agent,
    :config,
    :event_handler
  ]

  @type audio_format :: :pcm16 | :g711_ulaw | :g711_alaw

  def start_link(opts) do
    agent = Keyword.fetch!(opts, :agent)
    config = Keyword.get(opts, :config, %{})
    handler = Keyword.get(opts, :event_handler)

    GenServer.start_link(__MODULE__, %{
      agent: agent,
      config: config,
      event_handler: handler
    })
  end

  def send_audio(session, audio_data) when is_binary(audio_data) do
    GenServer.cast(session, {:send_audio, audio_data})
  end

  def send_message(session, text) when is_binary(text) do
    GenServer.cast(session, {:send_message, text})
  end

  def send_interrupt(session) do
    GenServer.cast(session, :interrupt)
  end

  @impl true
  def init(state) do
    # Connect to OpenAI Realtime API
    # ... WebSocket connection setup ...
    {:ok, state}
  end

  @impl true
  def handle_cast({:send_audio, data}, state) do
    # Send audio chunk
    {:noreply, state}
  end

  @impl true
  def handle_cast({:send_message, text}, state) do
    # Send text message
    {:noreply, state}
  end

  @impl true
  def handle_cast(:interrupt, state) do
    # Send interrupt signal
    {:noreply, state}
  end

  @impl true
  def handle_info({:websocket, :message, data}, state) do
    # Handle incoming WebSocket message
    event = decode_event(data)

    if state.event_handler do
      send(state.event_handler, {:realtime_event, event})
    end

    {:noreply, state}
  end

  defp decode_event(data) do
    # Decode realtime API event
    Jason.decode!(data)
  end
end
```

### 5.2 Realtime Events

**File**: `lib/codex/realtime/events.ex`

```elixir
defmodule Codex.Realtime.Events do
  @moduledoc """
  Realtime session event types.
  """

  defmodule Audio do
    defstruct [:data, :format, :sample_rate]
  end

  defmodule AudioEnd do
    defstruct [:item_id]
  end

  defmodule AudioInterrupted do
    defstruct [:item_id, :audio_end_ms]
  end

  defmodule ToolStart do
    defstruct [:tool_name, :call_id, :arguments]
  end

  defmodule ToolEnd do
    defstruct [:tool_name, :call_id, :result]
  end

  defmodule HandoffEvent do
    defstruct [:from_agent, :to_agent]
  end

  defmodule Error do
    defstruct [:code, :message]
  end

  def decode(%{"type" => "audio", "data" => data} = event) do
    %Audio{
      data: Base.decode64!(data),
      format: event["format"],
      sample_rate: event["sample_rate"]
    }
  end

  def decode(%{"type" => "audio.end"} = event) do
    %AudioEnd{item_id: event["item_id"]}
  end

  # ... more decoders ...
end
```

---

## 6. TESTING RECOMMENDATIONS

### 6.1 Session Backend Tests

```elixir
# test/codex/session/ets_test.exs
defmodule Codex.Session.ETSTest do
  use ExUnit.Case

  alias Codex.Session.ETS

  setup do
    {:ok, session} = ETS.start_link(table: :test_sessions)
    state = %ETS{session_id: "test-#{:rand.uniform(1000)}", table: :test_sessions}
    {:ok, state: state}
  end

  test "load returns empty list for new session", %{state: state} do
    assert {:ok, []} = ETS.load(state)
  end

  test "save and load round-trips entries", %{state: state} do
    entry = %{role: "user", content: "hello"}
    assert :ok = ETS.save(state, entry)
    assert {:ok, [^entry]} = ETS.load(state)
  end

  test "clear removes all entries", %{state: state} do
    ETS.save(state, %{content: "test"})
    assert :ok = ETS.clear(state)
    assert {:ok, []} = ETS.load(state)
  end
end
```

### 6.2 Hooks Tests

```elixir
# test/codex/hooks_test.exs
defmodule Codex.HooksTest do
  use ExUnit.Case

  defmodule TestHooks do
    @behaviour Codex.Hooks

    def on_agent_start(_ctx, agent) do
      send(self(), {:agent_started, agent.name})
      :ok
    end

    def on_tool_end(_ctx, _agent, tool, result) do
      send(self(), {:tool_ended, tool, result})
      :ok
    end
  end

  test "runs implemented callbacks" do
    agent = %Codex.Agent{name: "test"}
    Codex.Hooks.run(TestHooks, :on_agent_start, [%{}, agent])
    assert_received {:agent_started, "test"}
  end

  test "skips unimplemented callbacks" do
    assert :ok = Codex.Hooks.run(TestHooks, :on_llm_start, [%{}, %{}, "", []])
  end

  test "handles nil hooks" do
    assert :ok = Codex.Hooks.run(nil, :on_agent_start, [%{}, %{}])
  end
end
```

---

## 7. DOCUMENTATION UPDATES

### 7.1 Update README

Add sections for:
- Session backend options
- Lifecycle hooks usage
- Hosted tool configuration
- Image input examples

### 7.2 Add Module Docs

Each new module should have:
- `@moduledoc` with usage examples
- `@doc` for public functions
- Typespecs for all public functions

### 7.3 Add to Examples

Create new example files:
- `examples/session_persistence.exs`
- `examples/lifecycle_hooks.exs`
- `examples/hosted_tools_config.exs`
- `examples/image_input.exs`

---

## 8. DEPENDENCY UPDATES

### 8.1 Optional Dependencies

Add to `mix.exs`:

```elixir
defp deps do
  [
    # ... existing deps ...

    # Optional session backends
    {:redix, "~> 1.2", optional: true},
    {:ecto_sql, "~> 3.10", optional: true},
    {:postgrex, "~> 0.17", optional: true},

    # Optional realtime support
    {:websockex, "~> 0.4", optional: true},
    # or
    {:mint_web_socket, "~> 1.0", optional: true}
  ]
end
```

### 8.2 Feature Flags

Add compile-time feature detection:

```elixir
# lib/codex/features.ex
defmodule Codex.Features do
  @moduledoc false

  def redis_available? do
    Code.ensure_loaded?(Redix)
  end

  def ecto_available? do
    Code.ensure_loaded?(Ecto)
  end

  def websocket_available? do
    Code.ensure_loaded?(WebSockex) or Code.ensure_loaded?(Mint.WebSocket)
  end
end
```

---

This implementation guide provides concrete code examples and patterns for implementing the identified gaps. Each section can be tackled independently based on priority.

---

## Review Notes

- Date: 2025-12-14
- Summary: Corrected recommendations that conflicted with the current Elixir implementation; implemented the highest-impact item (Codex CLI env/flag forwarding) and left remaining work as lifecycle hook wiring + concrete hosted-tool engines (diff/computer/search implementations).
- Confidence: High for the forwarded CLI items; Medium for future recommendations.
