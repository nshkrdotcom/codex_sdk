defmodule Codex.Events do
  @moduledoc """
  Typed event structs emitted during Codex turn execution.

  Provides helpers to parse JSON-decoded maps into strongly typed structs and to
  convert structs back into protocol maps for encoding.
  """

  alias Codex.Items
  alias Codex.Protocol.RateLimit.Snapshot, as: RateLimitSnapshot
  alias Codex.Protocol.RequestUserInput.Question, as: RequestUserInputQuestion

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
    defstruct thread_id: nil, turn_id: nil, usage: %{}, delta: nil, rate_limits: nil

    @type t :: %__MODULE__{
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            usage: map(),
            delta: map() | nil,
            rate_limits: Codex.Protocol.RateLimit.Snapshot.t() | map() | nil
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

    Contains current rate limit information from the API, including
    limits, remaining quota, and reset times.
    """

    @enforce_keys [:rate_limits]
    defstruct rate_limits: %{}, thread_id: nil, turn_id: nil

    @type t :: %__MODULE__{
            rate_limits: Codex.Protocol.RateLimit.Snapshot.t() | map(),
            thread_id: String.t() | nil,
            turn_id: String.t() | nil
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

  defmodule DeprecationNotice do
    @moduledoc """
    Event emitted when the server reports a deprecated feature or behavior.
    """

    @enforce_keys [:summary]
    defstruct summary: nil, details: nil

    @type t :: %__MODULE__{
            summary: String.t(),
            details: String.t() | nil
          }
  end

  defmodule RawResponseItemCompleted do
    @moduledoc """
    Event emitted when a raw response item completes on the app-server stream.
    """

    @enforce_keys [:item]
    defstruct thread_id: nil, turn_id: nil, item: nil

    @type t :: %__MODULE__{
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            item: Items.t() | map()
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

  defmodule SessionConfigured do
    @moduledoc """
    Event emitted when a session is configured.
    """

    defstruct session_id: nil,
              forked_from_id: nil,
              model: nil,
              model_provider_id: nil,
              approval_policy: nil,
              sandbox_policy: nil,
              cwd: nil,
              reasoning_effort: nil,
              history_log_id: nil,
              history_entry_count: nil,
              initial_messages: nil,
              rollout_path: nil

    @type t :: %__MODULE__{
            session_id: String.t() | nil,
            forked_from_id: String.t() | nil,
            model: String.t() | nil,
            model_provider_id: String.t() | nil,
            approval_policy: term(),
            sandbox_policy: term(),
            cwd: String.t() | nil,
            reasoning_effort: String.t() | atom() | nil,
            history_log_id: non_neg_integer() | nil,
            history_entry_count: non_neg_integer() | nil,
            initial_messages: list() | nil,
            rollout_path: String.t() | nil
          }
  end

  defmodule Warning do
    @moduledoc """
    Warning event emitted during a turn.
    """

    @enforce_keys [:message]
    defstruct message: nil

    @type t :: %__MODULE__{
            message: String.t()
          }
  end

  defmodule ContextCompacted do
    @moduledoc """
    Indicates that the conversation context was compacted.
    """

    defstruct removed_turns: nil, remaining_turns: nil

    @type t :: %__MODULE__{
            removed_turns: non_neg_integer() | nil,
            remaining_turns: non_neg_integer() | nil
          }
  end

  defmodule ThreadRolledBack do
    @moduledoc """
    Indicates that recent user turns were removed from context.
    """

    defstruct num_turns: nil

    @type t :: %__MODULE__{
            num_turns: non_neg_integer() | nil
          }
  end

  defmodule RequestUserInput do
    @moduledoc """
    Event emitted when the agent requests user input.
    """

    defstruct id: nil, turn_id: nil, questions: []

    @type t :: %__MODULE__{
            id: String.t() | nil,
            turn_id: String.t() | nil,
            questions: list()
          }
  end

  defmodule McpStartupUpdate do
    @moduledoc """
    Incremental status update for MCP server startup.
    """

    defstruct server_name: nil, status: nil, message: nil

    @type t :: %__MODULE__{
            server_name: String.t() | nil,
            status: String.t() | map() | atom() | nil,
            message: String.t() | nil
          }
  end

  defmodule McpStartupComplete do
    @moduledoc """
    Summary of MCP server startup completion.
    """

    defstruct servers: nil

    @type t :: %__MODULE__{
            servers: map() | list() | nil
          }
  end

  defmodule ElicitationRequest do
    @moduledoc """
    Event emitted for MCP elicitation requests.
    """

    defstruct server_name: nil, id: nil, message: nil

    @type t :: %__MODULE__{
            server_name: String.t() | nil,
            id: String.t() | nil,
            message: String.t() | nil
          }
  end

  defmodule UndoStarted do
    @moduledoc """
    Event emitted when an undo operation begins.
    """

    defstruct turn_id: nil, message: nil

    @type t :: %__MODULE__{
            turn_id: String.t() | nil,
            message: String.t() | nil
          }
  end

  defmodule UndoCompleted do
    @moduledoc """
    Event emitted when an undo operation completes.
    """

    defstruct turn_id: nil, success: nil, message: nil

    @type t :: %__MODULE__{
            turn_id: String.t() | nil,
            success: boolean() | nil,
            message: String.t() | nil
          }
  end

  defmodule TurnAborted do
    @moduledoc """
    Event emitted when a turn is aborted.
    """

    defstruct turn_id: nil, reason: nil

    @type t :: %__MODULE__{
            turn_id: String.t() | nil,
            reason: String.t() | atom() | map() | nil
          }
  end

  defmodule ShutdownComplete do
    @moduledoc """
    Event emitted when the agent shuts down.
    """

    defstruct []

    @type t :: %__MODULE__{}
  end

  defmodule EnteredReviewMode do
    @moduledoc """
    Event emitted when a review session starts.
    """

    defstruct review_request: nil

    @type t :: %__MODULE__{
            review_request: map() | nil
          }
  end

  defmodule ExitedReviewMode do
    @moduledoc """
    Event emitted when a review session ends.
    """

    defstruct result: nil

    @type t :: %__MODULE__{
            result: map() | nil
          }
  end

  defmodule ConfigWarning do
    @moduledoc """
    Event emitted when configuration warnings are reported.
    """

    @enforce_keys [:summary]
    defstruct summary: nil, details: nil

    @type t :: %__MODULE__{
            summary: String.t(),
            details: String.t() | nil
          }
  end

  defmodule CollabAgentSpawnBegin do
    @moduledoc """
    Collab event emitted when an agent spawn starts.
    """

    defstruct call_id: nil, sender_thread_id: nil, prompt: nil

    @type t :: %__MODULE__{
            call_id: String.t() | nil,
            sender_thread_id: String.t() | nil,
            prompt: String.t() | nil
          }
  end

  defmodule CollabAgentSpawnEnd do
    @moduledoc """
    Collab event emitted when an agent spawn completes.
    """

    defstruct call_id: nil, sender_thread_id: nil, new_thread_id: nil, prompt: nil, status: nil

    @type t :: %__MODULE__{
            call_id: String.t() | nil,
            sender_thread_id: String.t() | nil,
            new_thread_id: String.t() | nil,
            prompt: String.t() | nil,
            status: map() | String.t() | atom() | nil
          }
  end

  defmodule CollabAgentInteractionBegin do
    @moduledoc """
    Collab event emitted when an agent interaction starts.
    """

    defstruct call_id: nil, sender_thread_id: nil, receiver_thread_id: nil, prompt: nil

    @type t :: %__MODULE__{
            call_id: String.t() | nil,
            sender_thread_id: String.t() | nil,
            receiver_thread_id: String.t() | nil,
            prompt: String.t() | nil
          }
  end

  defmodule CollabAgentInteractionEnd do
    @moduledoc """
    Collab event emitted when an agent interaction completes.
    """

    defstruct call_id: nil,
              sender_thread_id: nil,
              receiver_thread_id: nil,
              prompt: nil,
              status: nil

    @type t :: %__MODULE__{
            call_id: String.t() | nil,
            sender_thread_id: String.t() | nil,
            receiver_thread_id: String.t() | nil,
            prompt: String.t() | nil,
            status: map() | String.t() | atom() | nil
          }
  end

  defmodule CollabWaitingBegin do
    @moduledoc """
    Collab event emitted when an agent begins waiting.
    """

    defstruct sender_thread_id: nil, receiver_thread_ids: [], call_id: nil

    @type t :: %__MODULE__{
            sender_thread_id: String.t() | nil,
            receiver_thread_ids: [String.t()],
            call_id: String.t() | nil
          }
  end

  defmodule CollabWaitingEnd do
    @moduledoc """
    Collab event emitted when an agent stops waiting.
    """

    defstruct sender_thread_id: nil, call_id: nil, statuses: nil

    @type t :: %__MODULE__{
            sender_thread_id: String.t() | nil,
            call_id: String.t() | nil,
            statuses: map() | nil
          }
  end

  defmodule CollabCloseBegin do
    @moduledoc """
    Collab event emitted when a collab session begins closing.
    """

    defstruct call_id: nil, sender_thread_id: nil, receiver_thread_id: nil

    @type t :: %__MODULE__{
            call_id: String.t() | nil,
            sender_thread_id: String.t() | nil,
            receiver_thread_id: String.t() | nil
          }
  end

  defmodule CollabCloseEnd do
    @moduledoc """
    Collab event emitted when a collab session closes.
    """

    defstruct call_id: nil, sender_thread_id: nil, receiver_thread_id: nil, status: nil

    @type t :: %__MODULE__{
            call_id: String.t() | nil,
            sender_thread_id: String.t() | nil,
            receiver_thread_id: String.t() | nil,
            status: map() | String.t() | atom() | nil
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
    DeprecationNotice,
    RawResponseItemCompleted,
    Error,
    TurnFailed,
    SessionConfigured,
    Warning,
    ContextCompacted,
    ThreadRolledBack,
    RequestUserInput,
    McpStartupUpdate,
    McpStartupComplete,
    ElicitationRequest,
    UndoStarted,
    UndoCompleted,
    TurnAborted,
    ShutdownComplete,
    EnteredReviewMode,
    ExitedReviewMode,
    ConfigWarning,
    CollabAgentSpawnBegin,
    CollabAgentSpawnEnd,
    CollabAgentInteractionBegin,
    CollabAgentInteractionEnd,
    CollabWaitingBegin,
    CollabWaitingEnd,
    CollabCloseBegin,
    CollabCloseEnd
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
          | DeprecationNotice.t()
          | RawResponseItemCompleted.t()
          | Error.t()
          | TurnFailed.t()
          | ToolCallRequested.t()
          | ToolCallCompleted.t()
          | SessionConfigured.t()
          | Warning.t()
          | ContextCompacted.t()
          | ThreadRolledBack.t()
          | RequestUserInput.t()
          | McpStartupUpdate.t()
          | McpStartupComplete.t()
          | ElicitationRequest.t()
          | UndoStarted.t()
          | UndoCompleted.t()
          | TurnAborted.t()
          | ShutdownComplete.t()
          | EnteredReviewMode.t()
          | ExitedReviewMode.t()
          | ConfigWarning.t()
          | CollabAgentSpawnBegin.t()
          | CollabAgentSpawnEnd.t()
          | CollabAgentInteractionBegin.t()
          | CollabAgentInteractionEnd.t()
          | CollabWaitingBegin.t()
          | CollabWaitingEnd.t()
          | CollabCloseBegin.t()
          | CollabCloseEnd.t()

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

  def parse!(%{"type" => type} = map) when type in ["session_configured", "sessionConfigured"] do
    parse_session_configured(map)
  end

  def parse!(%{"type" => type} = map) when type in ["warning", "Warning"] do
    %Warning{
      message: Map.get(map, "message") || ""
    }
  end

  def parse!(%{"type" => type} = map) when type in ["context_compacted", "contextCompacted"] do
    %ContextCompacted{
      removed_turns: Map.get(map, "removed_turns") || Map.get(map, "removedTurns"),
      remaining_turns: Map.get(map, "remaining_turns") || Map.get(map, "remainingTurns")
    }
  end

  def parse!(%{"type" => type} = map) when type in ["thread_rolled_back", "threadRolledBack"] do
    %ThreadRolledBack{
      num_turns: Map.get(map, "num_turns") || Map.get(map, "numTurns")
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
    rate_limits =
      map
      |> Map.get("rate_limits")
      |> case do
        nil -> Map.get(map, "rateLimits")
        value -> value
      end
      |> parse_rate_limits()

    %ThreadTokenUsageUpdated{
      thread_id: Map.get(map, "thread_id"),
      turn_id: Map.get(map, "turn_id"),
      usage: Map.get(map, "usage") || Map.get(map, "token_usage") || %{},
      delta: Map.get(map, "delta") || Map.get(map, "usage_delta"),
      rate_limits: rate_limits
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

  def parse!(%{"type" => type} = map)
      when type in ["request_user_input", "requestUserInput"] do
    %RequestUserInput{
      id: Map.get(map, "id") || Map.get(map, "call_id") || Map.get(map, "callId"),
      turn_id: Map.get(map, "turn_id") || Map.get(map, "turnId"),
      questions:
        map
        |> Map.get("questions")
        |> parse_request_user_input_questions()
    }
  end

  def parse!(%{"type" => type} = map)
      when type in ["mcp_startup_update", "mcpStartupUpdate"] do
    {status, message} =
      map
      |> Map.get("status")
      |> normalize_mcp_startup_status()

    %McpStartupUpdate{
      server_name:
        Map.get(map, "server") ||
          Map.get(map, "server_name") ||
          Map.get(map, "serverName"),
      status: status,
      message: message || Map.get(map, "message")
    }
  end

  def parse!(%{"type" => type} = map)
      when type in ["mcp_startup_complete", "mcpStartupComplete"] do
    %McpStartupComplete{
      servers: normalize_mcp_startup_complete(map)
    }
  end

  def parse!(%{"type" => type} = map)
      when type in ["elicitation_request", "elicitationRequest"] do
    %ElicitationRequest{
      server_name:
        Map.get(map, "server_name") ||
          Map.get(map, "serverName") ||
          Map.get(map, "server"),
      id: Map.get(map, "id"),
      message: Map.get(map, "message")
    }
  end

  def parse!(%{"type" => type} = map) when type in ["undo_started", "undoStarted"] do
    %UndoStarted{
      turn_id: Map.get(map, "turn_id") || Map.get(map, "turnId"),
      message: Map.get(map, "message")
    }
  end

  def parse!(%{"type" => type} = map) when type in ["undo_completed", "undoCompleted"] do
    %UndoCompleted{
      turn_id: Map.get(map, "turn_id") || Map.get(map, "turnId"),
      success: Map.get(map, "success"),
      message: Map.get(map, "message")
    }
  end

  def parse!(%{"type" => type} = map)
      when type in ["turn_aborted", "turnAborted", "turn.aborted"] do
    %TurnAborted{
      turn_id: Map.get(map, "turn_id") || Map.get(map, "turnId"),
      reason: Map.get(map, "reason")
    }
  end

  def parse!(%{"type" => type}) when type in ["shutdown_complete", "shutdownComplete"] do
    %ShutdownComplete{}
  end

  def parse!(%{"type" => type} = map)
      when type in ["entered_review_mode", "enteredReviewMode"] do
    review_request =
      Map.get(map, "review_request") ||
        Map.get(map, "reviewRequest") ||
        Map.drop(map, ["type"])

    %EnteredReviewMode{review_request: review_request}
  end

  def parse!(%{"type" => type} = map)
      when type in ["exited_review_mode", "exitedReviewMode"] do
    result =
      Map.get(map, "review_output") ||
        Map.get(map, "reviewOutput") ||
        Map.get(map, "result") ||
        Map.drop(map, ["type"])

    %ExitedReviewMode{result: result}
  end

  def parse!(%{"type" => type} = map) when type in ["config_warning", "configWarning"] do
    %ConfigWarning{
      summary: Map.get(map, "summary") || "",
      details: Map.get(map, "details")
    }
  end

  def parse!(%{"type" => "collab_agent_spawn_begin"} = map) do
    %CollabAgentSpawnBegin{
      call_id: Map.get(map, "call_id") || Map.get(map, "callId") || Map.get(map, "id"),
      sender_thread_id: Map.get(map, "sender_thread_id") || Map.get(map, "senderThreadId"),
      prompt: Map.get(map, "prompt")
    }
  end

  def parse!(%{"type" => "collab_agent_spawn_end"} = map) do
    %CollabAgentSpawnEnd{
      call_id: Map.get(map, "call_id") || Map.get(map, "callId") || Map.get(map, "id"),
      sender_thread_id: Map.get(map, "sender_thread_id") || Map.get(map, "senderThreadId"),
      new_thread_id: Map.get(map, "new_thread_id") || Map.get(map, "newThreadId"),
      prompt: Map.get(map, "prompt"),
      status: Map.get(map, "status")
    }
  end

  def parse!(%{"type" => "collab_agent_interaction_begin"} = map) do
    %CollabAgentInteractionBegin{
      call_id: Map.get(map, "call_id") || Map.get(map, "callId") || Map.get(map, "id"),
      sender_thread_id: Map.get(map, "sender_thread_id") || Map.get(map, "senderThreadId"),
      receiver_thread_id: Map.get(map, "receiver_thread_id") || Map.get(map, "receiverThreadId"),
      prompt: Map.get(map, "prompt")
    }
  end

  def parse!(%{"type" => "collab_agent_interaction_end"} = map) do
    %CollabAgentInteractionEnd{
      call_id: Map.get(map, "call_id") || Map.get(map, "callId") || Map.get(map, "id"),
      sender_thread_id: Map.get(map, "sender_thread_id") || Map.get(map, "senderThreadId"),
      receiver_thread_id: Map.get(map, "receiver_thread_id") || Map.get(map, "receiverThreadId"),
      prompt: Map.get(map, "prompt"),
      status: Map.get(map, "status")
    }
  end

  def parse!(%{"type" => "collab_waiting_begin"} = map) do
    %CollabWaitingBegin{
      sender_thread_id: Map.get(map, "sender_thread_id") || Map.get(map, "senderThreadId"),
      receiver_thread_ids:
        Map.get(map, "receiver_thread_ids") ||
          Map.get(map, "receiverThreadIds") ||
          [],
      call_id: Map.get(map, "call_id") || Map.get(map, "callId") || Map.get(map, "id")
    }
  end

  def parse!(%{"type" => "collab_waiting_end"} = map) do
    %CollabWaitingEnd{
      sender_thread_id: Map.get(map, "sender_thread_id") || Map.get(map, "senderThreadId"),
      call_id: Map.get(map, "call_id") || Map.get(map, "callId") || Map.get(map, "id"),
      statuses: Map.get(map, "statuses")
    }
  end

  def parse!(%{"type" => "collab_close_begin"} = map) do
    %CollabCloseBegin{
      call_id: Map.get(map, "call_id") || Map.get(map, "callId") || Map.get(map, "id"),
      sender_thread_id: Map.get(map, "sender_thread_id") || Map.get(map, "senderThreadId"),
      receiver_thread_id: Map.get(map, "receiver_thread_id") || Map.get(map, "receiverThreadId")
    }
  end

  def parse!(%{"type" => "collab_close_end"} = map) do
    %CollabCloseEnd{
      call_id: Map.get(map, "call_id") || Map.get(map, "callId") || Map.get(map, "id"),
      sender_thread_id: Map.get(map, "sender_thread_id") || Map.get(map, "senderThreadId"),
      receiver_thread_id: Map.get(map, "receiver_thread_id") || Map.get(map, "receiverThreadId"),
      status: Map.get(map, "status")
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

  def parse!(%{"type" => "deprecationNotice"} = map) do
    %DeprecationNotice{
      summary: Map.get(map, "summary") || "",
      details: Map.get(map, "details")
    }
  end

  def parse!(%{"type" => "account/updated"} = map) do
    %AccountUpdated{
      auth_mode: Map.get(map, "auth_mode") || Map.get(map, "authMode")
    }
  end

  def parse!(%{"type" => "account/login/completed"} = map) do
    %AccountLoginCompleted{
      login_id: Map.get(map, "login_id") || Map.get(map, "loginId"),
      success: Map.get(map, "success") || false,
      error: Map.get(map, "error")
    }
  end

  def parse!(%{"type" => "account/rateLimits/updated"} = map) do
    rate_limits =
      map
      |> Map.get("rate_limits")
      |> case do
        nil -> Map.get(map, "rateLimits")
        value -> value
      end
      |> parse_rate_limits()

    %AccountRateLimitsUpdated{
      rate_limits: rate_limits || %{},
      thread_id: Map.get(map, "thread_id") || Map.get(map, "threadId"),
      turn_id: Map.get(map, "turn_id") || Map.get(map, "turnId")
    }
  end

  def parse!(%{"type" => type} = map)
      when type in ["rawResponseItem/completed", "rawResponseItem.completed"] do
    item_map = Map.get(map, "item") || %{}

    item =
      case Items.parse_raw_response_item(item_map) do
        {:ok, parsed} -> parsed
        {:error, _} -> item_map
      end

    %RawResponseItemCompleted{
      thread_id: Map.get(map, "thread_id") || Map.get(map, "threadId"),
      turn_id: Map.get(map, "turn_id") || Map.get(map, "turnId"),
      item: item
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
    |> put_optional("rate_limits", encode_rate_limits(event.rate_limits))
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
      "rate_limits" => encode_rate_limits(event.rate_limits) || %{}
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
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

  def to_map(%DeprecationNotice{} = event) do
    %{
      "type" => "deprecationNotice",
      "summary" => event.summary
    }
    |> put_optional("details", event.details)
  end

  def to_map(%RawResponseItemCompleted{} = event) do
    %{
      "type" => "rawResponseItem/completed",
      "item" => encode_raw_item(event.item)
    }
    |> put_optional("thread_id", event.thread_id)
    |> put_optional("turn_id", event.turn_id)
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

  def to_map(%SessionConfigured{} = event) do
    %{
      "type" => "session_configured"
    }
    |> put_optional("session_id", event.session_id)
    |> put_optional("forked_from_id", event.forked_from_id)
    |> put_optional("model", event.model)
    |> put_optional("model_provider_id", event.model_provider_id)
    |> put_optional("approval_policy", event.approval_policy)
    |> put_optional("sandbox_policy", event.sandbox_policy)
    |> put_optional("cwd", event.cwd)
    |> put_optional("reasoning_effort", event.reasoning_effort)
    |> put_optional("history_log_id", event.history_log_id)
    |> put_optional("history_entry_count", event.history_entry_count)
    |> put_optional("initial_messages", encode_initial_messages(event.initial_messages))
    |> put_optional("rollout_path", event.rollout_path)
  end

  def to_map(%Warning{} = event) do
    %{
      "type" => "warning",
      "message" => event.message
    }
  end

  def to_map(%ContextCompacted{} = event) do
    %{
      "type" => "context_compacted"
    }
    |> put_optional("removed_turns", event.removed_turns)
    |> put_optional("remaining_turns", event.remaining_turns)
  end

  def to_map(%ThreadRolledBack{} = event) do
    %{
      "type" => "thread_rolled_back"
    }
    |> put_optional("num_turns", event.num_turns)
  end

  def to_map(%RequestUserInput{} = event) do
    %{
      "type" => "request_user_input"
    }
    |> put_optional("id", event.id)
    |> put_optional("turn_id", event.turn_id)
    |> put_optional("questions", encode_request_user_input_questions(event.questions))
  end

  def to_map(%McpStartupUpdate{} = event) do
    %{
      "type" => "mcp_startup_update",
      "server" => event.server_name
    }
    |> put_optional("status", event.status)
    |> put_optional("message", event.message)
  end

  def to_map(%McpStartupComplete{} = event) do
    %{"type" => "mcp_startup_complete"}
    |> Map.merge(encode_mcp_startup_complete(event.servers))
  end

  def to_map(%ElicitationRequest{} = event) do
    %{
      "type" => "elicitation_request",
      "server_name" => event.server_name,
      "id" => event.id,
      "message" => event.message
    }
  end

  def to_map(%UndoStarted{} = event) do
    %{
      "type" => "undo_started"
    }
    |> put_optional("turn_id", event.turn_id)
    |> put_optional("message", event.message)
  end

  def to_map(%UndoCompleted{} = event) do
    %{
      "type" => "undo_completed"
    }
    |> put_optional("turn_id", event.turn_id)
    |> put_optional("success", event.success)
    |> put_optional("message", event.message)
  end

  def to_map(%TurnAborted{} = event) do
    %{
      "type" => "turn_aborted"
    }
    |> put_optional("turn_id", event.turn_id)
    |> put_optional("reason", event.reason)
  end

  def to_map(%ShutdownComplete{}) do
    %{"type" => "shutdown_complete"}
  end

  def to_map(%EnteredReviewMode{} = event) do
    base = %{"type" => "entered_review_mode"}

    case event.review_request do
      %{} = request -> Map.merge(base, request)
      nil -> base
      other -> Map.put(base, "review_request", other)
    end
  end

  def to_map(%ExitedReviewMode{} = event) do
    %{"type" => "exited_review_mode"}
    |> put_optional("review_output", event.result)
  end

  def to_map(%ConfigWarning{} = event) do
    %{
      "type" => "configWarning",
      "summary" => event.summary
    }
    |> put_optional("details", event.details)
  end

  def to_map(%CollabAgentSpawnBegin{} = event) do
    %{
      "type" => "collab_agent_spawn_begin",
      "call_id" => event.call_id,
      "sender_thread_id" => event.sender_thread_id
    }
    |> put_optional("prompt", event.prompt)
  end

  def to_map(%CollabAgentSpawnEnd{} = event) do
    %{
      "type" => "collab_agent_spawn_end",
      "call_id" => event.call_id,
      "sender_thread_id" => event.sender_thread_id
    }
    |> put_optional("new_thread_id", event.new_thread_id)
    |> put_optional("prompt", event.prompt)
    |> put_optional("status", event.status)
  end

  def to_map(%CollabAgentInteractionBegin{} = event) do
    %{
      "type" => "collab_agent_interaction_begin",
      "call_id" => event.call_id,
      "sender_thread_id" => event.sender_thread_id,
      "receiver_thread_id" => event.receiver_thread_id
    }
    |> put_optional("prompt", event.prompt)
  end

  def to_map(%CollabAgentInteractionEnd{} = event) do
    %{
      "type" => "collab_agent_interaction_end",
      "call_id" => event.call_id,
      "sender_thread_id" => event.sender_thread_id,
      "receiver_thread_id" => event.receiver_thread_id
    }
    |> put_optional("prompt", event.prompt)
    |> put_optional("status", event.status)
  end

  def to_map(%CollabWaitingBegin{} = event) do
    %{
      "type" => "collab_waiting_begin",
      "sender_thread_id" => event.sender_thread_id,
      "receiver_thread_ids" => event.receiver_thread_ids,
      "call_id" => event.call_id
    }
  end

  def to_map(%CollabWaitingEnd{} = event) do
    %{
      "type" => "collab_waiting_end",
      "sender_thread_id" => event.sender_thread_id,
      "call_id" => event.call_id
    }
    |> put_optional("statuses", event.statuses)
  end

  def to_map(%CollabCloseBegin{} = event) do
    %{
      "type" => "collab_close_begin",
      "call_id" => event.call_id,
      "sender_thread_id" => event.sender_thread_id,
      "receiver_thread_id" => event.receiver_thread_id
    }
  end

  def to_map(%CollabCloseEnd{} = event) do
    %{
      "type" => "collab_close_end",
      "call_id" => event.call_id,
      "sender_thread_id" => event.sender_thread_id,
      "receiver_thread_id" => event.receiver_thread_id
    }
    |> put_optional("status", event.status)
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

  defp parse_initial_messages(nil), do: nil

  defp parse_initial_messages(messages) when is_list(messages) do
    Enum.map(messages, &parse_initial_message/1)
  end

  defp parse_initial_messages(_), do: nil

  defp parse_session_configured(%{} = map) do
    %SessionConfigured{
      session_id: fetch_any(map, ["session_id", "sessionId"]),
      forked_from_id: fetch_any(map, ["forked_from_id", "forkedFromId"]),
      model: Map.get(map, "model"),
      model_provider_id: fetch_any(map, ["model_provider_id", "modelProviderId"]),
      approval_policy: fetch_any(map, ["approval_policy", "approvalPolicy"]),
      sandbox_policy: fetch_any(map, ["sandbox_policy", "sandboxPolicy"]),
      cwd: Map.get(map, "cwd"),
      reasoning_effort: fetch_any(map, ["reasoning_effort", "reasoningEffort"]),
      history_log_id: fetch_any(map, ["history_log_id", "historyLogId"]),
      history_entry_count: fetch_any(map, ["history_entry_count", "historyEntryCount"]),
      initial_messages:
        map
        |> fetch_initial_messages()
        |> parse_initial_messages(),
      rollout_path: fetch_any(map, ["rollout_path", "rolloutPath"])
    }
  end

  defp fetch_initial_messages(%{} = map) do
    Map.get(map, "initial_messages") || Map.get(map, "initialMessages")
  end

  defp fetch_any(%{} = map, keys) when is_list(keys) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      if Map.has_key?(map, key) do
        {:halt, Map.get(map, key)}
      else
        {:cont, nil}
      end
    end)
  end

  defp parse_initial_message(%{} = message) do
    parse!(message)
  rescue
    _ -> message
  end

  defp parse_initial_message(other), do: other

  defp encode_initial_messages(nil), do: nil

  defp encode_initial_messages(messages) when is_list(messages) do
    Enum.map(messages, &encode_initial_message/1)
  end

  defp encode_initial_messages(other), do: other

  defp encode_initial_message(%{__struct__: _} = message), do: to_map(message)
  defp encode_initial_message(other), do: other

  defp parse_request_user_input_questions(nil), do: []

  defp parse_request_user_input_questions(questions) when is_list(questions) do
    Enum.map(questions, fn
      %RequestUserInputQuestion{} = question ->
        question

      %{} = question ->
        RequestUserInputQuestion.from_map(question)

      other ->
        other
    end)
  end

  defp parse_request_user_input_questions(_), do: []

  defp encode_request_user_input_questions(nil), do: nil

  defp encode_request_user_input_questions(questions) when is_list(questions) do
    Enum.map(questions, fn
      %RequestUserInputQuestion{} = question ->
        %{
          "id" => question.id,
          "header" => question.header,
          "question" => question.question
        }
        |> put_optional("options", encode_request_user_input_options(question.options))

      %{} = question ->
        question

      other ->
        other
    end)
  end

  defp encode_request_user_input_questions(other), do: other

  defp encode_request_user_input_options(nil), do: nil

  defp encode_request_user_input_options(options) when is_list(options) do
    Enum.map(options, fn
      %Codex.Protocol.RequestUserInput.Option{} = option ->
        %{"label" => option.label, "description" => option.description}

      %{} = option ->
        option

      other ->
        other
    end)
  end

  defp encode_request_user_input_options(other), do: other

  defp normalize_mcp_startup_status(nil), do: {nil, nil}

  defp normalize_mcp_startup_status(%{"state" => state} = status) do
    {state, Map.get(status, "error")}
  end

  defp normalize_mcp_startup_status(%{state: state} = status) do
    {state, Map.get(status, :error)}
  end

  defp normalize_mcp_startup_status(value) when is_atom(value) do
    {Atom.to_string(value), nil}
  end

  defp normalize_mcp_startup_status(value) when is_binary(value), do: {value, nil}
  defp normalize_mcp_startup_status(_), do: {nil, nil}

  defp normalize_mcp_startup_complete(%{} = map) do
    servers = Map.get(map, "servers") || Map.get(map, :servers)

    if servers != nil do
      servers
    else
      data =
        %{}
        |> put_optional("ready", Map.get(map, "ready") || Map.get(map, :ready))
        |> put_optional("failed", Map.get(map, "failed") || Map.get(map, :failed))
        |> put_optional(
          "cancelled",
          Map.get(map, "cancelled") || Map.get(map, :cancelled) || Map.get(map, "canceled")
        )

      if data == %{}, do: nil, else: data
    end
  end

  defp encode_mcp_startup_complete(nil), do: %{}

  defp encode_mcp_startup_complete(%{} = servers) do
    ready = Map.get(servers, "ready") || Map.get(servers, :ready)
    failed = Map.get(servers, "failed") || Map.get(servers, :failed)
    cancelled = Map.get(servers, "cancelled") || Map.get(servers, :cancelled)

    if ready != nil or failed != nil or cancelled != nil do
      %{}
      |> put_optional("ready", ready)
      |> put_optional("failed", failed)
      |> put_optional("cancelled", cancelled)
    else
      %{"servers" => servers}
    end
  end

  defp encode_mcp_startup_complete(servers) when is_list(servers) do
    %{"servers" => servers}
  end

  defp encode_mcp_startup_complete(servers) do
    %{"servers" => servers}
  end

  defp parse_rate_limits(nil), do: nil

  defp parse_rate_limits(%RateLimitSnapshot{} = snapshot), do: snapshot

  defp parse_rate_limits(%{} = snapshot) do
    RateLimitSnapshot.from_map(snapshot)
  rescue
    _ -> snapshot
  end

  defp parse_rate_limits(_), do: nil

  defp encode_rate_limits(nil), do: nil

  defp encode_rate_limits(%RateLimitSnapshot{} = snapshot) do
    %{}
    |> put_optional("primary", encode_rate_limit_window(snapshot.primary))
    |> put_optional("secondary", encode_rate_limit_window(snapshot.secondary))
    |> put_optional("credits", encode_rate_limit_credits(snapshot.credits))
    |> put_optional("plan_type", encode_rate_limit_plan(snapshot.plan_type))
  end

  defp encode_rate_limits(%{} = snapshot), do: snapshot
  defp encode_rate_limits(other), do: other

  defp encode_rate_limit_window(nil), do: nil

  defp encode_rate_limit_window(%Codex.Protocol.RateLimit.Window{} = window) do
    %{}
    |> put_optional("used_percent", window.used_percent)
    |> put_optional("window_minutes", window.window_minutes)
    |> put_optional("resets_at", window.resets_at)
  end

  defp encode_rate_limit_window(%{} = window), do: window
  defp encode_rate_limit_window(other), do: other

  defp encode_rate_limit_credits(nil), do: nil

  defp encode_rate_limit_credits(%Codex.Protocol.RateLimit.CreditsSnapshot{} = credits) do
    %{}
    |> put_optional("has_credits", credits.has_credits)
    |> put_optional("unlimited", credits.unlimited)
    |> put_optional("balance", credits.balance)
  end

  defp encode_rate_limit_credits(%{} = credits), do: credits
  defp encode_rate_limit_credits(other), do: other

  defp encode_rate_limit_plan(nil), do: nil
  defp encode_rate_limit_plan(plan) when is_atom(plan), do: Atom.to_string(plan)
  defp encode_rate_limit_plan(plan) when is_binary(plan), do: plan
  defp encode_rate_limit_plan(plan), do: to_string(plan)

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp encode_raw_item(%{__struct__: _} = item), do: Items.to_map(item)
  defp encode_raw_item(%{} = item), do: item
  defp encode_raw_item(other), do: other

  defp encode_final_response(%Items.AgentMessage{text: text}) when is_binary(text) do
    %{"type" => "text", "text" => text}
  end

  defp encode_final_response(%Items.AgentMessage{}), do: %{"type" => "text"}
  defp encode_final_response(other), do: other
end
