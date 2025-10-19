defmodule Codex.ApprovalsTest do
  use ExUnit.Case, async: true

  alias Codex.Approvals.StaticPolicy

  test "allow policy approves tool calls" do
    policy = StaticPolicy.allow()
    assert :allow = StaticPolicy.review_tool(policy, %{tool_name: "demo"}, %{})
  end

  test "deny policy returns tagged error" do
    policy = StaticPolicy.deny(reason: "compliance")

    assert {:deny, "compliance"} =
             StaticPolicy.review_tool(policy, %{tool_name: "demo"}, %{thread_id: "t"})
  end
end
