defmodule Codex.Protocol.OpsTest do
  use ExUnit.Case, async: true

  alias Codex.Protocol.Ops

  test "encodes mention and skill user input items explicitly" do
    op =
      Ops.new(:user_turn, %{
        items: [
          %{type: :mention, name: "@docs", path: "app://docs"},
          %{type: :skill, name: "repo-skill", path: "/tmp/SKILL.md"}
        ]
      })

    assert %{
             "type" => "user_turn",
             "items" => [
               %{"type" => "mention", "name" => "@docs", "path" => "app://docs"},
               %{"type" => "skill", "name" => "repo-skill", "path" => "/tmp/SKILL.md"}
             ]
           } = Ops.to_map(op)
  end

  test "encodes granular approval policies with upstream external tagging" do
    op =
      Ops.new(:user_turn, %{
        ask_for_approval: %{
          granular: %{
            sandbox_approval: true,
            request_permissions: true
          }
        }
      })

    assert %{
             "type" => "user_turn",
             "approval_policy" => %{
               "granular" => %{
                 "sandbox_approval" => true,
                 "rules" => false,
                 "skill_approval" => false,
                 "request_permissions" => true,
                 "mcp_elicitations" => false
               }
             }
           } = Ops.to_map(op)
  end

  test "surfaces malformed granular approval policies instead of dropping them" do
    op =
      Ops.new(:override_turn_context, %{
        approval_policy: %{granular: %{request_permissions: "yes"}}
      })

    error =
      assert_raise ArgumentError, fn ->
        Ops.to_map(op)
      end

    assert Exception.message(error) =~ "invalid approval_policy for protocol op"
  end

  test "normalizes collaboration mode maps to the upstream nested settings shape" do
    op =
      Ops.new(:user_turn, %{
        collaboration_mode: %{
          mode: :plan,
          model: "gpt-5.3-codex",
          reasoningEffort: :high,
          developerInstructions: "Keep it brief."
        }
      })

    assert %{
             "type" => "user_turn",
             "collaboration_mode" => %{
               "mode" => "plan",
               "settings" => %{
                 "model" => "gpt-5.3-codex",
                 "reasoning_effort" => "high",
                 "developer_instructions" => "Keep it brief."
               }
             }
           } = Ops.to_map(op)
  end

  test "omits nil collaboration mode settings when normalizing maps" do
    op =
      Ops.new(:user_turn, %{
        collaboration_mode: %{
          mode: :plan,
          model: nil,
          reasoningEffort: :medium,
          developerInstructions: nil
        }
      })

    assert %{
             "type" => "user_turn",
             "collaboration_mode" => %{
               "mode" => "plan",
               "settings" => %{
                 "reasoning_effort" => "medium"
               }
             }
           } = Ops.to_map(op)
  end
end
