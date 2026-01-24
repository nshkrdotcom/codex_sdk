defmodule Codex do
  @moduledoc """
  Public entry point for the Codex SDK.

  Provides helpers to start new threads or resume existing ones.

  ## Realtime Voice

  For real-time voice interactions using WebSockets:

      # Define an agent
      agent = Codex.Realtime.agent(
        name: "VoiceAssistant",
        instructions: "You are a helpful voice assistant."
      )

      # Create and run a session
      {:ok, session} = Codex.Realtime.run(agent)

      # Send audio and subscribe to events
      Codex.Realtime.send_audio(session, audio_bytes)
      Codex.Realtime.subscribe(session, self())

      receive do
        {:session_event, event} -> handle_event(event)
      end

  See `Codex.Realtime` for full documentation.

  ## Voice Pipeline

  For non-realtime voice processing (STT -> Workflow -> TTS):

      workflow = Codex.Voice.simple_workflow(fn text ->
        ["You said: \#{text}"]
      end)

      {:ok, result} = Codex.Voice.run(audio, workflow: workflow)

  See `Codex.Voice` for full documentation.
  """

  alias Codex.Options
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions

  @type start_opts :: map() | keyword() | Options.t()
  @type thread_opts :: map() | keyword() | ThreadOptions.t()

  @doc """
  Starts a new Codex thread returning a `%Codex.Thread{}` struct.
  """
  @spec start_thread(start_opts(), thread_opts()) ::
          {:ok, Thread.t()} | {:error, term()}
  def start_thread(opts \\ %{}, thread_opts \\ %{}) do
    with {:ok, codex_opts} <- normalize_options(opts),
         {:ok, thread_opts} <- normalize_thread_options(thread_opts) do
      {:ok, Thread.build(codex_opts, thread_opts)}
    end
  end

  @doc """
  Resumes an existing thread with the given `thread_id`.

  Pass `:last` to resume the most recent recorded session (equivalent to
  `codex exec resume --last`).
  """
  @spec resume_thread(String.t() | :last, start_opts(), thread_opts()) ::
          {:ok, Thread.t()} | {:error, term()}
  def resume_thread(thread_id, opts \\ %{}, thread_opts \\ %{})

  def resume_thread(:last, opts, thread_opts) do
    with {:ok, codex_opts} <- normalize_options(opts),
         {:ok, thread_opts} <- normalize_thread_options(thread_opts) do
      {:ok, Thread.build(codex_opts, thread_opts, resume: :last)}
    end
  end

  def resume_thread(thread_id, opts, thread_opts) when is_binary(thread_id) do
    with {:ok, codex_opts} <- normalize_options(opts),
         {:ok, thread_opts} <- normalize_thread_options(thread_opts) do
      {:ok, Thread.build(codex_opts, thread_opts, thread_id: thread_id)}
    end
  end

  @doc """
  Lists session files persisted by the Codex CLI.

  Returns entries parsed from `~/.codex/sessions` by default.
  """
  @spec list_sessions(keyword()) ::
          {:ok, [Codex.Sessions.session_entry()]} | {:error, term()}
  def list_sessions(opts \\ []) do
    Codex.Sessions.list_sessions(opts)
  end

  defp normalize_options(%Options{} = opts), do: {:ok, opts}
  defp normalize_options(opts), do: Options.new(opts)

  defp normalize_thread_options(%ThreadOptions{} = opts), do: {:ok, opts}
  defp normalize_thread_options(opts), do: ThreadOptions.new(opts)

  # -- Realtime delegations ---------------------------------------------------

  @doc """
  Create and start a realtime session with an agent.

  Delegates to `Codex.Realtime.run/2`.

  ## Example

      agent = Codex.realtime_agent(name: "Assistant", instructions: "Be helpful.")
      {:ok, session} = Codex.realtime_run(agent)
  """
  @spec realtime_run(Codex.Realtime.Agent.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  defdelegate realtime_run(agent, opts \\ []), to: Codex.Realtime, as: :run

  @doc """
  Create a realtime agent.

  Delegates to `Codex.Realtime.agent/1`.

  ## Example

      agent = Codex.realtime_agent(
        name: "VoiceBot",
        instructions: "You are a helpful voice bot.",
        tools: [my_tool]
      )
  """
  @spec realtime_agent(keyword()) :: Codex.Realtime.Agent.t()
  defdelegate realtime_agent(opts), to: Codex.Realtime, as: :agent

  # -- Voice delegations ------------------------------------------------------

  @doc """
  Create and run a voice pipeline.

  Delegates to `Codex.Voice.run/2`.

  ## Example

      workflow = Codex.Voice.simple_workflow(fn text -> ["Echo: \#{text}"] end)
      {:ok, result} = Codex.voice_run(audio, workflow: workflow)
  """
  @spec voice_run(
          Codex.Voice.Input.AudioInput.t() | Codex.Voice.Input.StreamedAudioInput.t(),
          keyword()
        ) :: {:ok, Codex.Voice.Result.t()}
  defdelegate voice_run(audio, opts), to: Codex.Voice, as: :run

  @doc """
  Create an audio input from binary data.

  Delegates to `Codex.Voice.audio_input/2`.

  ## Example

      audio = Codex.voice_audio_input(File.read!("recording.pcm"))
  """
  @spec voice_audio_input(binary(), keyword()) :: Codex.Voice.Input.AudioInput.t()
  defdelegate voice_audio_input(data, opts \\ []), to: Codex.Voice, as: :audio_input
end
