defmodule Codex.Events do
  @moduledoc """
  Typed event structs emitted during Codex turn execution.

  Provides helpers to parse JSON-decoded maps into strongly typed structs and to
  convert structs back into protocol maps for encoding.
  """

  alias Codex.Items

  defmodule ThreadStarted do
    @moduledoc """
    Event emitted when a thread is first created.
    """

    @enforce_keys [:thread_id]
    defstruct thread_id: nil, metadata: %{}

    @type t :: %__MODULE__{
            thread_id: String.t(),
            metadata: map()
          }
  end

  defmodule TurnStarted do
    @moduledoc """
    Event emitted when a new turn starts.
    """

    defstruct turn_id: nil, thread_id: nil

    @type t :: %__MODULE__{
            turn_id: String.t() | nil,
            thread_id: String.t() | nil
          }
  end

  defmodule TurnContinuation do
    @moduledoc """
    Signals that a continuation token is available for resuming the turn.
    """

    @enforce_keys [:thread_id, :turn_id, :continuation_token]
    defstruct thread_id: nil,
              turn_id: nil,
              continuation_token: nil,
              retryable: true,
              reason: nil

    @type t :: %__MODULE__{
            thread_id: String.t(),
            turn_id: String.t(),
            continuation_token: String.t(),
            retryable: boolean(),
            reason: String.t() | nil
          }
  end

  defmodule TurnCompleted do
    @moduledoc """
    Final event for a turn, optionally carrying final response and usage data.
    """

    defstruct thread_id: nil,
              turn_id: nil,
              response_id: nil,
              final_response: nil,
              usage: nil,
              status: nil,
              error: nil

    @type t :: %__MODULE__{
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            response_id: String.t() | nil,
            final_response: Items.AgentMessage.t() | map() | nil,
            usage: map() | nil,
            status: String.t() | nil,
            error: map() | nil
          }
  end

  defmodule ThreadTokenUsageUpdated do
    @moduledoc """
    Incremental token usage update emitted while a turn is in flight.
    """

    @enforce_keys [:usage]
    defstruct thread_id: nil, turn_id: nil, usage: %{}, delta: nil

    @type t :: %__MODULE__{
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            usage: map(),
            delta: map() | nil
          }
  end

  defmodule TurnDiffUpdated do
    @moduledoc """
    Event emitted when the app-server publishes a turn diff update.
    """

    @enforce_keys [:diff]
    defstruct thread_id: nil, turn_id: nil, diff: ""

    @type t :: %__MODULE__{
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            diff: String.t() | map()
          }
  end

  defmodule TurnPlanUpdated do
    @moduledoc """
    Event emitted when the app-server publishes an updated plan for the current turn.
    """

    @enforce_keys [:plan]
    defstruct thread_id: nil, turn_id: nil, explanation: nil, plan: []

    @type plan_step_status :: :pending | :in_progress | :completed
    @type plan_step :: %{step: String.t(), status: plan_step_status()}

    @type t :: %__MODULE__{
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            explanation: String.t() | nil,
            plan: [plan_step()]
          }
  end

  defmodule CommandOutputDelta do
    @moduledoc """
    Event delta emitted while a command execution is producing output.
    """

    @enforce_keys [:item_id, :delta]
    defstruct thread_id: nil, turn_id: nil, item_id: nil, delta: ""

    @type t :: %__MODULE__{
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            item_id: String.t(),
            delta: String.t()
          }
  end

  defmodule FileChangeOutputDelta do
    @moduledoc """
    Event delta emitted while a file change stream is producing output.
    """

    @enforce_keys [:item_id, :delta]
    defstruct thread_id: nil, turn_id: nil, item_id: nil, delta: ""

    @type t :: %__MODULE__{
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            item_id: String.t(),
            delta: String.t()
          }
  end

  defmodule TerminalInteraction do
    @moduledoc """
    Event emitted when stdin is written to an interactive command execution.
    """

    @enforce_keys [:item_id]
    defstruct thread_id: nil, turn_id: nil, item_id: nil, process_id: nil, stdin: ""

    @type t :: %__MODULE__{
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            item_id: String.t(),
            process_id: String.t() | nil,
            stdin: String.t()
          }
  end

  defmodule ReasoningDelta do
    @moduledoc """
    Event delta emitted while reasoning content is streaming.
    """

    @enforce_keys [:item_id, :delta]
    defstruct thread_id: nil, turn_id: nil, item_id: nil, delta: "", content_index: nil

    @type t :: %__MODULE__{
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            item_id: String.t(),
            delta: String.t(),
            content_index: integer() | nil
          }
  end

  defmodule ReasoningSummaryDelta do
    @moduledoc """
    Event delta emitted while reasoning summary text is streaming.
    """

    @enforce_keys [:item_id, :delta]
    defstruct thread_id: nil, turn_id: nil, item_id: nil, delta: "", summary_index: nil

    @type t :: %__MODULE__{
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            item_id: String.t(),
            delta: String.t(),
            summary_index: integer() | nil
          }
  end

  defmodule ReasoningSummaryPartAdded do
    @moduledoc """
    Event emitted when a new reasoning summary part is added.
    """

    @enforce_keys [:item_id, :summary_index]
    defstruct thread_id: nil, turn_id: nil, item_id: nil, summary_index: nil

    @type t :: %__MODULE__{
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            item_id: String.t(),
            summary_index: integer()
          }
  end

  defmodule McpToolCallProgress do
    @moduledoc """
    Progress message emitted while an MCP tool call is running.
    """

    @enforce_keys [:item_id, :message]
    defstruct thread_id: nil, turn_id: nil, item_id: nil, message: ""

    @type t :: %__MODULE__{
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            item_id: String.t(),
            message: String.t()
          }
  end

  defmodule McpServerOauthLoginCompleted do
    @moduledoc """
    Event emitted when an MCP server OAuth login completes.
    """

    @enforce_keys [:name, :success]
    defstruct name: nil, success: false, error: nil

    @type t :: %__MODULE__{
            name: String.t(),
            success: boolean(),
            error: String.t() | nil
          }
  end

  defmodule AccountUpdated do
    @moduledoc """
    Event emitted when account authentication state changes.
    """

    defstruct auth_mode: nil

    @type t :: %__MODULE__{
            auth_mode: String.t() | nil
          }
  end

  defmodule AccountRateLimitsUpdated do
    @moduledoc """
    Event emitted when account rate limits are updated.
    """

    @enforce_keys [:rate_limits]
    defstruct rate_limits: %{}

    @type t :: %__MODULE__{
            rate_limits: map()
          }
  end

  defmodule AccountLoginCompleted do
    @moduledoc """
    Event emitted when account login completes.
    """

    @enforce_keys [:success]
    defstruct login_id: nil, success: false, error: nil

    @type t :: %__MODULE__{
            login_id: String.t() | nil,
            success: boolean(),
            error: String.t() | nil
          }
  end

  defmodule WindowsWorldWritableWarning do
    @moduledoc """
    Event emitted when world-writable Windows paths are detected.
    """

    @enforce_keys [:sample_paths, :extra_count, :failed_scan]
    defstruct sample_paths: [], extra_count: 0, failed_scan: false

    @type t :: %__MODULE__{
            sample_paths: [String.t()],
            extra_count: non_neg_integer(),
            failed_scan: boolean()
          }
  end

  defmodule AppServerNotification do
    @moduledoc """
    Lossless wrapper for an app-server notification that is not yet mapped into a typed event.
    """

    @enforce_keys [:method]
    defstruct method: nil, params: %{}

    @type t :: %__MODULE__{
            method: String.t(),
            params: map()
          }
  end

  defmodule TurnCompaction do
    @moduledoc """
    Signals that Codex compacted a turn's history.
    """

    @enforce_keys [:compaction, :stage]
    defstruct thread_id: nil, turn_id: nil, compaction: %{}, stage: nil

    @type stage :: :started | :completed | :failed | :unknown | String.t()

    @type t :: %__MODULE__{
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            compaction: map(),
            stage: stage()
          }
  end

  defmodule ItemAgentMessageDelta do
    @moduledoc """
    Event delta emitted when the agent produces message content.
    """

    @enforce_keys [:item]
    defstruct item: %{}, thread_id: nil, turn_id: nil

    @type t :: %__MODULE__{
            item: map(),
            thread_id: String.t() | nil,
            turn_id: String.t() | nil
          }
  end

  defmodule ItemInputTextDelta do
    @moduledoc """
    Event delta emitted for user input text items.
    """

    @enforce_keys [:item]
    defstruct item: %{}, thread_id: nil, turn_id: nil

    @type t :: %__MODULE__{
            item: map(),
            thread_id: String.t() | nil,
            turn_id: String.t() | nil
          }
  end

  defmodule ItemCompleted do
    @moduledoc """
    Event emitted when an item completes.
    """

    @enforce_keys [:item]
    defstruct item: nil, thread_id: nil, turn_id: nil

    @type t :: %__MODULE__{
            item: Items.t(),
            thread_id: String.t() | nil,
            turn_id: String.t() | nil
          }
  end

  defmodule ItemStarted do
    @moduledoc """
    Event emitted when an item begins processing.
    """

    @enforce_keys [:item]
    defstruct item: nil, thread_id: nil, turn_id: nil

    @type t :: %__MODULE__{
            item: Items.t(),
            thread_id: String.t() | nil,
            turn_id: String.t() | nil
          }
  end

  defmodule ItemUpdated do
    @moduledoc """
    Event emitted when an in-progress item receives an update.
    """

    @enforce_keys [:item]
    defstruct item: nil, thread_id: nil, turn_id: nil

    @type t :: %__MODULE__{
            item: Items.t(),
            thread_id: String.t() | nil,
            turn_id: String.t() | nil
          }
  end

  defmodule Error do
    @moduledoc """
    General error event emitted by the CLI.
    """

    @enforce_keys [:message]
    defstruct message: nil,
              thread_id: nil,
              turn_id: nil,
              additional_details: nil,
              codex_error_info: nil,
              will_retry: nil

    @type t :: %__MODULE__{
            message: String.t(),
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            additional_details: String.t() | nil,
            codex_error_info: map() | nil,
            will_retry: boolean() | nil
          }
  end

  defmodule TurnFailed do
    @moduledoc """
    Event emitted when a turn fails.
    """

    @enforce_keys [:error]
    defstruct error: %{}, thread_id: nil, turn_id: nil

    @type t :: %__MODULE__{
            error: map(),
            thread_id: String.t() | nil,
            turn_id: String.t() | nil
          }
  end

  defmodule ToolCallRequested do
    @moduledoc """
    Indicates Codex requires a tool invocation to continue auto-run.
    """

    @enforce_keys [:thread_id, :turn_id, :call_id, :tool_name, :arguments]
    defstruct thread_id: nil,
              turn_id: nil,
              call_id: nil,
              tool_name: nil,
              arguments: %{},
              requires_approval: false,
              approved: nil,
              approved_by_policy: nil,
              sandbox_warnings: nil,
              capabilities: nil

    @type t :: %__MODULE__{
            thread_id: String.t(),
            turn_id: String.t(),
            call_id: String.t(),
            tool_name: String.t(),
            arguments: map() | list() | String.t(),
            requires_approval: boolean(),
            approved: boolean() | nil,
            approved_by_policy: boolean() | nil,
            sandbox_warnings: [String.t()] | nil,
            capabilities: map() | nil
          }
  end

  defmodule ToolCallCompleted do
    @moduledoc """
    Event emitted when a tool call has completed and returned output.
    """

    @enforce_keys [:thread_id, :turn_id, :call_id, :tool_name, :output]
    defstruct thread_id: nil,
              turn_id: nil,
              call_id: nil,
              tool_name: nil,
              output: %{}

    @type t :: %__MODULE__{
            thread_id: String.t(),
            turn_id: String.t(),
            call_id: String.t(),
            tool_name: String.t(),
            output: map()
          }
  end

  alias __MODULE__.{
    ItemAgentMessageDelta,
    ItemInputTextDelta,
    ThreadStarted,
    TurnCompleted,
    ThreadTokenUsageUpdated,
    TurnCompaction,
    TurnContinuation,
    TurnDiffUpdated,
    TurnPlanUpdated,
    TurnStarted,
    ToolCallCompleted,
    ToolCallRequested,
    ItemCompleted,
    ItemStarted,
    ItemUpdated,
    CommandOutputDelta,
    FileChangeOutputDelta,
    TerminalInteraction,
    ReasoningDelta,
    ReasoningSummaryDelta,
    ReasoningSummaryPartAdded,
    AppServerNotification,
    McpToolCallProgress,
    McpServerOauthLoginCompleted,
    AccountUpdated,
    AccountRateLimitsUpdated,
    AccountLoginCompleted,
    WindowsWorldWritableWarning,
    Error,
    TurnFailed
  }

  @type t ::
          ThreadStarted.t()
          | TurnStarted.t()
          | TurnContinuation.t()
          | TurnCompleted.t()
          | ThreadTokenUsageUpdated.t()
          | TurnDiffUpdated.t()
          | TurnPlanUpdated.t()
          | TurnCompaction.t()
          | ItemAgentMessageDelta.t()
          | ItemInputTextDelta.t()
          | ItemCompleted.t()
          | ItemStarted.t()
          | ItemUpdated.t()
          | CommandOutputDelta.t()
          | FileChangeOutputDelta.t()
          | TerminalInteraction.t()
          | ReasoningDelta.t()
          | ReasoningSummaryDelta.t()
          | ReasoningSummaryPartAdded.t()
          | AppServerNotification.t()
          | McpToolCallProgress.t()
          | McpServerOauthLoginCompleted.t()
          | AccountUpdated.t()
          | AccountRateLimitsUpdated.t()
          | AccountLoginCompleted.t()
          | WindowsWorldWritableWarning.t()
          | Error.t()
          | TurnFailed.t()
          | ToolCallRequested.t()
          | ToolCallCompleted.t()

  @compaction_stage_map %{
    "started" => :started,
    "completed" => :completed,
    "failed" => :failed
  }

  @doc """
  Parses a JSON-decoded map into a typed event struct, raising on unknown event types.
  """
  @spec parse!(map()) :: t()
  def parse!(%{"type" => "thread.started"} = map) do
    %ThreadStarted{
      thread_id: Map.get(map, "thread_id"),
      metadata: Map.get(map, "metadata", %{})
    }
  end

  def parse!(%{"type" => "turn.started"} = map) do
    %TurnStarted{
      turn_id: Map.get(map, "turn_id"),
      thread_id: Map.get(map, "thread_id")
    }
  end

  def parse!(%{"type" => "turn.continuation"} = map) do
    %TurnContinuation{
      thread_id: Map.fetch!(map, "thread_id"),
      turn_id: Map.fetch!(map, "turn_id"),
      continuation_token: Map.fetch!(map, "continuation_token"),
      retryable: Map.get(map, "retryable", false),
      reason: Map.get(map, "reason")
    }
  end

  def parse!(%{"type" => "turn.completed"} = map) do
    %TurnCompleted{
      thread_id: Map.get(map, "thread_id"),
      turn_id: Map.get(map, "turn_id"),
      response_id: Map.get(map, "response_id"),
      final_response: Map.get(map, "final_response"),
      usage: Map.get(map, "usage"),
      status: Map.get(map, "status"),
      error: Map.get(map, "error")
    }
  end

  def parse!(%{"type" => type} = map)
      when type in ["thread.tokenUsage.updated", "thread/tokenUsage/updated"] do
    %ThreadTokenUsageUpdated{
      thread_id: Map.get(map, "thread_id"),
      turn_id: Map.get(map, "turn_id"),
      usage: Map.get(map, "usage") || Map.get(map, "token_usage") || %{},
      delta: Map.get(map, "delta") || Map.get(map, "usage_delta")
    }
  end

  def parse!(%{"type" => type} = map) when type in ["turn.diff.updated", "turn/diff/updated"] do
    %TurnDiffUpdated{
      thread_id: Map.get(map, "thread_id"),
      turn_id: Map.get(map, "turn_id"),
      diff: Map.get(map, "diff") || Map.get(map, "delta") || ""
    }
  end

  def parse!(%{"type" => type} = map) when type in ["turn.plan.updated", "turn/plan/updated"] do
    %TurnPlanUpdated{
      thread_id: Map.get(map, "thread_id"),
      turn_id: Map.get(map, "turn_id"),
      explanation: Map.get(map, "explanation"),
      plan: Map.get(map, "plan") || []
    }
  end

  def parse!(%{"type" => <<"turn.compaction", _rest::binary>>} = map), do: parse_compaction(map)
  def parse!(%{"type" => <<"turn/compaction", _rest::binary>>} = map), do: parse_compaction(map)

  def parse!(%{"type" => "item.agent_message.delta"} = map) do
    %ItemAgentMessageDelta{
      item: Map.fetch!(map, "item"),
      thread_id: Map.get(map, "thread_id"),
      turn_id: Map.get(map, "turn_id")
    }
  end

  def parse!(%{"type" => "item.input_text.delta"} = map) do
    %ItemInputTextDelta{
      item: Map.fetch!(map, "item"),
      thread_id: Map.get(map, "thread_id"),
      turn_id: Map.get(map, "turn_id")
    }
  end

  def parse!(%{"type" => "item.completed"} = map) do
    %ItemCompleted{
      item: map |> Map.fetch!("item") |> Items.parse!(),
      thread_id: Map.get(map, "thread_id"),
      turn_id: Map.get(map, "turn_id")
    }
  end

  def parse!(%{"type" => "item.started"} = map) do
    %ItemStarted{
      item: map |> Map.fetch!("item") |> Items.parse!(),
      thread_id: Map.get(map, "thread_id"),
      turn_id: Map.get(map, "turn_id")
    }
  end

  def parse!(%{"type" => "item.updated"} = map) do
    %ItemUpdated{
      item: map |> Map.fetch!("item") |> Items.parse!(),
      thread_id: Map.get(map, "thread_id"),
      turn_id: Map.get(map, "turn_id")
    }
  end

  def parse!(%{"type" => "error"} = map) do
    %Error{
      message: Map.get(map, "message"),
      thread_id: Map.get(map, "thread_id"),
      turn_id: Map.get(map, "turn_id"),
      additional_details: Map.get(map, "additional_details") || Map.get(map, "additionalDetails"),
      codex_error_info: Map.get(map, "codex_error_info") || Map.get(map, "codexErrorInfo"),
      will_retry: Map.get(map, "will_retry") || Map.get(map, "willRetry")
    }
  end

  def parse!(%{"type" => "turn.failed"} = map) do
    %TurnFailed{
      error: Map.get(map, "error", %{}),
      thread_id: Map.get(map, "thread_id"),
      turn_id: Map.get(map, "turn_id")
    }
  end

  def parse!(%{"type" => "tool.call.required"} = map) do
    %ToolCallRequested{
      thread_id: Map.fetch!(map, "thread_id"),
      turn_id: Map.fetch!(map, "turn_id"),
      call_id: Map.fetch!(map, "call_id"),
      tool_name: Map.fetch!(map, "tool_name"),
      arguments: Map.get(map, "arguments", %{}),
      requires_approval: Map.get(map, "requires_approval", false),
      approved: Map.get(map, "approved"),
      approved_by_policy: Map.get(map, "approved_by_policy"),
      sandbox_warnings: Map.get(map, "sandbox_warnings") || Map.get(map, "warnings"),
      capabilities: Map.get(map, "capabilities")
    }
  end

  def parse!(%{"type" => "tool.call.completed"} = map) do
    %ToolCallCompleted{
      thread_id: Map.fetch!(map, "thread_id"),
      turn_id: Map.fetch!(map, "turn_id"),
      call_id: Map.fetch!(map, "call_id"),
      tool_name: Map.fetch!(map, "tool_name"),
      output: Map.get(map, "output", %{})
    }
  end

  def parse!(%{"type" => unknown}) do
    raise ArgumentError, "unsupported codex event #{inspect(unknown)}"
  end

  def parse!(other) do
    raise ArgumentError, "expected codex event map, got: #{inspect(other)}"
  end

  @doc """
  Converts a typed event struct back into the JSON-serializable map representation.
  """
  @spec to_map(t()) :: map()
  def to_map(%ThreadStarted{} = event) do
    %{
      "type" => "thread.started",
      "thread_id" => event.thread_id
    }
    |> put_optional("metadata", event.metadata)
  end

  def to_map(%TurnStarted{} = event) do
    %{
      "type" => "turn.started",
      "turn_id" => event.turn_id,
      "thread_id" => event.thread_id
    }
  end

  def to_map(%TurnContinuation{} = event) do
    %{
      "type" => "turn.continuation",
      "thread_id" => event.thread_id,
      "turn_id" => event.turn_id,
      "continuation_token" => event.continuation_token,
      "retryable" => event.retryable
    }
    |> put_optional("reason", event.reason)
  end

  def to_map(%TurnCompleted{} = event) do
    %{
      "type" => "turn.completed",
      "thread_id" => event.thread_id,
      "turn_id" => event.turn_id
    }
    |> put_optional("response_id", event.response_id)
    |> put_optional("final_response", encode_final_response(event.final_response))
    |> put_optional("usage", event.usage)
    |> put_optional("status", event.status)
    |> put_optional("error", event.error)
  end

  def to_map(%ThreadTokenUsageUpdated{} = event) do
    %{
      "type" => "thread/tokenUsage/updated"
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
    |> put_optional("usage", event.usage)
    |> put_optional("delta", event.delta)
  end

  def to_map(%TurnDiffUpdated{} = event) do
    %{
      "type" => "turn/diff/updated"
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
    |> put_optional("diff", event.diff)
  end

  def to_map(%TurnPlanUpdated{} = event) do
    %{
      "type" => "turn/plan/updated"
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
    |> put_optional("explanation", event.explanation)
    |> put_optional("plan", event.plan)
  end

  def to_map(%TurnCompaction{} = event) do
    %{
      "type" => build_compaction_type(event.stage)
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
    |> put_optional("compaction", event.compaction)
  end

  def to_map(%ItemAgentMessageDelta{} = event) do
    %{
      "type" => "item.agent_message.delta",
      "item" => event.item
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
  end

  def to_map(%ItemInputTextDelta{} = event) do
    %{
      "type" => "item.input_text.delta",
      "item" => event.item
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
  end

  def to_map(%ItemCompleted{} = event) do
    %{
      "type" => "item.completed",
      "item" => Items.to_map(event.item)
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
  end

  def to_map(%ItemStarted{} = event) do
    %{
      "type" => "item.started",
      "item" => Items.to_map(event.item)
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
  end

  def to_map(%ItemUpdated{} = event) do
    %{
      "type" => "item.updated",
      "item" => Items.to_map(event.item)
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
  end

  def to_map(%CommandOutputDelta{} = event) do
    %{
      "type" => "item/commandExecution/outputDelta",
      "item_id" => event.item_id,
      "delta" => event.delta
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
  end

  def to_map(%FileChangeOutputDelta{} = event) do
    %{
      "type" => "item/fileChange/outputDelta",
      "item_id" => event.item_id,
      "delta" => event.delta
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
  end

  def to_map(%TerminalInteraction{} = event) do
    %{
      "type" => "item/commandExecution/terminalInteraction",
      "item_id" => event.item_id,
      "process_id" => event.process_id,
      "stdin" => event.stdin
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
  end

  def to_map(%ReasoningDelta{} = event) do
    %{
      "type" => "item/reasoning/textDelta",
      "item_id" => event.item_id,
      "delta" => event.delta
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
    |> put_optional("content_index", event.content_index)
  end

  def to_map(%ReasoningSummaryDelta{} = event) do
    %{
      "type" => "item/reasoning/summaryTextDelta",
      "item_id" => event.item_id,
      "delta" => event.delta
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
    |> put_optional("summary_index", event.summary_index)
  end

  def to_map(%ReasoningSummaryPartAdded{} = event) do
    %{
      "type" => "item/reasoning/summaryPartAdded",
      "item_id" => event.item_id
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
    |> put_optional("summary_index", event.summary_index)
  end

  def to_map(%McpToolCallProgress{} = event) do
    %{
      "type" => "item/mcpToolCall/progress",
      "item_id" => event.item_id,
      "message" => event.message
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
  end

  def to_map(%McpServerOauthLoginCompleted{} = event) do
    %{
      "type" => "mcpServer/oauthLogin/completed",
      "name" => event.name,
      "success" => event.success
    }
    |> put_optional("error", event.error)
  end

  def to_map(%AccountUpdated{} = event) do
    %{
      "type" => "account/updated"
    }
    |> put_optional("auth_mode", event.auth_mode)
  end

  def to_map(%AccountRateLimitsUpdated{} = event) do
    %{
      "type" => "account/rateLimits/updated",
      "rate_limits" => event.rate_limits
    }
  end

  def to_map(%AccountLoginCompleted{} = event) do
    %{
      "type" => "account/login/completed",
      "success" => event.success
    }
    |> put_optional("login_id", event.login_id)
    |> put_optional("error", event.error)
  end

  def to_map(%WindowsWorldWritableWarning{} = event) do
    %{
      "type" => "windows/worldWritableWarning",
      "sample_paths" => event.sample_paths,
      "extra_count" => event.extra_count,
      "failed_scan" => event.failed_scan
    }
  end

  def to_map(%Error{} = event) do
    %{
      "type" => "error",
      "message" => event.message
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
    |> put_optional("additional_details", event.additional_details)
    |> put_optional("codex_error_info", event.codex_error_info)
    |> put_optional("will_retry", event.will_retry)
  end

  def to_map(%TurnFailed{} = event) do
    %{
      "type" => "turn.failed",
      "error" => event.error
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
  end

  def to_map(%ToolCallRequested{} = event) do
    %{
      "type" => "tool.call.required",
      "thread_id" => event.thread_id,
      "turn_id" => event.turn_id,
      "call_id" => event.call_id,
      "tool_name" => event.tool_name,
      "arguments" => event.arguments,
      "requires_approval" => event.requires_approval
    }
    |> put_optional("approved", event.approved)
    |> put_optional("approved_by_policy", event.approved_by_policy)
    |> put_optional("sandbox_warnings", event.sandbox_warnings)
    |> put_optional("capabilities", event.capabilities)
  end

  def to_map(%ToolCallCompleted{} = event) do
    %{
      "type" => "tool.call.completed",
      "thread_id" => event.thread_id,
      "turn_id" => event.turn_id,
      "call_id" => event.call_id,
      "tool_name" => event.tool_name,
      "output" => event.output
    }
  end

  defp parse_compaction(map) do
    %TurnCompaction{
      thread_id: Map.get(map, "thread_id"),
      turn_id: Map.get(map, "turn_id"),
      compaction: Map.get(map, "compaction", %{}),
      stage: map |> Map.fetch!("type") |> parse_compaction_stage()
    }
  end

  defp parse_compaction_stage(type) do
    type
    |> String.split([".", "/"], trim: true)
    |> List.last()
    |> then(&Map.get(@compaction_stage_map, &1, &1 || :unknown))
  end

  defp build_compaction_type(stage) do
    case stage_to_string(stage) do
      nil -> "turn/compaction"
      stage_string -> "turn/compaction/#{stage_string}"
    end
  end

  defp stage_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp stage_to_string(value) when is_binary(value), do: value
  defp stage_to_string(_), do: nil

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp encode_final_response(%Items.AgentMessage{text: text}) when is_binary(text) do
    %{"type" => "text", "text" => text}
  end

  defp encode_final_response(%Items.AgentMessage{}), do: %{"type" => "text"}
  defp encode_final_response(other), do: other
end
