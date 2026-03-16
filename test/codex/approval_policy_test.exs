defmodule Codex.ApprovalPolicyTest do
  use ExUnit.Case, async: true

  alias Codex.ApprovalPolicy

  test "serializes externally tagged granular approval policies" do
    assert {:ok,
            %{
              "granular" => %{
                "sandbox_approval" => true,
                "rules" => false,
                "skill_approval" => false,
                "request_permissions" => true,
                "mcp_elicitations" => false
              }
            }} =
             ApprovalPolicy.to_external(%{
               granular: %{
                 sandbox_approval: true,
                 request_permissions: true
               }
             })
  end

  test "accepts string-keyed upstream external-tagged granular approval policies" do
    assert {:ok,
            %{
              "granular" => %{
                "sandbox_approval" => false,
                "rules" => false,
                "skill_approval" => false,
                "request_permissions" => true,
                "mcp_elicitations" => false
              }
            }} =
             ApprovalPolicy.to_external(%{
               "granular" => %{
                 "request_permissions" => true
               }
             })
  end

  test "rejects unknown granular approval keys" do
    assert {:error, {:invalid_ask_for_approval, _reason}} =
             ApprovalPolicy.to_external(%{
               type: :granular,
               sandbox_approval: true,
               unsupported: true
             })
  end

  test "rejects non-boolean granular approval flags" do
    assert {:error, {:invalid_ask_for_approval, _reason}} =
             ApprovalPolicy.to_external(%{
               granular: %{
                 request_permissions: "yes"
               }
             })
  end

  test "rejects conflicting alias values for the same granular flag" do
    assert {:error, {:invalid_ask_for_approval, _reason}} =
             ApprovalPolicy.to_external(%{
               granular: %{
                 request_permissions: true,
                 requestPermissions: false
               }
             })
  end

  test "rejects conflicting alias values for the granular type tag" do
    assert {:error, {:invalid_ask_for_approval, _reason}} =
             ApprovalPolicy.to_external(%{
               "type" => "never",
               type: :granular,
               request_permissions: true
             })
  end
end
