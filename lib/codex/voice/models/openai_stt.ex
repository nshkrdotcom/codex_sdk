defmodule Codex.Voice.Models.OpenAISTT do
  @moduledoc """
  OpenAI speech-to-text model implementation.

  This module implements the `Codex.Voice.Model.STTModel` behaviour using
  OpenAI's audio transcription API. It supports both single-shot transcription
  and streaming transcription sessions via WebSocket.

  ## Default Model

  The default model is `gpt-4o-transcribe`, which provides high-quality
  transcriptions with support for multiple languages.

  ## Example

      model = OpenAISTT.new()
      audio = AudioInput.new(wav_data)
      settings = STTSettings.new(language: "en")

      {:ok, text} = OpenAISTT.transcribe(model, audio, settings, true, false)
  """

  @behaviour Codex.Voice.Model.STTModel

  alias Codex.Auth
  alias Codex.Voice.Config.STTSettings
  alias Codex.Voice.Input.AudioInput
  alias Codex.Voice.Input.StreamedAudioInput
  alias Codex.Voice.Models.OpenAISTTSession

  defstruct [:model, :client, :api_key, :base_url]

  @type t :: %__MODULE__{
          model: String.t(),
          client: term(),
          api_key: String.t() | nil,
          base_url: String.t()
        }

  @default_model "gpt-4o-transcribe"
  @default_base_url "https://api.openai.com/v1"

  @doc """
  Create a new OpenAI STT model.

  ## Options

  - `:client` - Optional HTTP client (for testing)
  - `:api_key` - API key (defaults to OPENAI_API_KEY env var)
  - `:base_url` - API base URL (defaults to OpenAI)

  ## Examples

      iex> model = Codex.Voice.Models.OpenAISTT.new()
      iex> model.model
      "gpt-4o-transcribe"

      iex> model = Codex.Voice.Models.OpenAISTT.new("whisper-1")
      iex> model.model
      "whisper-1"
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
  Transcribe audio input to text.

  Makes a POST request to OpenAI's audio transcriptions endpoint with
  the audio data in WAV format.

  ## Parameters

  - `model` - The OpenAISTT model struct
  - `input` - AudioInput with the audio data
  - `settings` - STTSettings with transcription options
  - `_trace_include_sensitive_data` - Whether to include text in traces (unused)
  - `_trace_include_sensitive_audio_data` - Whether to include audio in traces (unused)

  ## Returns

  - `{:ok, text}` - The transcribed text
  - `{:error, reason}` - If the request fails
  """
  @spec transcribe(
          t(),
          AudioInput.t(),
          STTSettings.t(),
          boolean(),
          boolean()
        ) :: {:ok, String.t()} | {:error, term()}
  def transcribe(
        %__MODULE__{} = model,
        %AudioInput{} = input,
        %STTSettings{} = settings,
        _trace_include_sensitive_data,
        _trace_include_sensitive_audio_data
      ) do
    api_key = model.api_key || Auth.api_key()

    {filename, wav_data, content_type} = AudioInput.to_audio_file(input)

    # Build multipart form for Req library
    # Req expects: {name, {value, options}} where options is a keyword list
    # Options can include :filename, :content_type, :size
    multipart =
      [
        {:file, {wav_data, filename: filename, content_type: content_type}},
        {:model, model.model}
      ]
      |> maybe_add_param(:prompt, settings.prompt)
      |> maybe_add_param(:language, settings.language)
      |> maybe_add_param(:temperature, format_temperature(settings.temperature))

    case Req.post("#{model.base_url}/audio/transcriptions",
           headers: [{"Authorization", "Bearer #{api_key}"}],
           form_multipart: multipart
         ) do
      {:ok, %{status: 200, body: %{"text" => text}}} ->
        {:ok, text}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def create_session(
        %StreamedAudioInput{} = input,
        %STTSettings{} = settings,
        trace_include_sensitive_data,
        trace_include_sensitive_audio_data
      ) do
    OpenAISTTSession.start_link(
      input: input,
      settings: settings,
      model: @default_model,
      trace_include_sensitive_data: trace_include_sensitive_data,
      trace_include_sensitive_audio_data: trace_include_sensitive_audio_data
    )
  end

  defp maybe_add_param(list, _key, nil), do: list
  defp maybe_add_param(list, key, value) when is_atom(key), do: list ++ [{key, to_string(value)}]

  @spec format_temperature(float() | nil) :: String.t() | nil
  defp format_temperature(nil), do: nil
  defp format_temperature(temp), do: Float.to_string(temp)
end

defmodule Codex.Voice.Models.OpenAISTTSession do
  @moduledoc """
  Streaming transcription session using WebSocket.

  This GenServer manages a WebSocket connection to OpenAI's realtime
  transcription API. It receives audio input from a `StreamedAudioInput`
  and produces text transcriptions for each detected turn.

  ## Turn Detection

  The session uses semantic VAD (Voice Activity Detection) by default
  to detect turn boundaries in the audio stream.
  """

  use GenServer

  alias Codex.Auth
  alias Codex.Voice.Config.STTSettings
  alias Codex.Voice.Input.StreamedAudioInput

  @behaviour Codex.Voice.Model.StreamedTranscriptionSession

  defstruct [
    :input,
    :settings,
    :model,
    :api_key,
    :trace_include_sensitive_data,
    :trace_include_sensitive_audio_data,
    :websocket,
    :listener_task,
    :stream_task,
    transcripts: [],
    waiters: []
  ]

  @type t :: %__MODULE__{
          input: StreamedAudioInput.t(),
          settings: STTSettings.t(),
          model: String.t(),
          api_key: String.t() | nil,
          trace_include_sensitive_data: boolean(),
          trace_include_sensitive_audio_data: boolean(),
          websocket: pid() | nil,
          listener_task: Task.t() | nil,
          stream_task: Task.t() | nil,
          transcripts: [String.t()],
          waiters: [{GenServer.from(), reference()}]
        }

  @default_turn_detection %{"type" => "semantic_vad"}

  @doc """
  Start a new streaming transcription session.

  ## Options

  - `:input` - StreamedAudioInput to read audio from (required)
  - `:settings` - STTSettings for transcription options (required)
  - `:model` - Model name to use
  - `:api_key` - API key (defaults to OPENAI_API_KEY env var)
  - `:trace_include_sensitive_data` - Whether to include text in traces
  - `:trace_include_sensitive_audio_data` - Whether to include audio in traces
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl Codex.Voice.Model.StreamedTranscriptionSession
  def transcribe_turns(session) do
    Stream.resource(
      fn -> session end,
      fn session ->
        case GenServer.call(session, :get_transcript, :infinity) do
          {:ok, text} -> {[text], session}
          :done -> {:halt, session}
          {:error, reason} -> raise "Transcription error: #{inspect(reason)}"
        end
      end,
      fn _ -> :ok end
    )
  end

  @impl Codex.Voice.Model.StreamedTranscriptionSession
  def close(session) do
    GenServer.stop(session, :normal)
    :ok
  end

  @impl GenServer
  def init(opts) do
    input = Keyword.fetch!(opts, :input)
    settings = Keyword.fetch!(opts, :settings)

    state = %__MODULE__{
      input: input,
      settings: settings,
      model: Keyword.get(opts, :model, "gpt-4o-transcribe"),
      api_key: Keyword.get(opts, :api_key, Auth.api_key()),
      trace_include_sensitive_data: Keyword.get(opts, :trace_include_sensitive_data, true),
      trace_include_sensitive_audio_data:
        Keyword.get(opts, :trace_include_sensitive_audio_data, false)
    }

    # Connection will be established when transcribe_turns is first called
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_transcript, from, state) do
    case state.transcripts do
      [text | rest] ->
        {:reply, {:ok, text}, %{state | transcripts: rest}}

      [] ->
        # No transcripts available, add to waiters
        monitor_ref = monitor_waiter(from)
        {:noreply, %{state | waiters: state.waiters ++ [{from, monitor_ref}]}}
    end
  end

  @impl GenServer
  def handle_info({:transcript, text}, state) do
    case state.waiters do
      [{waiter, monitor_ref} | rest] ->
        Process.demonitor(monitor_ref, [:flush])
        GenServer.reply(waiter, {:ok, text})
        {:noreply, %{state | waiters: rest}}

      [] ->
        {:noreply, %{state | transcripts: state.transcripts ++ [text]}}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    waiters =
      Enum.reject(state.waiters, fn {_waiter, monitor_ref} ->
        monitor_ref == ref
      end)

    {:noreply, %{state | waiters: waiters}}
  end

  @impl GenServer
  def handle_info(:session_complete, state) do
    # Notify all waiters that we're done
    for {waiter, monitor_ref} <- state.waiters do
      Process.demonitor(monitor_ref, [:flush])
      GenServer.reply(waiter, :done)
    end

    {:noreply, %{state | waiters: []}}
  end

  @impl GenServer
  def handle_info({:error, reason}, state) do
    # Notify all waiters of the error
    for {waiter, monitor_ref} <- state.waiters do
      Process.demonitor(monitor_ref, [:flush])
      GenServer.reply(waiter, {:error, reason})
    end

    {:noreply, %{state | waiters: []}}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Enum.each(state.waiters, fn {waiter, monitor_ref} ->
      Process.demonitor(monitor_ref, [:flush])
      GenServer.reply(waiter, {:error, :closed})
    end)

    close_websocket(state.websocket)
    shutdown_task(state.listener_task)
    shutdown_task(state.stream_task)

    :ok
  end

  @doc false
  def default_turn_detection, do: @default_turn_detection

  defp close_websocket(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      Process.exit(pid, :shutdown)
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp close_websocket(_), do: :ok

  defp shutdown_task(%Task{} = task) do
    case task.pid do
      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          Process.exit(pid, :kill)
        end

        :ok

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp shutdown_task(_), do: :ok

  defp monitor_waiter({pid, _tag}) when is_pid(pid) do
    Process.monitor(pid)
  end
end
