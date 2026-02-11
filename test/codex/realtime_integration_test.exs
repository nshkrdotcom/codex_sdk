defmodule Codex.RealtimeIntegrationTest do
  @moduledoc """
  Integration tests for Codex.Realtime.

  These tests verify the integration between Realtime components.
  Tests requiring actual API access are tagged with `:integration` and skipped by default.
  """
  use ExUnit.Case, async: true

  alias Codex.Realtime
  alias Codex.Realtime.Agent
  alias Codex.Realtime.Config.RunConfig
  alias Codex.Realtime.Config.SessionModelSettings
  import Codex.Test.ModelFixtures

  @moduletag :realtime_integration

  describe "Codex.Realtime agent creation" do
    test "creates an agent with default options" do
      agent = Realtime.agent(name: "TestAgent")

      assert %Agent{} = agent
      assert agent.name == "TestAgent"
      assert agent.model == realtime_model()
    end

    test "creates an agent with custom instructions" do
      agent =
        Realtime.agent(
          name: "Assistant",
          instructions: "You are a helpful assistant."
        )

      assert agent.instructions == "You are a helpful assistant."
    end

    test "creates an agent with dynamic instructions" do
      dynamic_fn = fn context -> "Hello #{context[:user_name]}!" end

      agent =
        Realtime.agent(
          name: "Greeter",
          instructions: dynamic_fn
        )

      assert is_function(agent.instructions, 1)
      assert agent.instructions.(%{user_name: "Alice"}) == "Hello Alice!"
    end

    test "creates an agent with tools" do
      tool = %{
        name: "get_weather",
        description: "Get weather for a location",
        parameters: %{
          type: "object",
          properties: %{location: %{type: "string"}}
        }
      }

      agent =
        Realtime.agent(
          name: "WeatherBot",
          tools: [tool]
        )

      assert length(agent.tools) == 1
    end
  end

  describe "Codex.Realtime runner creation" do
    test "creates a runner from an agent" do
      agent = Realtime.agent(name: "TestAgent")
      runner = Realtime.runner(agent)

      assert runner.starting_agent == agent
    end

    test "creates a runner with custom config" do
      agent = Realtime.agent(name: "TestAgent")

      config = %RunConfig{
        tracing_disabled: true,
        model_settings: %SessionModelSettings{voice: "nova"}
      }

      runner = Realtime.runner(agent, config: config)

      assert runner.config == config
    end
  end

  describe "Codex main module delegation" do
    test "realtime_agent/1 delegates to Codex.Realtime.agent/1" do
      agent = Codex.realtime_agent(name: "DelegatedAgent")

      assert %Agent{} = agent
      assert agent.name == "DelegatedAgent"
    end
  end

  describe "Codex.Realtime runs a complete session" do
    @tag :skip
    @tag :integration
    test "runs a session with mock WebSocket" do
      # This test requires a mock WebSocket or real API access
      agent =
        Realtime.agent(
          name: "TestAgent",
          instructions: "Respond briefly."
        )

      # In a real integration test, you would:
      # 1. Start the session with mock WebSocket
      # 2. Subscribe to events
      # 3. Send messages/audio
      # 4. Verify events are received

      # {:ok, session} = Realtime.run(agent, websocket_module: MockWebSocket)
      # Realtime.subscribe(session, self())
      #
      # assert_receive {:session_event, %Codex.Realtime.Events.AgentStartEvent{}}, 5000

      assert agent.name == "TestAgent"
    end
  end
end
