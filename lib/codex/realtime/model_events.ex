defmodule Codex.Realtime.ModelEvents do
  @moduledoc """
  Low-level events from the realtime model transport layer.

  These events are emitted by the WebSocket connection and represent
  raw model communication. They are typically wrapped in session events
  before being exposed to application code.
  """

  alias Codex.Realtime.Items

  @type connection_status :: :connecting | :connected | :disconnected

  # Event Structs

  defmodule ConnectionStatusEvent do
    @moduledoc "Connection status change event."
    defstruct [:status, type: :connection_status]

    @type t :: %__MODULE__{
            type: :connection_status,
            status: Codex.Realtime.ModelEvents.connection_status()
          }
  end

  defmodule ErrorEvent do
    @moduledoc "Transport-layer error event."
    defstruct [:error, type: :error]
    @type t :: %__MODULE__{type: :error, error: term()}
  end

  defmodule ToolCallEvent do
    @moduledoc "Model attempted a tool/function call."
    defstruct [:name, :call_id, :arguments, :id, :previous_item_id, type: :function_call]

    @type t :: %__MODULE__{
            type: :function_call,
            name: String.t(),
            call_id: String.t(),
            arguments: String.t(),
            id: String.t() | nil,
            previous_item_id: String.t() | nil
          }
  end

  defmodule AudioEvent do
    @moduledoc "Raw audio bytes from the model."
    defstruct [:data, :response_id, :item_id, :content_index, type: :audio]

    @type t :: %__MODULE__{
            type: :audio,
            data: binary(),
            response_id: String.t(),
            item_id: String.t(),
            content_index: non_neg_integer()
          }
  end

  defmodule AudioDoneEvent do
    @moduledoc "Audio generation completed for an item."
    defstruct [:item_id, :content_index, type: :audio_done]

    @type t :: %__MODULE__{
            type: :audio_done,
            item_id: String.t(),
            content_index: non_neg_integer()
          }
  end

  defmodule AudioInterruptedEvent do
    @moduledoc "Audio was interrupted."
    defstruct [:item_id, :content_index, type: :audio_interrupted]

    @type t :: %__MODULE__{
            type: :audio_interrupted,
            item_id: String.t(),
            content_index: non_neg_integer()
          }
  end

  defmodule TranscriptDeltaEvent do
    @moduledoc "Partial transcript update."
    defstruct [:item_id, :delta, :response_id, type: :transcript_delta]

    @type t :: %__MODULE__{
            type: :transcript_delta,
            item_id: String.t(),
            delta: String.t(),
            response_id: String.t()
          }
  end

  defmodule ItemUpdatedEvent do
    @moduledoc "Item added to the history or updated."
    defstruct [:item, type: :item_updated]
    @type t :: %__MODULE__{type: :item_updated, item: Items.item()}
  end

  defmodule ItemDeletedEvent do
    @moduledoc "Item deleted from history."
    defstruct [:item_id, type: :item_deleted]
    @type t :: %__MODULE__{type: :item_deleted, item_id: String.t()}
  end

  defmodule TurnStartedEvent do
    @moduledoc "Model started generating a response."
    defstruct type: :turn_started
    @type t :: %__MODULE__{type: :turn_started}
  end

  defmodule TurnEndedEvent do
    @moduledoc "Model finished generating a response."
    defstruct type: :turn_ended
    @type t :: %__MODULE__{type: :turn_ended}
  end

  defmodule InputAudioTranscriptionCompletedEvent do
    @moduledoc "Input audio transcription completed."
    defstruct [:item_id, :transcript, type: :input_audio_transcription_completed]

    @type t :: %__MODULE__{
            type: :input_audio_transcription_completed,
            item_id: String.t(),
            transcript: String.t()
          }
  end

  defmodule InputAudioTimeoutTriggeredEvent do
    @moduledoc "Input audio timeout triggered."
    defstruct [:item_id, :audio_start_ms, :audio_end_ms, type: :input_audio_timeout_triggered]

    @type t :: %__MODULE__{
            type: :input_audio_timeout_triggered,
            item_id: String.t(),
            audio_start_ms: non_neg_integer(),
            audio_end_ms: non_neg_integer()
          }
  end

  defmodule OtherEvent do
    @moduledoc "Catchall for vendor-specific events."
    defstruct [:data, type: :other]
    @type t :: %__MODULE__{type: :other, data: term()}
  end

  defmodule ExceptionEvent do
    @moduledoc "Exception during model operation."
    defstruct [:exception, :context, type: :exception]

    @type t :: %__MODULE__{
            type: :exception,
            exception: Exception.t(),
            context: String.t() | nil
          }
  end

  defmodule RawServerEvent do
    @moduledoc "Raw event forwarded from server."
    defstruct [:data, type: :raw_server_event]
    @type t :: %__MODULE__{type: :raw_server_event, data: term()}
  end

  @type t ::
          ConnectionStatusEvent.t()
          | ErrorEvent.t()
          | ToolCallEvent.t()
          | AudioEvent.t()
          | AudioDoneEvent.t()
          | AudioInterruptedEvent.t()
          | TranscriptDeltaEvent.t()
          | ItemUpdatedEvent.t()
          | ItemDeletedEvent.t()
          | TurnStartedEvent.t()
          | TurnEndedEvent.t()
          | InputAudioTranscriptionCompletedEvent.t()
          | InputAudioTimeoutTriggeredEvent.t()
          | OtherEvent.t()
          | ExceptionEvent.t()
          | RawServerEvent.t()

  # Constructor Functions

  @doc "Create a connection status event."
  @spec connection_status(connection_status()) :: ConnectionStatusEvent.t()
  def connection_status(status) do
    %ConnectionStatusEvent{status: status}
  end

  @doc "Create an error event."
  @spec error(term()) :: ErrorEvent.t()
  def error(error) do
    %ErrorEvent{error: error}
  end

  @doc "Create a tool call event."
  @spec tool_call(keyword()) :: ToolCallEvent.t()
  def tool_call(opts) do
    %ToolCallEvent{
      name: Keyword.fetch!(opts, :name),
      call_id: Keyword.fetch!(opts, :call_id),
      arguments: Keyword.fetch!(opts, :arguments),
      id: Keyword.get(opts, :id),
      previous_item_id: Keyword.get(opts, :previous_item_id)
    }
  end

  @doc "Create an audio event."
  @spec audio(keyword()) :: AudioEvent.t()
  def audio(opts) do
    %AudioEvent{
      data: Keyword.fetch!(opts, :data),
      response_id: Keyword.fetch!(opts, :response_id),
      item_id: Keyword.fetch!(opts, :item_id),
      content_index: Keyword.fetch!(opts, :content_index)
    }
  end

  @doc "Create an audio done event."
  @spec audio_done(keyword()) :: AudioDoneEvent.t()
  def audio_done(opts) do
    %AudioDoneEvent{
      item_id: Keyword.fetch!(opts, :item_id),
      content_index: Keyword.fetch!(opts, :content_index)
    }
  end

  @doc "Create an audio interrupted event."
  @spec audio_interrupted(keyword()) :: AudioInterruptedEvent.t()
  def audio_interrupted(opts) do
    %AudioInterruptedEvent{
      item_id: Keyword.fetch!(opts, :item_id),
      content_index: Keyword.fetch!(opts, :content_index)
    }
  end

  @doc "Create a transcript delta event."
  @spec transcript_delta(keyword()) :: TranscriptDeltaEvent.t()
  def transcript_delta(opts) do
    %TranscriptDeltaEvent{
      item_id: Keyword.fetch!(opts, :item_id),
      delta: Keyword.fetch!(opts, :delta),
      response_id: Keyword.fetch!(opts, :response_id)
    }
  end

  @doc "Create an item updated event."
  @spec item_updated(Items.item()) :: ItemUpdatedEvent.t()
  def item_updated(item) do
    %ItemUpdatedEvent{item: item}
  end

  @doc "Create an item deleted event."
  @spec item_deleted(String.t()) :: ItemDeletedEvent.t()
  def item_deleted(item_id) do
    %ItemDeletedEvent{item_id: item_id}
  end

  @doc "Create a turn started event."
  @spec turn_started() :: TurnStartedEvent.t()
  def turn_started do
    %TurnStartedEvent{}
  end

  @doc "Create a turn ended event."
  @spec turn_ended() :: TurnEndedEvent.t()
  def turn_ended do
    %TurnEndedEvent{}
  end

  @doc "Create an input audio transcription completed event."
  @spec input_audio_transcription_completed(keyword()) ::
          InputAudioTranscriptionCompletedEvent.t()
  def input_audio_transcription_completed(opts) do
    %InputAudioTranscriptionCompletedEvent{
      item_id: Keyword.fetch!(opts, :item_id),
      transcript: Keyword.fetch!(opts, :transcript)
    }
  end

  @doc "Create an other event."
  @spec other(term()) :: OtherEvent.t()
  def other(data) do
    %OtherEvent{data: data}
  end

  @doc "Create an exception event."
  @spec exception(Exception.t(), String.t() | nil) :: ExceptionEvent.t()
  def exception(exception, context \\ nil) do
    %ExceptionEvent{exception: exception, context: context}
  end

  @doc "Create a raw server event."
  @spec raw_server_event(term()) :: RawServerEvent.t()
  def raw_server_event(data) do
    %RawServerEvent{data: data}
  end

  # Parsing

  @doc "Parse model event from JSON."
  @spec from_json(map()) :: {:ok, t()} | {:error, term()}
  def from_json(%{"type" => "error"} = json) do
    {:ok, error(json["error"])}
  end

  def from_json(%{"type" => "response.audio.delta"} = json) do
    {:ok,
     audio(
       data: Base.decode64!(json["delta"]),
       response_id: json["response_id"],
       item_id: json["item_id"],
       content_index: json["content_index"] || json["output_index"] || 0
     )}
  end

  def from_json(%{"type" => "response.audio.done"} = json) do
    {:ok,
     audio_done(
       item_id: json["item_id"],
       content_index: json["content_index"] || json["output_index"] || 0
     )}
  end

  def from_json(%{"type" => "response.function_call_arguments.done"} = json) do
    {:ok,
     tool_call(
       name: json["name"],
       call_id: json["call_id"],
       arguments: json["arguments"],
       id: json["item_id"]
     )}
  end

  def from_json(%{"type" => "response.audio_transcript.delta"} = json) do
    {:ok,
     transcript_delta(
       item_id: json["item_id"],
       delta: json["delta"],
       response_id: json["response_id"]
     )}
  end

  def from_json(%{"type" => "conversation.item.created"} = json) do
    with {:ok, item} <- Items.from_json(json["item"]) do
      {:ok, item_updated(item)}
    end
  end

  def from_json(%{"type" => "conversation.item.deleted"} = json) do
    {:ok, item_deleted(json["item_id"])}
  end

  def from_json(%{"type" => "response.created"}) do
    {:ok, turn_started()}
  end

  def from_json(%{"type" => "response.done"}) do
    {:ok, turn_ended()}
  end

  def from_json(%{"type" => "conversation.item.input_audio_transcription.completed"} = json) do
    {:ok,
     input_audio_transcription_completed(
       item_id: json["item_id"],
       transcript: json["transcript"]
     )}
  end

  def from_json(%{"type" => "input_audio_buffer.speech_started"}) do
    {:ok, turn_started()}
  end

  def from_json(%{"type" => "input_audio_buffer.speech_stopped"}) do
    {:ok, turn_ended()}
  end

  def from_json(json) do
    {:ok, other(json)}
  end
end
