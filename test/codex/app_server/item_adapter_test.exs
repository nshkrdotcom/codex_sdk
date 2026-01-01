defmodule Codex.AppServer.ItemAdapterTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.ItemAdapter
  alias Codex.Items

  describe "to_item/1" do
    test "maps agentMessage into Items.AgentMessage" do
      item = %{"type" => "agentMessage", "id" => "msg_1", "text" => "hello"}

      assert {:ok, %Items.AgentMessage{id: "msg_1", text: "hello"}} = ItemAdapter.to_item(item)
    end

    test "maps userMessage into Items.UserMessage with content blocks" do
      item = %{
        "type" => "userMessage",
        "id" => "u_1",
        "content" => [
          %{"type" => "text", "text" => "hello"},
          %{"type" => "localImage", "path" => "/tmp/image.png"}
        ]
      }

      assert {:ok, %Items.UserMessage{id: "u_1", content: content}} = ItemAdapter.to_item(item)
      assert length(content) == 2
      assert Enum.at(content, 0)["type"] == "text"
    end

    test "maps commandExecution into Items.CommandExecution with extended metadata" do
      item = %{
        "type" => "commandExecution",
        "id" => "cmd_1",
        "command" => "ls -la",
        "cwd" => "/tmp",
        "processId" => nil,
        "status" => "inProgress",
        "commandActions" => [],
        "aggregatedOutput" => nil,
        "exitCode" => nil,
        "durationMs" => 12
      }

      assert {:ok,
              %Items.CommandExecution{
                id: "cmd_1",
                command: "ls -la",
                aggregated_output: "",
                exit_code: nil,
                status: :in_progress,
                cwd: "/tmp",
                process_id: nil,
                command_actions: [],
                duration_ms: 12
              }} = ItemAdapter.to_item(item)
    end

    test "maps reasoning into Items.Reasoning with structured summary/content" do
      item = %{
        "type" => "reasoning",
        "id" => "reason_1",
        "summary" => ["Summary line"],
        "content" => ["Detail line 1", "Detail line 2"]
      }

      assert {:ok, %Items.Reasoning{id: "reason_1", summary: summary, content: content}} =
               ItemAdapter.to_item(item)

      assert summary == ["Summary line"]
      assert content == ["Detail line 1", "Detail line 2"]
    end

    test "maps fileChange into Items.FileChange preserving diffs" do
      item = %{
        "type" => "fileChange",
        "id" => "fc_1",
        "status" => "completed",
        "changes" => [
          %{
            "path" => "README.md",
            "kind" => %{"type" => "update", "movePath" => nil},
            "diff" => "@@ -1 +1 @@\n-Hello\n+Hi\n"
          }
        ]
      }

      assert {:ok, %Items.FileChange{id: "fc_1", status: :completed, changes: [change]}} =
               ItemAdapter.to_item(item)

      assert change.path == "README.md"
      assert change.kind == :update
      assert change.diff =~ "+Hi"
    end

    test "returns raw for unknown item types" do
      item = %{"type" => "mysteryItem", "id" => "x", "foo" => "bar"}

      assert {:raw, ^item} = ItemAdapter.to_item(item)
    end
  end

  describe "to_raw_item/1" do
    test "parses ghost snapshot raw items" do
      item = %{
        "type" => "ghost_snapshot",
        "id" => "raw_1",
        "ghost_commit" => %{"id" => "ghost_1"}
      }

      assert {:ok, %Items.GhostSnapshot{id: "raw_1", ghost_commit: %{"id" => "ghost_1"}}} =
               ItemAdapter.to_raw_item(item)
    end

    test "returns RawResponseItem for unknown raw types" do
      item = %{"type" => "custom_item", "foo" => "bar"}

      assert {:ok, %Items.RawResponseItem{type: "custom_item", payload: %{"foo" => "bar"}}} =
               ItemAdapter.to_raw_item(item)
    end
  end
end
