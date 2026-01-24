defmodule Codex.Realtime.Events do
  @moduledoc """
  High-level session events for realtime applications.

  These events are emitted by the session and provide a clean interface
  for application code to react to session state changes.
  """

  alias Codex.Realtime.Items
  alias Codex.Realtime.ModelEvents

  defmodule EventInfo do
    @moduledoc "Common information for all events."
    defstruct [:context]
    @type t :: %__MODULE__{context: map()}
  end

  # Session Event Structs

  defmodule AgentStartEvent do
    @moduledoc "A new agent has started."
    defstruct [:agent, :info, type: :agent_start]

    @type t :: %__MODULE__{
            type: :agent_start,
            agent: term(),
            info: Codex.Realtime.Events.EventInfo.t()
          }
  end

  defmodule AgentEndEvent do
    @moduledoc "An agent has ended."
    defstruct [:agent, :info, type: :agent_end]

    @type t :: %__MODULE__{
            type: :agent_end,
            agent: term(),
            info: Codex.Realtime.Events.EventInfo.t()
          }
  end

  defmodule HandoffEvent do
    @moduledoc "Agent handed off to another agent."
    defstruct [:from_agent, :to_agent, :info, type: :handoff]

    @type t :: %__MODULE__{
            type: :handoff,
            from_agent: term(),
            to_agent: term(),
            info: Codex.Realtime.Events.EventInfo.t()
          }
  end

  defmodule ToolStartEvent do
    @moduledoc "Tool call started."
    defstruct [:agent, :tool, :arguments, :info, type: :tool_start]

    @type t :: %__MODULE__{
            type: :tool_start,
            agent: term(),
            tool: term(),
            arguments: String.t(),
            info: Codex.Realtime.Events.EventInfo.t()
          }
  end

  defmodule ToolEndEvent do
    @moduledoc "Tool call completed."
    defstruct [:agent, :tool, :arguments, :output, :info, type: :tool_end]

    @type t :: %__MODULE__{
            type: :tool_end,
            agent: term(),
            tool: term(),
            arguments: String.t(),
            output: term(),
            info: Codex.Realtime.Events.EventInfo.t()
          }
  end

  defmodule RawModelEvent do
    @moduledoc "Raw model event wrapper."
    defstruct [:data, :info, type: :raw_model_event]

    @type t :: %__MODULE__{
            type: :raw_model_event,
            data: ModelEvents.t(),
            info: Codex.Realtime.Events.EventInfo.t()
          }
  end

  defmodule AudioEndEvent do
    @moduledoc "Audio generation ended."
    defstruct [:item_id, :content_index, :info, type: :audio_end]

    @type t :: %__MODULE__{
            type: :audio_end,
            item_id: String.t(),
            content_index: non_neg_integer(),
            info: Codex.Realtime.Events.EventInfo.t()
          }
  end

  defmodule AudioEvent do
    @moduledoc "Audio data received."
    defstruct [:audio, :item_id, :content_index, :info, type: :audio]

    @type t :: %__MODULE__{
            type: :audio,
            audio: ModelEvents.AudioEvent.t() | map(),
            item_id: String.t(),
            content_index: non_neg_integer(),
            info: Codex.Realtime.Events.EventInfo.t()
          }
  end

  defmodule AudioInterruptedEvent do
    @moduledoc "Audio was interrupted."
    defstruct [:item_id, :content_index, :info, type: :audio_interrupted]

    @type t :: %__MODULE__{
            type: :audio_interrupted,
            item_id: String.t(),
            content_index: non_neg_integer(),
            info: Codex.Realtime.Events.EventInfo.t()
          }
  end

  defmodule ErrorEvent do
    @moduledoc "Error occurred."
    defstruct [:error, :info, type: :error]

    @type t :: %__MODULE__{
            type: :error,
            error: term(),
            info: Codex.Realtime.Events.EventInfo.t()
          }
  end

  defmodule HistoryUpdatedEvent do
    @moduledoc "Full history update."
    defstruct [:history, :info, type: :history_updated]

    @type t :: %__MODULE__{
            type: :history_updated,
            history: [Items.item()],
            info: Codex.Realtime.Events.EventInfo.t()
          }
  end

  defmodule HistoryAddedEvent do
    @moduledoc "Item added to history."
    defstruct [:item, :info, type: :history_added]

    @type t :: %__MODULE__{
            type: :history_added,
            item: Items.item(),
            info: Codex.Realtime.Events.EventInfo.t()
          }
  end

  defmodule GuardrailTrippedEvent do
    @moduledoc "Guardrail was tripped."
    defstruct [:guardrail_results, :message, :info, type: :guardrail_tripped]

    @type t :: %__MODULE__{
            type: :guardrail_tripped,
            guardrail_results: list(),
            message: String.t(),
            info: Codex.Realtime.Events.EventInfo.t()
          }
  end

  defmodule InputAudioTimeoutTriggeredEvent do
    @moduledoc "Input audio timeout triggered."
    defstruct [:info, type: :input_audio_timeout_triggered]

    @type t :: %__MODULE__{
            type: :input_audio_timeout_triggered,
            info: Codex.Realtime.Events.EventInfo.t()
          }
  end

  @type t ::
          AgentStartEvent.t()
          | AgentEndEvent.t()
          | HandoffEvent.t()
          | ToolStartEvent.t()
          | ToolEndEvent.t()
          | RawModelEvent.t()
          | AudioEndEvent.t()
          | AudioEvent.t()
          | AudioInterruptedEvent.t()
          | ErrorEvent.t()
          | HistoryUpdatedEvent.t()
          | HistoryAddedEvent.t()
          | GuardrailTrippedEvent.t()
          | InputAudioTimeoutTriggeredEvent.t()

  # Constructor Functions

  @doc "Create an agent start event."
  @spec agent_start(term(), map()) :: AgentStartEvent.t()
  def agent_start(agent, context) do
    %AgentStartEvent{agent: agent, info: %EventInfo{context: context}}
  end

  @doc "Create an agent end event."
  @spec agent_end(term(), map()) :: AgentEndEvent.t()
  def agent_end(agent, context) do
    %AgentEndEvent{agent: agent, info: %EventInfo{context: context}}
  end

  @doc "Create a handoff event."
  @spec handoff(term(), term(), map()) :: HandoffEvent.t()
  def handoff(from_agent, to_agent, context) do
    %HandoffEvent{
      from_agent: from_agent,
      to_agent: to_agent,
      info: %EventInfo{context: context}
    }
  end

  @doc "Create a tool start event."
  @spec tool_start(term(), term(), String.t(), map()) :: ToolStartEvent.t()
  def tool_start(agent, tool, arguments, context) do
    %ToolStartEvent{
      agent: agent,
      tool: tool,
      arguments: arguments,
      info: %EventInfo{context: context}
    }
  end

  @doc "Create a tool end event."
  @spec tool_end(term(), term(), String.t(), term(), map()) :: ToolEndEvent.t()
  def tool_end(agent, tool, arguments, output, context) do
    %ToolEndEvent{
      agent: agent,
      tool: tool,
      arguments: arguments,
      output: output,
      info: %EventInfo{context: context}
    }
  end

  @doc "Create a raw model event."
  @spec raw_model_event(ModelEvents.t(), map()) :: RawModelEvent.t()
  def raw_model_event(data, context) do
    %RawModelEvent{data: data, info: %EventInfo{context: context}}
  end

  @doc "Create an audio event."
  @spec audio(ModelEvents.AudioEvent.t() | map(), String.t(), non_neg_integer(), map()) ::
          AudioEvent.t()
  def audio(model_audio, item_id, content_index, context) do
    %AudioEvent{
      audio: model_audio,
      item_id: item_id,
      content_index: content_index,
      info: %EventInfo{context: context}
    }
  end

  @doc "Create an audio end event."
  @spec audio_end(String.t(), non_neg_integer(), map()) :: AudioEndEvent.t()
  def audio_end(item_id, content_index, context) do
    %AudioEndEvent{
      item_id: item_id,
      content_index: content_index,
      info: %EventInfo{context: context}
    }
  end

  @doc "Create an audio interrupted event."
  @spec audio_interrupted(String.t(), non_neg_integer(), map()) :: AudioInterruptedEvent.t()
  def audio_interrupted(item_id, content_index, context) do
    %AudioInterruptedEvent{
      item_id: item_id,
      content_index: content_index,
      info: %EventInfo{context: context}
    }
  end

  @doc "Create an error event."
  @spec error(term(), map()) :: ErrorEvent.t()
  def error(error, context) do
    %ErrorEvent{error: error, info: %EventInfo{context: context}}
  end

  @doc "Create a history updated event."
  @spec history_updated([Items.item()], map()) :: HistoryUpdatedEvent.t()
  def history_updated(history, context) do
    %HistoryUpdatedEvent{history: history, info: %EventInfo{context: context}}
  end

  @doc "Create a history added event."
  @spec history_added(Items.item(), map()) :: HistoryAddedEvent.t()
  def history_added(item, context) do
    %HistoryAddedEvent{item: item, info: %EventInfo{context: context}}
  end

  @doc "Create a guardrail tripped event."
  @spec guardrail_tripped(list(), String.t(), map()) :: GuardrailTrippedEvent.t()
  def guardrail_tripped(results, message, context) do
    %GuardrailTrippedEvent{
      guardrail_results: results,
      message: message,
      info: %EventInfo{context: context}
    }
  end

  @doc "Create an input audio timeout triggered event."
  @spec input_audio_timeout_triggered(map()) :: InputAudioTimeoutTriggeredEvent.t()
  def input_audio_timeout_triggered(context) do
    %InputAudioTimeoutTriggeredEvent{info: %EventInfo{context: context}}
  end
end
