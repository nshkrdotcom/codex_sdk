defmodule Codex.ItemsIdAndOrdinalTest do
  use ExUnit.Case, async: true

  alias Codex.Items
  alias Codex.Sessions

  @post_0144_dir "test/support/fixtures/codex_post_0144"

  test "response item IDs remain opaque across prefixed and legacy forms" do
    %{"item" => prefixed_wire} = read_frame("response_item_prefixed_id.jsonl")
    legacy_wire = Map.put(prefixed_wire, "id", "abc123")

    for {expected_id, wire} <- [{"msg_1", prefixed_wire}, {"abc123", legacy_wire}] do
      assert %Items.AgentMessage{id: ^expected_id} = item = Items.parse!(wire)
      assert Items.to_map(item)["id"] == expected_id
    end
  end

  test "session rollout metadata preserves optional ordinal records" do
    rollout = read_frame("rollout_line_ordinal.jsonl")

    with_ordinal = list_single_rollout(rollout, "with-ordinal")
    assert with_ordinal.metadata["ordinal"] == 42
    assert with_ordinal.started_at == "2026-07-10T00:00:00.000Z"

    without_ordinal =
      rollout
      |> Map.delete("ordinal")
      |> list_single_rollout("without-ordinal")

    refute Map.has_key?(without_ordinal.metadata, "ordinal")
    assert without_ordinal.started_at == with_ordinal.started_at
  end

  defp list_single_rollout(rollout, suffix) do
    sessions_dir =
      Path.join(
        System.tmp_dir!(),
        "codex_rollout_#{suffix}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(sessions_dir)
    File.write!(Path.join(sessions_dir, "rollout.jsonl"), Jason.encode!(rollout) <> "\n")
    on_exit(fn -> File.rm_rf(sessions_dir) end)

    assert {:ok, [entry]} = Sessions.list_sessions(sessions_dir: sessions_dir)
    entry
  end

  defp read_frame(file) do
    @post_0144_dir
    |> Path.join(file)
    |> File.stream!([], :line)
    |> Stream.map(&String.trim/1)
    |> Enum.find(&(&1 != "" and not String.starts_with?(&1, "#")))
    |> Jason.decode!()
  end
end
