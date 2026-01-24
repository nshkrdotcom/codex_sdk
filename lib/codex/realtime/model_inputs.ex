defmodule Codex.Realtime.ModelInputs do
  @moduledoc """
  Input message types for sending events to the realtime model.

  These structs represent commands that can be sent to the realtime
  WebSocket connection, such as sending audio, user input, or tool outputs.
  """

  alias Codex.Realtime.Config.SessionModelSettings
  alias Codex.Realtime.ModelEvents

  # Input Message Structs

  defmodule SendRawMessage do
    @moduledoc "Send a raw message to the model."
    defstruct [:message]

    @type t :: %__MODULE__{
            message: map()
          }
  end

  defmodule SendUserInput do
    @moduledoc "Send user input (text or structured message)."
    defstruct [:user_input]

    @type t :: %__MODULE__{
            user_input: String.t() | map()
          }
  end

  defmodule SendAudio do
    @moduledoc "Send audio data to the model."
    defstruct [:audio, commit: false]

    @type t :: %__MODULE__{
            audio: binary(),
            commit: boolean()
          }
  end

  defmodule SendToolOutput do
    @moduledoc "Send tool output to the model."
    defstruct [:tool_call, :output, :start_response]

    @type t :: %__MODULE__{
            tool_call: ModelEvents.ToolCallEvent.t(),
            output: String.t(),
            start_response: boolean()
          }
  end

  defmodule SendInterrupt do
    @moduledoc "Send an interrupt to the model."
    defstruct force_response_cancel: false

    @type t :: %__MODULE__{
            force_response_cancel: boolean()
          }
  end

  defmodule SendSessionUpdate do
    @moduledoc "Send session settings update."
    defstruct [:session_settings]

    @type t :: %__MODULE__{
            session_settings: SessionModelSettings.t()
          }
  end

  @type send_event ::
          SendRawMessage.t()
          | SendUserInput.t()
          | SendAudio.t()
          | SendToolOutput.t()
          | SendInterrupt.t()
          | SendSessionUpdate.t()

  # Constructors

  @doc "Create a send raw message event."
  @spec send_raw_message(map()) :: SendRawMessage.t()
  def send_raw_message(message) do
    %SendRawMessage{message: message}
  end

  @doc "Create a send user input event."
  @spec send_user_input(String.t() | map()) :: SendUserInput.t()
  def send_user_input(input) do
    %SendUserInput{user_input: input}
  end

  @doc "Create a send audio event."
  @spec send_audio(binary(), boolean()) :: SendAudio.t()
  def send_audio(audio, commit \\ false) do
    %SendAudio{audio: audio, commit: commit}
  end

  @doc "Create a send tool output event."
  @spec send_tool_output(ModelEvents.ToolCallEvent.t(), String.t(), boolean()) ::
          SendToolOutput.t()
  def send_tool_output(tool_call, output, start_response \\ true) do
    %SendToolOutput{tool_call: tool_call, output: output, start_response: start_response}
  end

  @doc "Create a send interrupt event."
  @spec send_interrupt(boolean()) :: SendInterrupt.t()
  def send_interrupt(force \\ false) do
    %SendInterrupt{force_response_cancel: force}
  end

  @doc "Create a send session update event."
  @spec send_session_update(SessionModelSettings.t()) :: SendSessionUpdate.t()
  def send_session_update(settings) do
    %SendSessionUpdate{session_settings: settings}
  end

  # JSON Serialization

  @doc "Convert send event to JSON for WebSocket."
  @spec to_json(send_event()) :: map() | [map()]
  def to_json(%SendRawMessage{message: msg}) do
    msg
  end

  def to_json(%SendUserInput{user_input: input}) when is_binary(input) do
    %{
      "type" => "conversation.item.create",
      "item" => %{
        "type" => "message",
        "role" => "user",
        "content" => [%{"type" => "input_text", "text" => input}]
      }
    }
  end

  def to_json(%SendUserInput{user_input: %{"type" => "message"} = msg}) do
    %{"type" => "conversation.item.create", "item" => msg}
  end

  def to_json(%SendUserInput{user_input: msg}) when is_map(msg) do
    %{"type" => "conversation.item.create", "item" => msg}
  end

  def to_json(%SendAudio{audio: audio, commit: commit}) do
    base_msg = %{
      "type" => "input_audio_buffer.append",
      "audio" => Base.encode64(audio)
    }

    if commit do
      # Return list of messages: append then commit
      [base_msg, %{"type" => "input_audio_buffer.commit"}]
    else
      base_msg
    end
  end

  def to_json(%SendToolOutput{tool_call: tc, output: output, start_response: start}) do
    msgs = [
      %{
        "type" => "conversation.item.create",
        "item" => %{
          "type" => "function_call_output",
          "call_id" => tc.call_id,
          "output" => output
        }
      }
    ]

    if start do
      msgs ++ [%{"type" => "response.create"}]
    else
      msgs
    end
  end

  def to_json(%SendInterrupt{}) do
    %{"type" => "response.cancel"}
  end

  def to_json(%SendSessionUpdate{session_settings: settings}) do
    %{
      "type" => "session.update",
      "session" => SessionModelSettings.to_json(settings)
    }
  end
end
