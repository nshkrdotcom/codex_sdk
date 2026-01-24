defmodule Codex.VoiceIntegrationTest do
  @moduledoc """
  Integration tests for Codex.Voice.

  These tests verify the integration between Voice pipeline components.
  Tests requiring actual API access are tagged with `:integration` and skipped by default.
  """
  use ExUnit.Case, async: true

  alias Codex.Voice
  alias Codex.Voice.Config
  alias Codex.Voice.Input.AudioInput
  alias Codex.Voice.Input.StreamedAudioInput
  alias Codex.Voice.Pipeline
  alias Codex.Voice.SimpleWorkflow

  @moduletag :voice_integration

  describe "Codex.Voice convenience functions" do
    test "audio_input/2 creates AudioInput with defaults" do
      data = <<0, 0, 255, 127>>
      input = Voice.audio_input(data)

      assert %AudioInput{} = input
      assert input.data == data
      assert input.frame_rate == 24_000
      assert input.sample_width == 2
      assert input.channels == 1
    end

    test "audio_input/2 accepts custom options" do
      data = <<0, 0>>
      input = Voice.audio_input(data, frame_rate: 16_000, channels: 2)

      assert input.frame_rate == 16_000
      assert input.channels == 2
    end

    test "streamed_input/0 creates StreamedAudioInput" do
      input = Voice.streamed_input()

      assert %StreamedAudioInput{} = input
      assert is_pid(input.queue)
    end

    test "simple_workflow/2 creates SimpleWorkflow" do
      workflow = Voice.simple_workflow(fn text -> ["Echo: #{text}"] end)

      assert %SimpleWorkflow{} = workflow
      assert is_function(workflow.handler, 1)
    end

    test "simple_workflow/2 with greeting" do
      workflow =
        Voice.simple_workflow(
          fn text -> ["Echo: #{text}"] end,
          greeting: "Hello!"
        )

      assert workflow.greeting == "Hello!"
    end

    test "config/1 creates Config" do
      config = Voice.config(workflow_name: "Test Workflow")

      assert %Config{} = config
      assert config.workflow_name == "Test Workflow"
    end
  end

  describe "Codex.Voice.Pipeline creation" do
    test "creates pipeline with workflow" do
      workflow = SimpleWorkflow.new(fn text -> ["Response: #{text}"] end)
      pipeline = Pipeline.new(workflow: workflow)

      assert %Pipeline{} = pipeline
      assert pipeline.workflow == workflow
    end

    test "creates pipeline with custom config" do
      workflow = SimpleWorkflow.new(fn text -> [text] end)
      config = Config.new(workflow_name: "Custom")

      pipeline = Pipeline.new(workflow: workflow, config: config)

      assert pipeline.config.workflow_name == "Custom"
    end
  end

  describe "Codex main module delegation" do
    test "voice_audio_input/2 delegates to Codex.Voice.audio_input/2" do
      data = <<1, 2, 3, 4>>
      input = Codex.voice_audio_input(data)

      assert %AudioInput{} = input
      assert input.data == data
    end
  end

  describe "StreamedAudioInput operations" do
    test "add/2 and get/1 work correctly" do
      input = StreamedAudioInput.new()

      :ok = StreamedAudioInput.add(input, <<1, 2>>)
      :ok = StreamedAudioInput.add(input, <<3, 4>>)

      assert {:ok, <<1, 2>>} = StreamedAudioInput.get(input)
      assert {:ok, <<3, 4>>} = StreamedAudioInput.get(input)
      assert :empty = StreamedAudioInput.get(input)
    end

    test "close/1 signals end of stream" do
      input = StreamedAudioInput.new()

      :ok = StreamedAudioInput.add(input, <<1, 2>>)
      :ok = StreamedAudioInput.close(input)

      assert {:ok, <<1, 2>>} = StreamedAudioInput.get(input)
      assert :eof = StreamedAudioInput.get(input)
    end

    test "stream/1 yields all chunks" do
      input = StreamedAudioInput.new()

      spawn(fn ->
        StreamedAudioInput.add(input, <<1, 2>>)
        StreamedAudioInput.add(input, <<3, 4>>)
        StreamedAudioInput.close(input)
      end)

      chunks = input |> StreamedAudioInput.stream() |> Enum.to_list()

      assert chunks == [<<1, 2>>, <<3, 4>>]
    end
  end

  describe "SimpleWorkflow" do
    test "run/2 invokes handler" do
      workflow = SimpleWorkflow.new(fn text -> ["Got: #{text}"] end)

      result = SimpleWorkflow.run(workflow, "hello")

      assert result == ["Got: hello"]
    end

    test "on_start/1 returns greeting when set" do
      workflow = SimpleWorkflow.new(fn _ -> [] end, greeting: "Welcome!")

      assert SimpleWorkflow.on_start(workflow) == ["Welcome!"]
    end

    test "on_start/1 returns empty list when no greeting" do
      workflow = SimpleWorkflow.new(fn _ -> [] end)

      assert SimpleWorkflow.on_start(workflow) == []
    end
  end

  describe "Codex.Voice runs pipeline with mock workflow" do
    @tag :skip
    @tag :integration
    test "runs complete voice pipeline" do
      # This test would require mock models for STT and TTS
      # In a real integration test, you would:
      # 1. Create a workflow
      # 2. Create audio input
      # 3. Run the pipeline
      # 4. Stream and verify results

      workflow = SimpleWorkflow.new(fn text -> ["Echo: #{text}"] end)

      # With mock models:
      # audio = Voice.audio_input(test_audio_data)
      # {:ok, result} = Voice.run(audio, workflow: workflow, stt_model: MockSTT, tts_model: MockTTS)
      #
      # events = result |> Codex.Voice.Result.stream() |> Enum.to_list()
      # assert Enum.any?(events, &match?(%{type: :voice_stream_event_lifecycle, event: :turn_started}, &1))

      assert workflow.handler.("test") == ["Echo: test"]
    end
  end
end
