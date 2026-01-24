defmodule Codex.Voice.WorkflowTest do
  use ExUnit.Case, async: true

  alias Codex.Voice.AgentWorkflow
  alias Codex.Voice.SimpleWorkflow

  describe "SimpleWorkflow" do
    test "creates with handler function" do
      workflow = SimpleWorkflow.new(fn text -> ["Echo: #{text}"] end)
      assert workflow.handler != nil
    end

    test "run returns handler output" do
      workflow = SimpleWorkflow.new(fn text -> ["Echo: #{text}"] end)
      result = SimpleWorkflow.run(workflow, "Hello")
      assert result == ["Echo: Hello"]
    end

    test "on_start returns greeting when set" do
      workflow = SimpleWorkflow.new(fn _ -> [] end, greeting: "Welcome!")
      assert SimpleWorkflow.on_start(workflow) == ["Welcome!"]
    end

    test "on_start returns empty when no greeting" do
      workflow = SimpleWorkflow.new(fn _ -> [] end)
      assert SimpleWorkflow.on_start(workflow) == []
    end

    test "handles complex handler output" do
      workflow =
        SimpleWorkflow.new(fn text ->
          ["Part 1: #{text}", "Part 2: continuation"]
        end)

      result = SimpleWorkflow.run(workflow, "test")
      assert result == ["Part 1: test", "Part 2: continuation"]
    end

    test "handler can return empty list" do
      workflow = SimpleWorkflow.new(fn _text -> [] end)
      result = SimpleWorkflow.run(workflow, "ignored")
      assert result == []
    end
  end

  describe "AgentWorkflow" do
    test "creates from agent" do
      agent = %Codex.Agent{name: "Test", instructions: "Be helpful"}
      workflow = AgentWorkflow.new(agent)
      assert workflow.agent == agent
    end

    test "accepts context" do
      agent = %Codex.Agent{name: "Test"}
      workflow = AgentWorkflow.new(agent, context: %{user: "Alice"})
      assert workflow.context == %{user: "Alice"}
    end

    test "initializes with empty history" do
      agent = %Codex.Agent{name: "Test"}
      workflow = AgentWorkflow.new(agent)
      assert workflow.history == []
    end

    test "on_start returns greeting when instructions contain 'greeting'" do
      agent = %Codex.Agent{name: "Test", instructions: "Always start with a greeting"}
      workflow = AgentWorkflow.new(agent)
      result = AgentWorkflow.on_start(workflow)
      assert result == ["Hello! How can I assist you today?"]
    end

    test "on_start returns empty list when instructions don't contain 'greeting'" do
      agent = %Codex.Agent{name: "Test", instructions: "Be helpful and concise"}
      workflow = AgentWorkflow.new(agent)
      result = AgentWorkflow.on_start(workflow)
      assert result == []
    end

    test "on_start returns empty list when instructions are nil" do
      agent = %Codex.Agent{name: "Test", instructions: nil}
      workflow = AgentWorkflow.new(agent)
      result = AgentWorkflow.on_start(workflow)
      assert result == []
    end

    test "default context is empty map" do
      agent = %Codex.Agent{name: "Test"}
      workflow = AgentWorkflow.new(agent)
      assert workflow.context == %{}
    end
  end

  describe "Workflow behaviour" do
    test "SimpleWorkflow implements Workflow behaviour" do
      assert function_exported?(SimpleWorkflow, :run, 2)
      assert function_exported?(SimpleWorkflow, :on_start, 1)
    end

    test "AgentWorkflow implements Workflow behaviour" do
      assert function_exported?(AgentWorkflow, :run, 2)
      assert function_exported?(AgentWorkflow, :on_start, 1)
    end
  end
end
