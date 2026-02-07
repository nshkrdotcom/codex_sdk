defmodule Codex.Protocol.CollaborationModeTest do
  use ExUnit.Case, async: true

  alias Codex.Protocol.CollaborationMode

  test "from_map/1 decodes collaboration modes" do
    data = %{
      "mode" => "plan",
      "model" => "gpt-5.1-codex",
      "reasoning_effort" => "high",
      "developer_instructions" => "Keep it brief."
    }

    assert %CollaborationMode{
             mode: :plan,
             model: "gpt-5.1-codex",
             reasoning_effort: :high,
             developer_instructions: "Keep it brief."
           } = CollaborationMode.from_map(data)
  end

  test "to_map/1 encodes collaboration modes" do
    mode = %CollaborationMode{
      mode: :pair_programming,
      model: "gpt-5.1-codex",
      reasoning_effort: :low,
      developer_instructions: nil
    }

    assert %{
             "mode" => "pair_programming",
             "model" => "gpt-5.1-codex",
             "reasoning_effort" => "low"
           } = CollaborationMode.to_map(mode)
  end

  test "from_map/1 decodes legacy pair programming variants" do
    assert %CollaborationMode{mode: :pair_programming} =
             CollaborationMode.from_map(%{
               "mode" => "pairprogramming",
               "model" => "gpt-5.1-codex"
             })

    assert %CollaborationMode{mode: :pair_programming} =
             CollaborationMode.from_map(%{
               "mode" => "pair-programming",
               "model" => "gpt-5.1-codex"
             })
  end

  test "from_map/1 decodes code and default modes" do
    assert %CollaborationMode{mode: :code} =
             CollaborationMode.from_map(%{"mode" => "code", "model" => "gpt-5.1-codex"})

    assert %CollaborationMode{mode: :default} =
             CollaborationMode.from_map(%{"mode" => "default", "model" => "gpt-5.1-codex"})
  end

  test "unknown modes default to :custom" do
    assert %CollaborationMode{mode: :custom} =
             CollaborationMode.from_map(%{"mode" => "unknown", "model" => "gpt-5.1-codex"})
  end
end
