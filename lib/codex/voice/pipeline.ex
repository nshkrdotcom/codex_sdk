defmodule Codex.Voice.Pipeline do
  @moduledoc """
  Orchestrates STT → Workflow → TTS voice pipelines.

  A voice pipeline provides an opinionated three-step flow for voice agents:

  1. **Transcribe** - Convert audio input to text using a speech-to-text model
  2. **Process** - Run the text through a workflow to generate a response
  3. **Synthesize** - Convert the response text to audio using a text-to-speech model

  ## Workflows

  A workflow is any module that implements a `run/2` function that takes the
  workflow struct and input text, returning an enumerable of response text
  chunks.

  For multi-turn conversations with `StreamedAudioInput`, workflows can
  optionally implement `on_start/1` to generate an initial greeting.

  ## Example

      # Define a simple workflow
      defmodule EchoWorkflow do
        defstruct []

        def run(_workflow, text) do
          ["You said: \#{text}"]
        end

        def on_start(_workflow) do
          ["Hello! I'm an echo bot. Say something!"]
        end
      end

      # Create and run the pipeline
      workflow = %EchoWorkflow{}
      pipeline = Pipeline.new(workflow: workflow)

      audio = AudioInput.new(audio_bytes)
      {:ok, result} = Pipeline.run(pipeline, audio)

      # Stream the results
      result
      |> Result.stream()
      |> Enum.each(fn event ->
        case event do
          %{type: :voice_stream_event_audio, data: data} ->
            play_audio(data)

          %{type: :voice_stream_event_lifecycle, event: :turn_ended} ->
            IO.puts("Turn complete!")

          %{type: :voice_stream_event_lifecycle, event: :session_ended} ->
            IO.puts("Session ended")

          %{type: :voice_stream_event_error, error: error} ->
            Logger.error("Error: \#{inspect(error)}")
        end
      end)

  ## Input Types

  - `AudioInput` - A static audio buffer for single-turn interactions
  - `StreamedAudioInput` - A streaming audio input for multi-turn conversations

  ## Configuration

  The pipeline can be configured with custom STT and TTS models, or it will
  use the default OpenAI models:

      config = Config.new(
        workflow_name: "Customer Support",
        tts_settings: TTSSettings.new(voice: :nova)
      )

      pipeline = Pipeline.new(
        workflow: workflow,
        config: config,
        stt_model: "whisper-1",
        tts_model: "tts-1-hd"
      )
  """

  alias Codex.Voice.Config
  alias Codex.Voice.Config.STTSettings
  alias Codex.Voice.Config.TTSSettings
  alias Codex.Voice.Input.AudioInput
  alias Codex.Voice.Input.StreamedAudioInput
  alias Codex.Voice.Models.OpenAIProvider
  alias Codex.Voice.Models.OpenAISTT
  alias Codex.Voice.Models.OpenAISTTSession
  alias Codex.Voice.Models.OpenAITTS
  alias Codex.Voice.Result

  require Logger

  defstruct [:workflow, :stt_model, :tts_model, :config]

  @type t :: %__MODULE__{
          workflow: struct(),
          stt_model: struct(),
          tts_model: struct(),
          config: Config.t()
        }

  @doc """
  Create a new voice pipeline.

  ## Options

  - `:workflow` - Required. The workflow module to run (must have a `run/2` function)
  - `:stt_model` - Speech-to-text model. Can be a model struct, model name string, or nil for default
  - `:tts_model` - Text-to-speech model. Can be a model struct, model name string, or nil for default
  - `:config` - Pipeline configuration (defaults to `%Config{}`)

  ## Examples

      # Simple pipeline with defaults
      pipeline = Pipeline.new(workflow: %MyWorkflow{})

      # Pipeline with custom models
      pipeline = Pipeline.new(
        workflow: %MyWorkflow{},
        stt_model: "whisper-1",
        tts_model: "tts-1-hd"
      )

      # Pipeline with full configuration
      pipeline = Pipeline.new(
        workflow: %MyWorkflow{},
        config: Config.new(
          workflow_name: "Support Agent",
          tts_settings: TTSSettings.new(voice: :nova)
        )
      )
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    workflow = Keyword.fetch!(opts, :workflow)
    config = Keyword.get(opts, :config) || %Config{}
    provider = config.model_provider || OpenAIProvider

    stt_model = resolve_stt_model(Keyword.get(opts, :stt_model), provider)
    tts_model = resolve_tts_model(Keyword.get(opts, :tts_model), provider)

    %__MODULE__{
      workflow: workflow,
      stt_model: stt_model,
      tts_model: tts_model,
      config: config
    }
  end

  @doc """
  Run the pipeline on audio input.

  ## Parameters

  - `pipeline` - The voice pipeline
  - `audio_input` - Either `AudioInput` for single-turn or `StreamedAudioInput` for multi-turn

  ## Returns

  - `{:ok, result}` - A `Result` struct that can be streamed for events.
    Errors that occur during processing are delivered as `VoiceStreamEventError`
    events in the result stream rather than being returned from this function.

  ## Examples

      # Single-turn with static audio
      audio = AudioInput.new(audio_bytes)
      {:ok, result} = Pipeline.run(pipeline, audio)

      # Multi-turn with streaming audio
      input = StreamedAudioInput.new()
      {:ok, result} = Pipeline.run(pipeline, input)

      # Push audio chunks to the input
      StreamedAudioInput.add(input, chunk1)
      StreamedAudioInput.add(input, chunk2)
      StreamedAudioInput.close(input)
  """
  @spec run(t(), AudioInput.t() | StreamedAudioInput.t()) :: {:ok, Result.t()}
  def run(%__MODULE__{} = pipeline, %AudioInput{} = audio) do
    run_single_turn(pipeline, audio)
  end

  def run(%__MODULE__{} = pipeline, %StreamedAudioInput{} = audio) do
    run_multi_turn(pipeline, audio)
  end

  # Private functions

  @spec resolve_stt_model(struct() | String.t() | nil, module()) :: struct()
  defp resolve_stt_model(%OpenAISTT{} = model, _provider), do: model
  defp resolve_stt_model(nil, provider), do: provider.get_stt_model(nil)
  defp resolve_stt_model(name, provider) when is_binary(name), do: provider.get_stt_model(name)

  @spec resolve_tts_model(struct() | String.t() | nil, module()) :: struct()
  defp resolve_tts_model(%OpenAITTS{} = model, _provider), do: model
  defp resolve_tts_model(nil, provider), do: provider.get_tts_model(nil)
  defp resolve_tts_model(name, provider) when is_binary(name), do: provider.get_tts_model(name)

  @spec run_single_turn(t(), AudioInput.t()) :: {:ok, Result.t()}
  defp run_single_turn(pipeline, audio) do
    tts_settings = pipeline.config.tts_settings || %TTSSettings{}
    result = Result.new(pipeline.tts_model, tts_settings, pipeline.config)

    task =
      Task.async(fn ->
        try do
          # Transcribe audio to text
          stt_settings = pipeline.config.stt_settings || %STTSettings{}

          {:ok, text} =
            OpenAISTT.transcribe(
              pipeline.stt_model,
              audio,
              stt_settings,
              pipeline.config.trace_include_sensitive_data,
              pipeline.config.trace_include_sensitive_audio_data
            )

          # Signal turn start
          Result.turn_started(result)

          # Run workflow and convert each response to audio
          pipeline.workflow
          |> apply_workflow(:run, [text])
          |> Enum.each(fn response_text ->
            Result.add_text(result, response_text)
          end)

          # Signal turn and session completion
          Result.turn_done(result)
          Result.done(result)
        rescue
          e ->
            Logger.error("Pipeline error: #{inspect(e)}")
            Result.add_error(result, e)
        end
      end)

    result = Result.set_task(result, task)
    {:ok, result}
  end

  @spec run_multi_turn(t(), StreamedAudioInput.t()) :: {:ok, Result.t()}
  defp run_multi_turn(pipeline, audio) do
    tts_settings = pipeline.config.tts_settings || %TTSSettings{}
    result = Result.new(pipeline.tts_model, tts_settings, pipeline.config)

    task =
      Task.async(fn ->
        try do
          # Call on_start if workflow supports it
          maybe_call_on_start(pipeline.workflow, result)

          # Create streaming transcription session
          stt_settings = pipeline.config.stt_settings || %STTSettings{}

          {:ok, session} =
            OpenAISTT.create_session(
              audio,
              stt_settings,
              pipeline.config.trace_include_sensitive_data,
              pipeline.config.trace_include_sensitive_audio_data
            )

          # Process turns
          session
          |> OpenAISTTSession.transcribe_turns()
          |> Enum.each(fn text ->
            Result.turn_started(result)

            pipeline.workflow
            |> apply_workflow(:run, [text])
            |> Enum.each(fn response_text ->
              Result.add_text(result, response_text)
            end)

            Result.turn_done(result)
          end)

          # Clean up session and signal completion
          OpenAISTTSession.close(session)
          Result.done(result)
        rescue
          e ->
            Logger.error("Pipeline error: #{inspect(e)}")
            Result.add_error(result, e)
        end
      end)

    result = Result.set_task(result, task)
    {:ok, result}
  end

  @spec maybe_call_on_start(struct(), Result.t()) :: :ok
  defp maybe_call_on_start(workflow, result) do
    module = workflow.__struct__

    if function_exported?(module, :on_start, 1) do
      Result.turn_started(result)

      workflow
      |> apply_workflow(:on_start, [])
      |> Enum.each(fn text ->
        Result.add_text(result, text)
      end)

      Result.turn_done(result)
    end

    :ok
  rescue
    e ->
      Logger.warning("on_start/1 failed: #{inspect(e)}")
      :ok
  end

  @spec apply_workflow(struct(), atom(), list()) :: Enumerable.t()
  defp apply_workflow(workflow, fun, args) do
    module = workflow.__struct__
    apply(module, fun, [workflow | args])
  end
end
