defmodule Codex.Realtime.RunnerTest do
  use ExUnit.Case, async: true

  alias Codex.Realtime.Agent
  alias Codex.Realtime.Config.ModelConfig
  alias Codex.Realtime.Config.RunConfig
  alias Codex.Realtime.Runner
  alias Codex.Realtime.Session
  alias Codex.Test.MockWebSocket

  describe "new/2" do
    test "creates runner with agent" do
      agent = Agent.new(name: "TestAgent")
      runner = Runner.new(agent)

      assert runner.starting_agent == agent
      assert runner.config == nil
      assert runner.model == nil
    end

    test "accepts run config" do
      agent = Agent.new(name: "TestAgent")
      config = %RunConfig{tracing_disabled: true}
      runner = Runner.new(agent, config: config)

      assert runner.starting_agent == agent
      assert runner.config.tracing_disabled == true
    end

    test "accepts model override" do
      agent = Agent.new(name: "TestAgent")
      runner = Runner.new(agent, model: SomeCustomModel)

      assert runner.model == SomeCustomModel
    end

    test "accepts multiple options" do
      agent = Agent.new(name: "TestAgent")
      config = %RunConfig{async_tool_calls: false}

      runner =
        Runner.new(agent,
          config: config,
          model: CustomModel
        )

      assert runner.starting_agent == agent
      assert runner.config.async_tool_calls == false
      assert runner.model == CustomModel
    end
  end

  describe "run/2" do
    test "starts a session with mock websocket" do
      agent = Agent.new(name: "TestAgent", instructions: "Be helpful")
      runner = Runner.new(agent)

      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Runner.run(runner,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      assert Process.alive?(session)

      # Clean up
      Session.close(session)
    end

    test "passes context to session" do
      agent = Agent.new(name: "TestAgent")
      runner = Runner.new(agent)

      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Runner.run(runner,
          context: %{user_id: "123", locale: "en"},
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      assert Process.alive?(session)
      Session.close(session)
    end

    test "passes model config to session" do
      agent = Agent.new(name: "TestAgent")
      runner = Runner.new(agent)

      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      model_config = %ModelConfig{
        api_key: "test-key",
        url: "wss://custom.api.example.com/v1/realtime"
      }

      {:ok, session} =
        Runner.run(runner,
          model_config: model_config,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      assert Process.alive?(session)
      Session.close(session)
    end

    test "uses run config from runner" do
      agent = Agent.new(name: "TestAgent")
      config = %RunConfig{tracing_disabled: true}
      runner = Runner.new(agent, config: config)

      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Runner.run(runner,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      assert Process.alive?(session)
      Session.close(session)
    end

    test "defaults to empty context" do
      agent = Agent.new(name: "TestAgent")
      runner = Runner.new(agent)

      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Runner.run(runner,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      assert Process.alive?(session)
      Session.close(session)
    end
  end

  describe "struct" do
    test "has correct default values" do
      runner = %Runner{}

      assert runner.starting_agent == nil
      assert runner.config == nil
      assert runner.model == nil
    end

    test "can be pattern matched" do
      agent = Agent.new(name: "TestAgent")
      runner = Runner.new(agent)

      assert %Runner{starting_agent: %Agent{name: "TestAgent"}} = runner
    end
  end
end
