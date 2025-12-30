defmodule Codex.ItemsReasoningTest do
  use ExUnit.Case, async: true

  alias Codex.Items

  test "parse!/1 preserves structured reasoning fields" do
    item = %{
      "type" => "reasoning",
      "id" => "reason_1",
      "summary" => ["Summary"],
      "content" => ["Detail 1", "Detail 2"]
    }

    assert %Items.Reasoning{id: "reason_1", summary: summary, content: content} =
             Items.parse!(item)

    assert summary == ["Summary"]
    assert content == ["Detail 1", "Detail 2"]
  end

  test "to_map/1 emits summary/content when present" do
    item = %Items.Reasoning{
      id: "reason_2",
      summary: ["S"],
      content: ["C"],
      text: nil
    }

    map = Items.to_map(item)

    assert map["summary"] == ["S"]
    assert map["content"] == ["C"]
  end
end
