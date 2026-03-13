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
end
