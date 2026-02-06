defmodule Codex.Voice.PipelineTest do
  use ExUnit.Case, async: true

  alias Codex.StreamQueue
  alias Codex.Voice.Config
  alias Codex.Voice.Config.TTSSettings
  alias Codex.Voice.Events.VoiceStreamEventAudio
  alias Codex.Voice.Events.VoiceStreamEventLifecycle
  alias Codex.Voice.Input.StreamedAudioInput
  alias Codex.Voice.Pipeline
  alias Codex.Voice.Result

  # Mock workflow for testing
  defmodule MockWorkflow do
    defstruct [:greeting]

    def run(_workflow, text) do
      ["You said: #{text}"]
    end

    def on_start(%{greeting: greeting}) when is_binary(greeting) do
      [greeting]
    end

    def on_start(_workflow) do
      ["Hello! How can I help?"]
    end
  end

  # Mock workflow without on_start
  defmodule SimpleWorkflow do
    defstruct []

    def run(_workflow, text) do
      ["Echo: #{text}"]
    end
  end

  # Mock STT model for testing
  defmodule MockSTT do
    defstruct [:model]

    def new(model \\ "mock-stt", _opts \\ []) do
      %__MODULE__{model: model}
    end

    def transcribe(_model, _input, _settings, _trace_data, _trace_audio) do
      {:ok, "Hello world"}
    end

    def create_session(_input, _settings, _trace_data, _trace_audio) do
      {:ok, self()}
    end
  end

  # Mock TTS model for testing
  defmodule MockTTS do
    defstruct [:model]

    def new(model \\ "mock-tts", _opts \\ []) do
      %__MODULE__{model: model}
    end

    def run(_model, text, _settings) do
      # Return simple audio chunks for testing
      [<<0, 0, 0, 0>>, "text:#{text}"]
    end
  end

  describe "new/1" do
    test "creates pipeline with required workflow" do
      pipeline = Pipeline.new(workflow: %MockWorkflow{})
      assert pipeline.workflow == %MockWorkflow{}
      assert pipeline.config != nil
    end

    test "creates pipeline with custom config" do
      config = Config.new(workflow_name: "Test Pipeline")
      pipeline = Pipeline.new(workflow: %MockWorkflow{}, config: config)
      assert pipeline.config.workflow_name == "Test Pipeline"
    end

    test "raises without workflow" do
      assert_raise KeyError, fn ->
        Pipeline.new([])
      end
    end
  end

  describe "Result.new/3" do
    test "creates a new result with queue" do
      tts_model = MockTTS.new()
      tts_settings = TTSSettings.new(voice: :nova)
      config = Config.new()

      result = Result.new(tts_model, tts_settings, config)

      assert result.tts_model == tts_model
      assert result.tts_settings == tts_settings
      assert result.config == config
      assert is_pid(result.queue)
      assert result.task == nil
      assert result.total_output_text == ""
    end

    test "creates result with nil settings using defaults" do
      tts_model = MockTTS.new()

      result = Result.new(tts_model, nil, nil)

      assert result.tts_settings == %TTSSettings{}
      assert result.config == %Config{}
    end
  end

  describe "Result.stream/1" do
    test "streams events from queue" do
      tts_model = MockTTS.new()
      result = Result.new(tts_model, %TTSSettings{}, %Config{})

      # Add some events to the queue
      Result.turn_started(result)
      Result.turn_done(result)
      Result.done(result)

      events = result |> Result.stream() |> Enum.to_list()

      assert length(events) == 3
      assert %VoiceStreamEventLifecycle{event: :turn_started} = Enum.at(events, 0)
      assert %VoiceStreamEventLifecycle{event: :turn_ended} = Enum.at(events, 1)
      assert %VoiceStreamEventLifecycle{event: :session_ended} = Enum.at(events, 2)
    end
  end

  describe "Result.add_text/2" do
    test "converts text to audio events" do
      tts_model = MockTTS.new()
      result = Result.new(tts_model, %TTSSettings{}, %Config{})

      updated_result = Result.add_text(result, "Hello")

      # Check that total_output_text is updated
      assert updated_result.total_output_text == "Hello"

      # Don't signal done, just check queue has audio events
      # Read directly from queue
      events = drain_queue(result.queue)
      refute events == []

      assert Enum.any?(events, fn
               %VoiceStreamEventAudio{} -> true
               _ -> false
             end)
    end

    test "ignores empty text" do
      tts_model = MockTTS.new()
      result = Result.new(tts_model, %TTSSettings{}, %Config{})

      updated_result = Result.add_text(result, "")

      assert updated_result.total_output_text == ""
    end
  end

  describe "Result lifecycle functions" do
    test "turn_started adds lifecycle event" do
      tts_model = MockTTS.new()
      result = Result.new(tts_model, %TTSSettings{}, %Config{})

      :ok = Result.turn_started(result)

      events = drain_queue(result.queue)
      assert [%VoiceStreamEventLifecycle{event: :turn_started}] = events
    end

    test "turn_done adds lifecycle event" do
      tts_model = MockTTS.new()
      result = Result.new(tts_model, %TTSSettings{}, %Config{})

      :ok = Result.turn_done(result)

      events = drain_queue(result.queue)
      assert [%VoiceStreamEventLifecycle{event: :turn_ended}] = events
    end

    test "done adds lifecycle event and done marker" do
      tts_model = MockTTS.new()
      result = Result.new(tts_model, %TTSSettings{}, %Config{})

      :ok = Result.done(result)

      events = drain_queue(result.queue)
      assert [%VoiceStreamEventLifecycle{event: :session_ended}] = events
    end
  end

  describe "Result.add_error/2" do
    test "adds error event and done marker" do
      tts_model = MockTTS.new()
      result = Result.new(tts_model, %TTSSettings{}, %Config{})

      error = %RuntimeError{message: "test error"}
      :ok = Result.add_error(result, error)

      events = drain_queue(result.queue)
      assert [%Codex.Voice.Events.VoiceStreamEventError{error: ^error}] = events
    end

    test "wraps non-exception errors" do
      tts_model = MockTTS.new()
      result = Result.new(tts_model, %TTSSettings{}, %Config{})

      :ok = Result.add_error(result, {:error, :some_reason})

      events = drain_queue(result.queue)
      assert [%Codex.Voice.Events.VoiceStreamEventError{error: %RuntimeError{}}] = events
    end
  end

  describe "MockWorkflow" do
    test "run returns response" do
      workflow = %MockWorkflow{}
      result = MockWorkflow.run(workflow, "test input")
      assert result == ["You said: test input"]
    end

    test "on_start returns greeting" do
      workflow = %MockWorkflow{}
      result = MockWorkflow.on_start(workflow)
      assert result == ["Hello! How can I help?"]
    end

    test "on_start uses custom greeting" do
      workflow = %MockWorkflow{greeting: "Welcome!"}
      result = MockWorkflow.on_start(workflow)
      assert result == ["Welcome!"]
    end
  end

  describe "SimpleWorkflow" do
    test "run returns echo" do
      workflow = %SimpleWorkflow{}
      result = SimpleWorkflow.run(workflow, "test")
      assert result == ["Echo: test"]
    end

    test "does not have on_start" do
      refute function_exported?(SimpleWorkflow, :on_start, 1)
    end
  end

  describe "pipeline worker lifecycle" do
    test "run/2 worker is not linked to the caller process" do
      previous_flag = Process.flag(:trap_exit, true)

      on_exit(fn ->
        Process.flag(:trap_exit, previous_flag)
      end)

      pipeline = Pipeline.new(workflow: %SimpleWorkflow{})
      audio = StreamedAudioInput.new()

      {:ok, result} = Pipeline.run(pipeline, audio)

      assert %Task{pid: task_pid} = result.task
      assert Process.alive?(task_pid)

      Process.exit(task_pid, :boom)
      refute_receive {:EXIT, ^task_pid, :boom}, 100
    end
  end

  # Helper function to drain all items from an Agent-backed queue
  defp drain_queue(queue_pid) do
    drain_queue_acc(queue_pid, [])
  end

  defp drain_queue_acc(queue_pid, acc) do
    item = dequeue_from_agent(queue_pid)

    case item do
      :empty -> Enum.reverse(acc)
      item -> drain_queue_acc(queue_pid, [item | acc])
    end
  end

  defp dequeue_from_agent(queue_pid) do
    case StreamQueue.try_pop(queue_pid) do
      {:ok, item} -> item
      :done -> :empty
      {:error, _reason} -> :empty
      :empty -> :empty
    end
  end
end
