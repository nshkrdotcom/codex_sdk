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
              final_response: nil,
              usage: nil,
              status: nil

    @type t :: %__MODULE__{
            thread_id: String.t() | nil,
            turn_id: String.t() | nil,
            final_response: Items.AgentMessage.t() | map() | nil,
            usage: map() | nil,
            status: String.t() | nil
          }
  end

  defmodule ItemAgentMessageDelta do
    @moduledoc """
    Event delta emitted when the agent produces message content.
    """

    @enforce_keys [:item]
    defstruct item: %{}

    @type t :: %__MODULE__{
            item: map()
          }
  end

  defmodule ItemInputTextDelta do
    @moduledoc """
    Event delta emitted for user input text items.
    """

    @enforce_keys [:item]
    defstruct item: %{}

    @type t :: %__MODULE__{
            item: map()
          }
  end

  defmodule ItemCompleted do
    @moduledoc """
    Event emitted when an item completes.
    """

    @enforce_keys [:item]
    defstruct item: nil

    @type t :: %__MODULE__{
            item: Items.t()
          }
  end

  defmodule ItemStarted do
    @moduledoc """
    Event emitted when an item begins processing.
    """

    @enforce_keys [:item]
    defstruct item: nil

    @type t :: %__MODULE__{
            item: Items.t()
          }
  end

  defmodule ItemUpdated do
    @moduledoc """
    Event emitted when an in-progress item receives an update.
    """

    @enforce_keys [:item]
    defstruct item: nil

    @type t :: %__MODULE__{
            item: Items.t()
          }
  end

  defmodule Error do
    @moduledoc """
    General error event emitted by the CLI.
    """

    @enforce_keys [:message]
    defstruct message: nil

    @type t :: %__MODULE__{
            message: String.t()
          }
  end

  defmodule TurnFailed do
    @moduledoc """
    Event emitted when a turn fails.
    """

    @enforce_keys [:error]
    defstruct error: %{}

    @type t :: %__MODULE__{
            error: map()
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
              requires_approval: false

    @type t :: %__MODULE__{
            thread_id: String.t(),
            turn_id: String.t(),
            call_id: String.t(),
            tool_name: String.t(),
            arguments: map(),
            requires_approval: boolean()
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
    TurnContinuation,
    TurnStarted,
    ToolCallCompleted,
    ToolCallRequested,
    ItemCompleted,
    ItemStarted,
    ItemUpdated,
    Error,
    TurnFailed
  }

  @type t ::
          ThreadStarted.t()
          | TurnStarted.t()
          | TurnContinuation.t()
          | TurnCompleted.t()
          | ItemAgentMessageDelta.t()
          | ItemInputTextDelta.t()
          | ItemCompleted.t()
          | ItemStarted.t()
          | ItemUpdated.t()
          | Error.t()
          | TurnFailed.t()
          | ToolCallRequested.t()
          | ToolCallCompleted.t()

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
      final_response: Map.get(map, "final_response"),
      usage: Map.get(map, "usage"),
      status: Map.get(map, "status")
    }
  end

  def parse!(%{"type" => "item.agent_message.delta"} = map) do
    %ItemAgentMessageDelta{
      item: Map.fetch!(map, "item")
    }
  end

  def parse!(%{"type" => "item.input_text.delta"} = map) do
    %ItemInputTextDelta{
      item: Map.fetch!(map, "item")
    }
  end

  def parse!(%{"type" => "item.completed"} = map) do
    %ItemCompleted{
      item: map |> Map.fetch!("item") |> Items.parse!()
    }
  end

  def parse!(%{"type" => "item.started"} = map) do
    %ItemStarted{
      item: map |> Map.fetch!("item") |> Items.parse!()
    }
  end

  def parse!(%{"type" => "item.updated"} = map) do
    %ItemUpdated{
      item: map |> Map.fetch!("item") |> Items.parse!()
    }
  end

  def parse!(%{"type" => "error"} = map) do
    %Error{
      message: Map.get(map, "message")
    }
  end

  def parse!(%{"type" => "turn.failed"} = map) do
    %TurnFailed{
      error: Map.get(map, "error", %{})
    }
  end

  def parse!(%{"type" => "tool.call.required"} = map) do
    %ToolCallRequested{
      thread_id: Map.fetch!(map, "thread_id"),
      turn_id: Map.fetch!(map, "turn_id"),
      call_id: Map.fetch!(map, "call_id"),
      tool_name: Map.fetch!(map, "tool_name"),
      arguments: Map.get(map, "arguments", %{}),
      requires_approval: Map.get(map, "requires_approval", false)
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
    |> put_optional("final_response", encode_final_response(event.final_response))
    |> put_optional("usage", event.usage)
    |> put_optional("status", event.status)
  end

  def to_map(%ItemAgentMessageDelta{} = event) do
    %{
      "type" => "item.agent_message.delta",
      "item" => event.item
    }
  end

  def to_map(%ItemInputTextDelta{} = event) do
    %{
      "type" => "item.input_text.delta",
      "item" => event.item
    }
  end

  def to_map(%ItemCompleted{} = event) do
    %{
      "type" => "item.completed",
      "item" => Items.to_map(event.item)
    }
  end

  def to_map(%ItemStarted{} = event) do
    %{
      "type" => "item.started",
      "item" => Items.to_map(event.item)
    }
  end

  def to_map(%ItemUpdated{} = event) do
    %{
      "type" => "item.updated",
      "item" => Items.to_map(event.item)
    }
  end

  def to_map(%Error{} = event) do
    %{
      "type" => "error",
      "message" => event.message
    }
  end

  def to_map(%TurnFailed{} = event) do
    %{
      "type" => "turn.failed",
      "error" => event.error
    }
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

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp encode_final_response(%Items.AgentMessage{text: text}) when is_binary(text) do
    %{"type" => "text", "text" => text}
  end

  defp encode_final_response(%Items.AgentMessage{}), do: %{"type" => "text"}
  defp encode_final_response(other), do: other
end
