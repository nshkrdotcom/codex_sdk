defmodule Codex.Realtime.Items do
  @moduledoc """
  Conversation item types for realtime sessions.

  Items represent messages, tool calls, and their content in a realtime conversation.
  """

  # Content Types

  defmodule InputText do
    @moduledoc "Text input content."
    @enforce_keys [:type, :text]
    defstruct [:type, :text]

    @type t :: %__MODULE__{
            type: :input_text,
            text: String.t() | nil
          }
  end

  defmodule InputAudio do
    @moduledoc "Audio input content."
    @enforce_keys [:type]
    defstruct [:type, :audio, :transcript]

    @type t :: %__MODULE__{
            type: :input_audio,
            audio: String.t() | nil,
            transcript: String.t() | nil
          }
  end

  defmodule InputImage do
    @moduledoc "Image input content."
    @enforce_keys [:type]
    defstruct [:type, :image_url, :detail]

    @type t :: %__MODULE__{
            type: :input_image,
            image_url: String.t() | nil,
            detail: String.t() | nil
          }
  end

  defmodule AssistantText do
    @moduledoc "Text content from assistant."
    @enforce_keys [:type]
    defstruct [:type, :text]

    @type t :: %__MODULE__{
            type: :text,
            text: String.t() | nil
          }
  end

  defmodule AssistantAudio do
    @moduledoc "Audio content from assistant."
    @enforce_keys [:type]
    defstruct [:type, :audio, :transcript]

    @type t :: %__MODULE__{
            type: :audio,
            audio: String.t() | nil,
            transcript: String.t() | nil
          }
  end

  # Message Item Types

  defmodule SystemMessageItem do
    @moduledoc "A system message item."
    @enforce_keys [:item_id, :type, :role, :content]
    defstruct [:item_id, :previous_item_id, :type, :role, :content]

    @type t :: %__MODULE__{
            item_id: String.t(),
            previous_item_id: String.t() | nil,
            type: :message,
            role: :system,
            content: [Codex.Realtime.Items.InputText.t()]
          }
  end

  defmodule UserMessageItem do
    @moduledoc "A user message item."
    @enforce_keys [:item_id, :type, :role, :content]
    defstruct [:item_id, :previous_item_id, :type, :role, :content]

    @type t :: %__MODULE__{
            item_id: String.t(),
            previous_item_id: String.t() | nil,
            type: :message,
            role: :user,
            content: [
              Codex.Realtime.Items.InputText.t()
              | Codex.Realtime.Items.InputAudio.t()
              | Codex.Realtime.Items.InputImage.t()
            ]
          }
  end

  defmodule AssistantMessageItem do
    @moduledoc "An assistant message item."
    @enforce_keys [:item_id, :type, :role, :content]
    defstruct [:item_id, :previous_item_id, :type, :role, :status, :content]

    @type status :: :in_progress | :completed | :incomplete

    @type t :: %__MODULE__{
            item_id: String.t(),
            previous_item_id: String.t() | nil,
            type: :message,
            role: :assistant,
            status: status() | nil,
            content: [
              Codex.Realtime.Items.AssistantText.t()
              | Codex.Realtime.Items.AssistantAudio.t()
            ]
          }
  end

  defmodule RealtimeToolCallItem do
    @moduledoc "A tool/function call item."
    @enforce_keys [:item_id, :type, :status, :arguments, :name]
    defstruct [:item_id, :previous_item_id, :call_id, :type, :status, :arguments, :name, :output]

    @type status :: :in_progress | :completed

    @type t :: %__MODULE__{
            item_id: String.t(),
            previous_item_id: String.t() | nil,
            call_id: String.t() | nil,
            type: :function_call,
            status: status(),
            arguments: String.t(),
            name: String.t(),
            output: String.t() | nil
          }
  end

  # Type Aliases

  @type input_content :: InputText.t() | InputAudio.t() | InputImage.t()
  @type assistant_content :: AssistantText.t() | AssistantAudio.t()
  @type message_item :: SystemMessageItem.t() | UserMessageItem.t() | AssistantMessageItem.t()
  @type item :: message_item() | RealtimeToolCallItem.t()

  # Constructor Functions

  @doc "Create input text content."
  @spec input_text(String.t()) :: InputText.t()
  def input_text(text) do
    %InputText{type: :input_text, text: text}
  end

  @doc "Create input audio content."
  @spec input_audio(String.t() | nil, String.t() | nil) :: InputAudio.t()
  def input_audio(audio \\ nil, transcript \\ nil) do
    %InputAudio{type: :input_audio, audio: audio, transcript: transcript}
  end

  @doc "Create input image content."
  @spec input_image(String.t(), String.t() | nil) :: InputImage.t()
  def input_image(image_url, detail \\ nil) do
    %InputImage{type: :input_image, image_url: image_url, detail: detail}
  end

  @doc "Create assistant text content."
  @spec assistant_text(String.t() | nil) :: AssistantText.t()
  def assistant_text(text \\ nil) do
    %AssistantText{type: :text, text: text}
  end

  @doc "Create assistant audio content."
  @spec assistant_audio(String.t() | nil, String.t() | nil) :: AssistantAudio.t()
  def assistant_audio(audio \\ nil, transcript \\ nil) do
    %AssistantAudio{type: :audio, audio: audio, transcript: transcript}
  end

  @doc "Create a system message item."
  @spec system_message(String.t(), [InputText.t()], keyword()) :: SystemMessageItem.t()
  def system_message(item_id, content, opts \\ []) do
    %SystemMessageItem{
      item_id: item_id,
      previous_item_id: Keyword.get(opts, :previous_item_id),
      type: :message,
      role: :system,
      content: content
    }
  end

  @doc "Create a user message item."
  @spec user_message(String.t(), [input_content()], keyword()) :: UserMessageItem.t()
  def user_message(item_id, content, opts \\ []) do
    %UserMessageItem{
      item_id: item_id,
      previous_item_id: Keyword.get(opts, :previous_item_id),
      type: :message,
      role: :user,
      content: content
    }
  end

  @doc "Create an assistant message item."
  @spec assistant_message(String.t(), [assistant_content()], keyword()) ::
          AssistantMessageItem.t()
  def assistant_message(item_id, content, opts \\ []) do
    %AssistantMessageItem{
      item_id: item_id,
      previous_item_id: Keyword.get(opts, :previous_item_id),
      type: :message,
      role: :assistant,
      status: Keyword.get(opts, :status),
      content: content
    }
  end

  @doc "Create a tool call item."
  @spec tool_call_item(keyword()) :: RealtimeToolCallItem.t()
  def tool_call_item(opts) do
    %RealtimeToolCallItem{
      item_id: Keyword.fetch!(opts, :item_id),
      previous_item_id: Keyword.get(opts, :previous_item_id),
      call_id: Keyword.get(opts, :call_id),
      type: :function_call,
      status: Keyword.fetch!(opts, :status),
      arguments: Keyword.fetch!(opts, :arguments),
      name: Keyword.fetch!(opts, :name),
      output: Keyword.get(opts, :output)
    }
  end

  # Serialization

  @doc "Convert an item or content to JSON-compatible map."
  @spec to_json(item() | input_content() | assistant_content()) :: map()
  def to_json(%InputText{} = content) do
    %{"type" => "input_text", "text" => content.text}
  end

  def to_json(%InputAudio{} = content) do
    %{"type" => "input_audio"}
    |> maybe_put("audio", content.audio)
    |> maybe_put("transcript", content.transcript)
  end

  def to_json(%InputImage{} = content) do
    %{"type" => "input_image"}
    |> maybe_put("image_url", content.image_url)
    |> maybe_put("detail", content.detail)
  end

  def to_json(%AssistantText{} = content) do
    %{"type" => "text"}
    |> maybe_put("text", content.text)
  end

  def to_json(%AssistantAudio{} = content) do
    %{"type" => "audio"}
    |> maybe_put("audio", content.audio)
    |> maybe_put("transcript", content.transcript)
  end

  def to_json(%SystemMessageItem{} = item) do
    %{
      "item_id" => item.item_id,
      "type" => "message",
      "role" => "system",
      "content" => Enum.map(item.content, &to_json/1)
    }
    |> maybe_put("previous_item_id", item.previous_item_id)
  end

  def to_json(%UserMessageItem{} = item) do
    %{
      "item_id" => item.item_id,
      "type" => "message",
      "role" => "user",
      "content" => Enum.map(item.content, &to_json/1)
    }
    |> maybe_put("previous_item_id", item.previous_item_id)
  end

  def to_json(%AssistantMessageItem{} = item) do
    %{
      "item_id" => item.item_id,
      "type" => "message",
      "role" => "assistant",
      "content" => Enum.map(item.content, &to_json/1)
    }
    |> maybe_put("previous_item_id", item.previous_item_id)
    |> maybe_put("status", status_to_string(item.status))
  end

  def to_json(%RealtimeToolCallItem{} = item) do
    %{
      "item_id" => item.item_id,
      "type" => "function_call",
      "status" => status_to_string(item.status),
      "arguments" => item.arguments,
      "name" => item.name
    }
    |> maybe_put("previous_item_id", item.previous_item_id)
    |> maybe_put("call_id", item.call_id)
    |> maybe_put("output", item.output)
  end

  # Parsing

  @doc "Parse an item from JSON."
  @spec from_json(map()) :: {:ok, item()} | {:error, term()}
  def from_json(%{"type" => "message", "role" => "system"} = json) do
    {:ok,
     %SystemMessageItem{
       item_id: json["item_id"],
       previous_item_id: json["previous_item_id"],
       type: :message,
       role: :system,
       content: parse_content(json["content"] || [], :input)
     }}
  end

  def from_json(%{"type" => "message", "role" => "user"} = json) do
    {:ok,
     %UserMessageItem{
       item_id: json["item_id"],
       previous_item_id: json["previous_item_id"],
       type: :message,
       role: :user,
       content: parse_content(json["content"] || [], :input)
     }}
  end

  def from_json(%{"type" => "message", "role" => "assistant"} = json) do
    {:ok,
     %AssistantMessageItem{
       item_id: json["item_id"],
       previous_item_id: json["previous_item_id"],
       type: :message,
       role: :assistant,
       status: parse_status(json["status"]),
       content: parse_content(json["content"] || [], :assistant)
     }}
  end

  def from_json(%{"type" => "function_call"} = json) do
    {:ok,
     %RealtimeToolCallItem{
       item_id: json["item_id"],
       previous_item_id: json["previous_item_id"],
       call_id: json["call_id"],
       type: :function_call,
       status: parse_status(json["status"]) || :in_progress,
       arguments: json["arguments"] || "",
       name: json["name"] || "",
       output: json["output"]
     }}
  end

  def from_json(json) do
    {:error, {:unknown_item_type, json["type"]}}
  end

  # Private Helpers

  defp parse_content(content_list, :input) do
    Enum.map(content_list, fn
      %{"type" => "input_text"} = c -> input_text(c["text"])
      %{"type" => "input_audio"} = c -> input_audio(c["audio"], c["transcript"])
      %{"type" => "input_image"} = c -> input_image(c["image_url"], c["detail"])
    end)
  end

  defp parse_content(content_list, :assistant) do
    Enum.map(content_list, fn
      %{"type" => "text"} = c -> assistant_text(c["text"])
      %{"type" => "audio"} = c -> assistant_audio(c["audio"], c["transcript"])
    end)
  end

  defp parse_status(nil), do: nil
  defp parse_status("in_progress"), do: :in_progress
  defp parse_status("completed"), do: :completed
  defp parse_status("incomplete"), do: :incomplete

  defp status_to_string(nil), do: nil
  defp status_to_string(:in_progress), do: "in_progress"
  defp status_to_string(:completed), do: "completed"
  defp status_to_string(:incomplete), do: "incomplete"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
