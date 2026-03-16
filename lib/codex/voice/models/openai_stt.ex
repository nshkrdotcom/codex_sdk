defmodule Codex.Voice.Models.OpenAISTT do
  @moduledoc """
  OpenAI speech-to-text model implementation.

  This module implements the `Codex.Voice.Model.STTModel` behaviour using
  OpenAI's audio transcription API. It supports both single-shot transcription
  and streamed-input sessions that transcribe buffered audio once the input
  closes.

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
  alias Codex.Config.Defaults
  alias Codex.Net.CA
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

  @default_model Defaults.stt_model()
  @default_base_url Defaults.openai_api_base_url()

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
    api_key = model.api_key || Auth.direct_api_key()

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

    request_client = resolve_request_client(model.client)

    req_opts =
      [headers: [{"Authorization", "Bearer #{api_key}"}], form_multipart: multipart]
      |> CA.merge_req_options()

    case request_client.(
           "#{model.base_url}/audio/transcriptions",
           req_opts
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
        %__MODULE__{} = model,
        %StreamedAudioInput{} = input,
        %STTSettings{} = settings,
        trace_include_sensitive_data,
        trace_include_sensitive_audio_data
      ) do
    OpenAISTTSession.start_link(
      input: input,
      settings: settings,
      stt_model: model,
      trace_include_sensitive_data: trace_include_sensitive_data,
      trace_include_sensitive_audio_data: trace_include_sensitive_audio_data
    )
  end

  @doc false
  def create_session(
        %StreamedAudioInput{} = input,
        %STTSettings{} = settings,
        trace_include_sensitive_data,
        trace_include_sensitive_audio_data
      ) do
    create_session(
      new(),
      input,
      settings,
      trace_include_sensitive_data,
      trace_include_sensitive_audio_data
    )
  end

  defp maybe_add_param(list, _key, nil), do: list
  defp maybe_add_param(list, key, value) when is_atom(key), do: list ++ [{key, to_string(value)}]

  defp resolve_request_client(nil), do: &Req.post/2
  defp resolve_request_client(client) when is_function(client, 2), do: client
  defp resolve_request_client(client) when is_atom(client), do: &client.post/2

  @spec format_temperature(float() | nil) :: String.t() | nil
  defp format_temperature(nil), do: nil
  defp format_temperature(temp), do: Float.to_string(temp)
end

defmodule Codex.Voice.Models.OpenAISTTSession do
  @moduledoc """
  Buffered streamed transcription session.

  This GenServer consumes a `StreamedAudioInput` until it closes, then submits
  the aggregated audio to the configured STT model and yields completed
  transcript turns to callers.
  """

  use GenServer

  alias Codex.Auth
  alias Codex.Config.Defaults
  alias Codex.TaskSupport
  alias Codex.Voice.Config.STTSettings
  alias Codex.Voice.Input.AudioInput
  alias Codex.Voice.Input.StreamedAudioInput
  alias Codex.Voice.Models.OpenAISTT

  @behaviour Codex.Voice.Model.StreamedTranscriptionSession

  defstruct [
    :input,
    :settings,
    :model,
    :api_key,
    :trace_include_sensitive_data,
    :trace_include_sensitive_audio_data,
    :stt_model,
    :websocket,
    :listener_task,
    :stream_task,
    :completion,
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
          stt_model: OpenAISTT.t(),
          websocket: pid() | nil,
          listener_task: Task.t() | nil,
          stream_task: Task.t() | nil,
          completion: :done | {:error, term()} | nil,
          transcripts: [String.t()],
          waiters: [{GenServer.from(), reference()}]
        }

  @default_turn_detection Defaults.stt_default_turn_detection()

  @doc """
  Start a new streaming transcription session.

  ## Options

  - `:input` - StreamedAudioInput to read audio from (required)
  - `:settings` - STTSettings for transcription options (required)
  - `:stt_model` - Optional `OpenAISTT` model struct to use as-is
  - `:model` - Model name to use when `:stt_model` is not provided
  - `:api_key` - API key (defaults to OPENAI_API_KEY env var)
  - `:base_url` - API base URL when `:stt_model` is not provided
  - `:client` - Optional HTTP client when `:stt_model` is not provided
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
    stt_model = resolve_stt_model(opts)
    api_key = stt_model.api_key || Auth.direct_api_key()

    state = %__MODULE__{
      input: input,
      settings: settings,
      model: stt_model.model,
      api_key: api_key,
      trace_include_sensitive_data: Keyword.get(opts, :trace_include_sensitive_data, true),
      trace_include_sensitive_audio_data:
        Keyword.get(opts, :trace_include_sensitive_audio_data, false),
      stt_model: %{stt_model | api_key: api_key},
      completion: nil
    }

    case start_transcription_task(state) do
      {:ok, task} ->
        {:ok, %{state | stream_task: task}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call(:get_transcript, from, state) do
    case state.transcripts do
      [text | rest] ->
        {:reply, {:ok, text}, %{state | transcripts: rest}}

      [] ->
        case state.completion do
          :done ->
            {:reply, :done, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}

          nil ->
            monitor_ref = monitor_waiter(from)
            {:noreply, %{state | waiters: state.waiters ++ [{from, monitor_ref}]}}
        end
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

  def handle_info({ref, _result}, %{stream_task: %Task{ref: ref}} = state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        {:DOWN, ref, :process, pid, reason},
        %{stream_task: %Task{ref: ref, pid: pid}} = state
      ) do
    state = %{state | stream_task: nil}

    case {reason, state.completion} do
      {:normal, _} ->
        {:noreply, state}

      {:shutdown, _} ->
        {:noreply, state}

      {{:shutdown, _}, _} ->
        {:noreply, state}

      {_reason, nil} ->
        finish_with_error(state, {:task_exit, reason})

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    waiters =
      Enum.reject(state.waiters, fn {_waiter, monitor_ref} ->
        monitor_ref == ref
      end)

    {:noreply, %{state | waiters: waiters}}
  end

  @impl GenServer
  def handle_info(:session_complete, state) do
    finish_with_completion(state)
  end

  @impl GenServer
  def handle_info({:session_error, reason}, state) do
    finish_with_error(state, reason)
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

  defp resolve_stt_model(opts) do
    case Keyword.get(opts, :stt_model) do
      %OpenAISTT{} = model ->
        model

      nil ->
        OpenAISTT.new(
          Keyword.get(opts, :model, OpenAISTT.model_name()),
          api_key: Keyword.get(opts, :api_key),
          base_url: Keyword.get(opts, :base_url, Defaults.openai_api_base_url()),
          client: Keyword.get(opts, :client)
        )
    end
  end

  defp start_transcription_task(state) do
    session = self()

    runner = fn ->
      run_transcription(session, state)
    end

    TaskSupport.async_nolink(runner)
  end

  defp run_transcription(session, state) do
    case collect_audio(state.input) do
      <<>> ->
        send(session, :session_complete)

      audio_data ->
        audio_input = AudioInput.new(audio_data)

        case OpenAISTT.transcribe(
               state.stt_model,
               audio_input,
               state.settings,
               state.trace_include_sensitive_data,
               state.trace_include_sensitive_audio_data
             ) do
          {:ok, text} ->
            maybe_send_transcript(session, text)
            send(session, :session_complete)

          {:error, reason} ->
            send(session, {:session_error, reason})
        end
    end
  rescue
    error ->
      send(session, {:session_error, error})
  catch
    kind, reason ->
      send(session, {:session_error, {kind, reason}})
  end

  defp collect_audio(%StreamedAudioInput{} = input) do
    input
    |> StreamedAudioInput.stream()
    |> Enum.reduce([], fn chunk, acc -> [chunk | acc] end)
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp maybe_send_transcript(session, text) do
    if String.trim(text) != "" do
      send(session, {:transcript, text})
    end

    :ok
  end

  defp finish_with_completion(state) do
    Enum.each(state.waiters, fn {waiter, monitor_ref} ->
      Process.demonitor(monitor_ref, [:flush])
      GenServer.reply(waiter, :done)
    end)

    {:noreply, %{state | waiters: [], completion: :done}}
  end

  defp finish_with_error(state, reason) do
    Enum.each(state.waiters, fn {waiter, monitor_ref} ->
      Process.demonitor(monitor_ref, [:flush])
      GenServer.reply(waiter, {:error, reason})
    end)

    {:noreply, %{state | waiters: [], completion: {:error, reason}}}
  end

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
