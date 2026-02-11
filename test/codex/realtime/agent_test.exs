defmodule Codex.Realtime.AgentTest do
  use ExUnit.Case, async: true

  alias Codex.Handoff
  alias Codex.Realtime.Agent
  import Codex.Test.ModelFixtures

  describe "struct creation" do
    test "creates with defaults" do
      agent = %Agent{}
      assert agent.name == "Agent"
      assert agent.model == realtime_model()
      assert agent.instructions == "You are a helpful assistant."
    end

    test "creates with custom values" do
      agent = %Agent{
        name: "VoiceBot",
        model: "gpt-4o-mini-realtime-preview",
        instructions: "Be concise",
        handoff_description: "A voice assistant"
      }

      assert agent.name == "VoiceBot"
      assert agent.handoff_description == "A voice assistant"
    end

    test "accepts tools list" do
      defmodule TestTool do
        use Codex.FunctionTool,
          name: "get_weather",
          description: "Gets the weather",
          parameters: %{},
          handler: fn _args, _ctx -> {:ok, %{"weather" => "sunny"}} end
      end

      agent = %Agent{tools: [TestTool]}

      assert length(agent.tools) == 1
      assert TestTool in agent.tools
    end

    test "accepts handoffs list" do
      other_agent = %Agent{name: "Other"}
      agent = %Agent{handoffs: [other_agent]}

      assert length(agent.handoffs) == 1
    end

    test "accepts output_guardrails list" do
      agent = %Agent{output_guardrails: [:content_filter]}

      assert agent.output_guardrails == [:content_filter]
    end

    test "accepts hooks" do
      hooks = %{on_start: fn _ -> :ok end}
      agent = %Agent{hooks: hooks}

      assert agent.hooks == hooks
    end
  end

  describe "new/1" do
    test "creates agent from keyword list" do
      agent =
        Agent.new(
          name: "TestAgent",
          instructions: "Test instructions"
        )

      assert agent.name == "TestAgent"
      assert agent.instructions == "Test instructions"
    end

    test "creates agent with all options" do
      agent =
        Agent.new(
          name: "FullAgent",
          model: "gpt-4o-mini-realtime-preview",
          instructions: "Full instructions",
          handoff_description: "A full agent",
          tools: [],
          handoffs: [],
          output_guardrails: [],
          hooks: nil
        )

      assert agent.name == "FullAgent"
      assert agent.model == "gpt-4o-mini-realtime-preview"
    end
  end

  describe "resolve_instructions/2" do
    test "returns string instructions as-is" do
      agent = %Agent{instructions: "Be helpful"}
      assert Agent.resolve_instructions(agent, %{}) == "Be helpful"
    end

    test "returns nil when instructions is nil" do
      agent = %Agent{instructions: nil}
      assert Agent.resolve_instructions(agent, %{}) == nil
    end

    test "calls function instructions with context" do
      agent = %Agent{
        instructions: fn ctx -> "Hello #{ctx.user_name}" end
      }

      assert Agent.resolve_instructions(agent, %{user_name: "Alice"}) == "Hello Alice"
    end

    test "calls function instructions with context and agent" do
      agent = %Agent{
        name: "GreeterBot",
        instructions: fn ctx, agent -> "Hello #{ctx.user_name}, I am #{agent.name}" end
      }

      assert Agent.resolve_instructions(agent, %{user_name: "Bob"}) ==
               "Hello Bob, I am GreeterBot"
    end
  end

  describe "get_tools/1" do
    test "returns agent tools" do
      defmodule SearchTool do
        use Codex.FunctionTool,
          name: "search",
          description: "Searches",
          parameters: %{},
          handler: fn _args, _ctx -> {:ok, %{}} end
      end

      agent = %Agent{tools: [SearchTool]}

      tools = Agent.get_tools(agent)
      assert length(tools) == 1
    end

    test "includes handoff tools for agent handoffs" do
      other = %Agent{name: "Support", handoff_description: "Support agent"}
      agent = %Agent{handoffs: [other]}

      tools = Agent.get_tools(agent)
      assert length(tools) == 1

      [handoff_tool] = tools
      assert handoff_tool.tool_name == "transfer_to_support"
    end

    test "includes handoff tools for Handoff structs" do
      target_agent = %Codex.Agent{name: "Sales", handoff_description: "Sales agent"}
      handoff = Handoff.wrap(target_agent)

      agent = %Agent{handoffs: [handoff]}

      tools = Agent.get_tools(agent)
      assert length(tools) == 1

      [handoff_tool] = tools
      assert handoff_tool.tool_name == "transfer_to_sales"
    end

    test "combines regular tools and handoff tools" do
      defmodule CalcTool do
        use Codex.FunctionTool,
          name: "calculator",
          description: "Calculates",
          parameters: %{},
          handler: fn _args, _ctx -> {:ok, %{}} end
      end

      other = %Agent{name: "Helper"}
      agent = %Agent{tools: [CalcTool], handoffs: [other]}

      tools = Agent.get_tools(agent)
      assert length(tools) == 2
    end

    test "returns empty list when no tools or handoffs" do
      agent = %Agent{}
      assert Agent.get_tools(agent) == []
    end
  end

  describe "find_handoff_target/2" do
    test "finds agent by name" do
      support = %Agent{name: "Support"}
      sales = %Agent{name: "Sales"}
      agent = %Agent{handoffs: [support, sales]}

      {:ok, target} = Agent.find_handoff_target(agent, "transfer_to_support")
      assert target.name == "Support"
    end

    test "finds agent case-insensitively via tool name" do
      support = %Agent{name: "Support"}
      agent = %Agent{handoffs: [support]}

      # Tool names are lowercased
      {:ok, target} = Agent.find_handoff_target(agent, "transfer_to_support")
      assert target.name == "Support"
    end

    test "returns error for unknown handoff" do
      agent = %Agent{handoffs: []}
      assert {:error, :not_found} = Agent.find_handoff_target(agent, "transfer_to_Unknown")
    end

    test "finds Handoff struct target" do
      target_agent = %Codex.Agent{name: "Billing"}
      handoff = Handoff.wrap(target_agent)
      agent = %Agent{handoffs: [handoff]}

      {:ok, target} = Agent.find_handoff_target(agent, "transfer_to_billing")
      assert target.name == "Billing"
    end

    test "returns error for malformed tool name" do
      support = %Agent{name: "Support"}
      agent = %Agent{handoffs: [support]}

      assert {:error, :not_found} = Agent.find_handoff_target(agent, "invalid_name")
    end
  end

  describe "clone/2" do
    test "clones agent with new values" do
      original = %Agent{
        name: "Original",
        instructions: "Original instructions"
      }

      cloned = Agent.clone(original, name: "Cloned", model: "gpt-4o-mini-realtime-preview")

      assert cloned.name == "Cloned"
      assert cloned.model == "gpt-4o-mini-realtime-preview"
      # Unchanged fields should be preserved
      assert cloned.instructions == "Original instructions"
    end

    test "clone preserves unchanged fields" do
      original = %Agent{
        name: "Original",
        instructions: "Keep me",
        handoff_description: "Keep this too",
        tools: [:some_tool]
      }

      cloned = Agent.clone(original, name: "New Name")

      assert cloned.name == "New Name"
      assert cloned.instructions == "Keep me"
      assert cloned.handoff_description == "Keep this too"
      assert cloned.tools == [:some_tool]
    end
  end

  describe "handoff tool creation" do
    test "creates handoff tool with correct description" do
      other = %Agent{name: "Expert", handoff_description: "An expert in complex matters"}
      agent = %Agent{handoffs: [other]}

      [handoff_tool] = Agent.get_tools(agent)

      assert handoff_tool.tool_description ==
               "Handoff to the Expert agent to handle the request. An expert in complex matters"
    end

    test "creates handoff tool with default description when none provided" do
      other = %Agent{name: "Helper"}
      agent = %Agent{handoffs: [other]}

      [handoff_tool] = Agent.get_tools(agent)

      assert handoff_tool.tool_description == "Handoff to the Helper agent to handle the request."
    end

    test "creates handoff tool with sanitized name" do
      other = %Agent{name: "Sales Rep"}
      agent = %Agent{handoffs: [other]}

      [handoff_tool] = Agent.get_tools(agent)

      assert handoff_tool.tool_name == "transfer_to_sales_rep"
    end
  end
end
