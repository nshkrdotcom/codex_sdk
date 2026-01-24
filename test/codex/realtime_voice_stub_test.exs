defmodule Codex.RealtimeVoiceStubTest do
  @moduledoc """
  Tests for Codex.Realtime and Codex.Voice modules.

  Note: These modules are now fully implemented. This test file verifies
  basic functionality and error handling.
  """
  use ExUnit.Case, async: true

  describe "Codex.Realtime basic functionality" do
    test "agent/1 creates an agent" do
      agent = Codex.Realtime.agent(name: "TestAgent")

      assert %Codex.Realtime.Agent{} = agent
      assert agent.name == "TestAgent"
    end

    test "runner/2 creates a runner" do
      agent = Codex.Realtime.agent(name: "TestAgent")
      runner = Codex.Realtime.runner(agent)

      assert %Codex.Realtime.Runner{} = runner
      assert runner.starting_agent == agent
    end
  end

  describe "Codex.Voice basic functionality" do
    test "audio_input/1 creates an audio input" do
      input = Codex.Voice.audio_input(<<0, 0, 255, 127>>)

      assert %Codex.Voice.Input.AudioInput{} = input
      assert input.data == <<0, 0, 255, 127>>
    end

    test "streamed_input/0 creates a streamed input" do
      input = Codex.Voice.streamed_input()

      assert %Codex.Voice.Input.StreamedAudioInput{} = input
    end

    test "simple_workflow/1 creates a workflow" do
      workflow = Codex.Voice.simple_workflow(fn text -> ["Echo: #{text}"] end)

      assert %Codex.Voice.SimpleWorkflow{} = workflow
    end
  end
end
