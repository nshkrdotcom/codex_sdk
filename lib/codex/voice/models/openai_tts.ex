defmodule Codex.Voice.Models.OpenAITTS do
  @moduledoc """
  OpenAI text-to-speech model implementation.

  This module implements the `Codex.Voice.Model.TTSModel` behaviour using
  OpenAI's audio speech API. It converts text to audio and returns the
  result as a stream of PCM bytes.

  ## Default Model

  The default model is `gpt-4o-mini-tts`, which provides high-quality
  text-to-speech with support for multiple voices and instructions.

  ## Voices

  The following voices are available:
  - `:alloy` - Neutral and balanced
  - `:ash` - Warm and conversational (default)
  - `:coral` - Clear and articulate
  - `:echo` - Soft and thoughtful
  - `:fable` - Expressive and dramatic
  - `:onyx` - Deep and authoritative
  - `:nova` - Friendly and upbeat
  - `:sage` - Calm and measured
  - `:shimmer` - Bright and energetic

  ## Example

      model = OpenAITTS.new()
      settings = TTSSettings.new(voice: :nova, speed: 1.0)

      audio_stream = OpenAITTS.run(model, "Hello, world!", settings)

      Enum.each(audio_stream, fn chunk ->
        # Process PCM audio chunk
      end)
  """

  @behaviour Codex.Voice.Model.TTSModel

  alias Codex.Voice.Config.TTSSettings

  defstruct [:model, :client, :api_key, :base_url]

  @type t :: %__MODULE__{
          model: String.t(),
          client: term(),
          api_key: String.t() | nil,
          base_url: String.t()
        }

  @default_model "gpt-4o-mini-tts"
  @default_voice :ash
  @default_base_url "https://api.openai.com/v1"

  @doc """
  Create a new OpenAI TTS model.

  ## Options

  - `:client` - Optional HTTP client (for testing)
  - `:api_key` - API key (defaults to OPENAI_API_KEY env var)
  - `:base_url` - API base URL (defaults to OpenAI)

  ## Examples

      iex> model = Codex.Voice.Models.OpenAITTS.new()
      iex> model.model
      "gpt-4o-mini-tts"

      iex> model = Codex.Voice.Models.OpenAITTS.new("tts-1")
      iex> model.model
      "tts-1"
  """
  @spec new(String.t() | nil, keyword()) :: t()
  def new(model \\ nil, opts \\ []) do
    %__MODULE__{
      model: model || @default_model,
      client: Keyword.get(opts, :client),
      api_key: Keyword.get(opts, :api_key),
      base_url: Keyword.get(opts, :base_url, @default_base_url)
    }
  end

  @impl true
  def model_name, do: @default_model

  @doc """
  Convert text to speech, returning a stream of PCM audio bytes.

  ## Parameters

  - `model` - The OpenAITTS model struct
  - `text` - The text to convert to speech
  - `settings` - TTSSettings with voice and speed options

  ## Returns

  An enumerable that yields audio bytes in PCM format. Each chunk
  is approximately 1024 bytes.

  ## Example

      model = OpenAITTS.new()
      settings = TTSSettings.new(voice: :nova)

      audio_chunks =
        OpenAITTS.run(model, "Hello!", settings)
        |> Enum.to_list()
  """
  @spec run(t(), String.t(), TTSSettings.t()) :: Enumerable.t()
  def run(%__MODULE__{} = model, text, %TTSSettings{} = settings) do
    api_key = model.api_key || System.get_env("OPENAI_API_KEY")
    voice = voice_to_string(settings.voice || @default_voice)

    body =
      %{
        model: model.model,
        input: text,
        voice: voice,
        response_format: "pcm"
      }
      |> maybe_add_speed(settings.speed)
      |> maybe_add_instructions(settings.instructions)

    Stream.resource(
      fn -> start_streaming_request(model.base_url, api_key, body) end,
      &receive_chunk/1,
      &cleanup_request/1
    )
  end

  @spec start_streaming_request(String.t(), String.t(), map()) ::
          {:streaming, Req.Response.t()} | {:error, term()}
  defp start_streaming_request(base_url, api_key, body) do
    # Create a streaming request
    case Req.post("#{base_url}/audio/speech",
           headers: [
             {"Authorization", "Bearer #{api_key}"},
             {"Content-Type", "application/json"}
           ],
           json: body,
           into: :self
         ) do
      {:ok, response} ->
        {:streaming, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec receive_chunk({:streaming, Req.Response.t()} | {:error, term()}) ::
          {[binary()], {:streaming, Req.Response.t()}}
          | {:halt, {:streaming, Req.Response.t()}}
          | {:halt, {:error, term()}}
  defp receive_chunk({:error, _reason} = state) do
    {:halt, state}
  end

  defp receive_chunk({:streaming, _response} = state) do
    receive do
      {_ref, {:data, chunk}} ->
        {[chunk], state}

      {_ref, :done} ->
        {:halt, state}

      {_ref, {:error, reason}} ->
        {:halt, {:error, reason}}

      {:DOWN, _ref, :process, _pid, _reason} ->
        {:halt, state}
    after
      30_000 ->
        # Timeout after 30 seconds of no data
        {:halt, {:error, :timeout}}
    end
  end

  @spec cleanup_request({:streaming, Req.Response.t()} | {:error, term()}) :: :ok
  defp cleanup_request(_state), do: :ok

  @spec voice_to_string(TTSSettings.voice()) :: String.t()
  defp voice_to_string(voice) when is_atom(voice), do: Atom.to_string(voice)
  defp voice_to_string(voice) when is_binary(voice), do: voice

  @spec maybe_add_speed(map(), float() | nil) :: map()
  defp maybe_add_speed(body, nil), do: body
  defp maybe_add_speed(body, speed), do: Map.put(body, :speed, speed)

  @spec maybe_add_instructions(map(), String.t() | nil) :: map()
  defp maybe_add_instructions(body, nil), do: body

  defp maybe_add_instructions(body, instructions) do
    Map.put(body, :extra_body, %{instructions: instructions})
  end
end
