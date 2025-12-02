defmodule Codex.HandoffTest do
  use ExUnit.Case, async: true

  alias Codex.Agent
  alias Codex.AgentRunner
  alias Codex.Handoff

  describe "handoff wrapping" do
    test "wraps agents into handoffs with default metadata" do
      {:ok, target} = Agent.new(%{name: "support", handoff_description: "Handles tickets"})
      {:ok, parent} = Agent.new(%{name: "router", handoffs: [target]})

      assert {:ok, [handoff]} = AgentRunner.get_handoffs(parent, %{})

      assert %Handoff{} = handoff
      assert handoff.tool_name == "transfer_to_support"
      assert handoff.tool_description =~ "support"
      assert handoff.agent_name == "support"
      assert handoff.strict_json_schema
    end

    test "honors custom metadata and filters enabled handoffs" do
      {:ok, sales} = Agent.new(%{name: "sales"})
      {:ok, support} = Agent.new(%{name: "support"})

      disabled =
        Handoff.wrap(sales,
          tool_name: "custom_tool",
          tool_description: "custom description",
          nest_handoff_history: false,
          is_enabled: fn _ctx, _agent -> false end
        )

      {:ok, parent} =
        Agent.new(%{
          name: "router",
          handoffs: [
            disabled,
            support
          ]
        })

      assert {:ok, [handoff]} = AgentRunner.get_handoffs(parent, %{context: :ok})

      assert handoff.tool_name == "transfer_to_support"
      assert handoff.tool_description =~ "support"
      assert handoff.nest_handoff_history == nil
      assert handoff.input_filter == nil
    end
  end
end
