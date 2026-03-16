defmodule Codex.AppServer.ItemAdapterTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.ItemAdapter
  alias Codex.Items

  describe "to_item/1" do
    test "maps agentMessage into Items.AgentMessage" do
      item = %{"type" => "agentMessage", "id" => "msg_1", "text" => "hello", "phase" => "final"}

      assert {:ok, %Items.AgentMessage{id: "msg_1", text: "hello", phase: "final"}} =
               ItemAdapter.to_item(item)
    end

    test "maps plan and context compaction items" do
      assert {:ok, %Items.Plan{id: "plan_1", text: "Ship it"}} =
               ItemAdapter.to_item(%{"type" => "plan", "id" => "plan_1", "text" => "Ship it"})

      assert {:ok, %Items.ContextCompaction{id: "compact_1"}} =
               ItemAdapter.to_item(%{"type" => "contextCompaction", "id" => "compact_1"})
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

    test "maps dynamic and collab tool calls" do
      dynamic_item = %{
        "type" => "dynamicToolCall",
        "id" => "dyn_1",
        "tool" => "browser",
        "arguments" => %{"url" => "https://example.com"},
        "status" => "completed",
        "contentItems" => [%{"type" => "inputText", "text" => "done"}],
        "success" => true,
        "durationMs" => 33
      }

      assert {:ok,
              %Items.DynamicToolCall{
                id: "dyn_1",
                tool: "browser",
                arguments: %{"url" => "https://example.com"},
                status: :completed,
                content_items: [%{"type" => "inputText", "text" => "done"}],
                success: true,
                duration_ms: 33
              }} = ItemAdapter.to_item(dynamic_item)

      collab_item = %{
        "type" => "collabAgentToolCall",
        "id" => "collab_1",
        "tool" => "spawn",
        "status" => "inProgress",
        "senderThreadId" => "thread_sender",
        "receiverThreadIds" => ["thread_receiver"],
        "prompt" => "delegate this",
        "model" => "gpt-5.4",
        "reasoningEffort" => "high",
        "agentsStates" => %{"thread_receiver" => %{"status" => "running"}}
      }

      assert {:ok,
              %Items.CollabAgentToolCall{
                id: "collab_1",
                tool: "spawn",
                status: :in_progress,
                sender_thread_id: "thread_sender",
                receiver_thread_ids: ["thread_receiver"],
                prompt: "delegate this",
                model: "gpt-5.4",
                reasoning_effort: "high",
                agents_states: %{"thread_receiver" => %{"status" => "running"}}
              }} = ItemAdapter.to_item(collab_item)
    end

    test "maps web search and image generation extensions" do
      web_item = %{
        "type" => "webSearch",
        "id" => "search_1",
        "query" => "codex sdk",
        "action" => "search"
      }

      assert {:ok, %Items.WebSearch{id: "search_1", query: "codex sdk", action: "search"}} =
               ItemAdapter.to_item(web_item)

      image_item = %{
        "type" => "imageGeneration",
        "id" => "img_1",
        "status" => "completed",
        "revisedPrompt" => "more contrast",
        "result" => "https://example.com/image.png",
        "savedPath" => "/tmp/image.png"
      }

      assert {:ok,
              %Items.ImageGeneration{
                id: "img_1",
                status: "completed",
                revised_prompt: "more contrast",
                result: "https://example.com/image.png",
                saved_path: "/tmp/image.png"
              }} = ItemAdapter.to_item(image_item)
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
