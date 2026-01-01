defmodule Codex.AppServer.NotificationAdapterTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.NotificationAdapter
  alias Codex.Events
  alias Codex.Items

  describe "to_event/2" do
    test "maps agent message deltas into Codex.Events.ItemAgentMessageDelta" do
      params = %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "itemId" => "msg_1",
        "delta" => "hello"
      }

      assert {:ok,
              %Events.ItemAgentMessageDelta{thread_id: "thr_1", turn_id: "turn_1", item: item}} =
               NotificationAdapter.to_event("item/agentMessage/delta", params)

      assert item["id"] == "msg_1"
      assert item["text"] == "hello"
    end

    test "maps token usage updates into Codex.Events.ThreadTokenUsageUpdated" do
      params = %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "tokenUsage" => %{
          "total" => %{
            "totalTokens" => 21,
            "inputTokens" => 12,
            "cachedInputTokens" => 0,
            "outputTokens" => 9,
            "reasoningOutputTokens" => 0
          },
          "last" => %{
            "totalTokens" => 9,
            "inputTokens" => 0,
            "cachedInputTokens" => 0,
            "outputTokens" => 9,
            "reasoningOutputTokens" => 0
          },
          "modelContextWindow" => nil
        }
      }

      assert {:ok,
              %Events.ThreadTokenUsageUpdated{
                thread_id: "thr_1",
                turn_id: "turn_1",
                usage: usage,
                delta: delta
              }} = NotificationAdapter.to_event("thread/tokenUsage/updated", params)

      assert usage["total_tokens"] == 21
      assert delta["output_tokens"] == 9
    end

    test "maps diff updates with unified diff string" do
      params = %{"threadId" => "thr_1", "turnId" => "turn_1", "diff" => "@@ -1 +1 @@\n"}

      assert {:ok, %Events.TurnDiffUpdated{thread_id: "thr_1", turn_id: "turn_1", diff: diff}} =
               NotificationAdapter.to_event("turn/diff/updated", params)

      assert diff =~ "@@"
    end

    test "maps plan updates into Codex.Events.TurnPlanUpdated" do
      params = %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "explanation" => "Doing the thing",
        "plan" => [
          %{"step" => "First", "status" => "pending"},
          %{"step" => "Second", "status" => "inProgress"},
          %{"step" => "Third", "status" => "completed"}
        ]
      }

      assert {:ok,
              %Events.TurnPlanUpdated{
                thread_id: "thr_1",
                turn_id: "turn_1",
                explanation: "Doing the thing",
                plan: plan
              }} = NotificationAdapter.to_event("turn/plan/updated", params)

      assert plan == [
               %{step: "First", status: :pending},
               %{step: "Second", status: :in_progress},
               %{step: "Third", status: :completed}
             ]
    end

    test "maps reasoning summary part added notifications" do
      params = %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "itemId" => "reason_1",
        "summaryIndex" => 2
      }

      assert {:ok,
              %Events.ReasoningSummaryPartAdded{
                thread_id: "thr_1",
                turn_id: "turn_1",
                item_id: "reason_1",
                summary_index: 2
              }} =
               NotificationAdapter.to_event("item/reasoning/summaryPartAdded", params)
    end

    test "maps file change output deltas" do
      params = %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "itemId" => "patch_1",
        "delta" => "patching..."
      }

      assert {:ok,
              %Events.FileChangeOutputDelta{
                thread_id: "thr_1",
                turn_id: "turn_1",
                item_id: "patch_1",
                delta: "patching..."
              }} = NotificationAdapter.to_event("item/fileChange/outputDelta", params)
    end

    test "maps terminal interaction notifications" do
      params = %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "itemId" => "cmd_1",
        "processId" => "proc_1",
        "stdin" => "y\n"
      }

      assert {:ok,
              %Events.TerminalInteraction{
                thread_id: "thr_1",
                turn_id: "turn_1",
                item_id: "cmd_1",
                process_id: "proc_1",
                stdin: "y\n"
              }} =
               NotificationAdapter.to_event("item/commandExecution/terminalInteraction", params)
    end

    test "maps MCP tool call progress notifications" do
      params = %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "itemId" => "mcp_1",
        "message" => "Downloading..."
      }

      assert {:ok,
              %Events.McpToolCallProgress{
                thread_id: "thr_1",
                turn_id: "turn_1",
                item_id: "mcp_1",
                message: "Downloading..."
              }} = NotificationAdapter.to_event("item/mcpToolCall/progress", params)
    end

    test "maps account and auth notifications" do
      assert {:ok, %Events.AccountUpdated{auth_mode: "apiKey"}} =
               NotificationAdapter.to_event("account/updated", %{"authMode" => "apiKey"})

      assert {:ok,
              %Events.AccountLoginCompleted{
                login_id: "login_1",
                success: true,
                error: nil
              }} =
               NotificationAdapter.to_event("account/login/completed", %{
                 "loginId" => "login_1",
                 "success" => true,
                 "error" => nil
               })
    end

    test "maps account rate limit updates" do
      params = %{"rateLimits" => %{"primary" => %{"remaining" => 10}}}

      assert {:ok, %Events.AccountRateLimitsUpdated{rate_limits: %{"primary" => _}}} =
               NotificationAdapter.to_event("account/rateLimits/updated", params)
    end

    test "maps MCP OAuth completion and Windows warnings" do
      assert {:ok,
              %Events.McpServerOauthLoginCompleted{
                name: "mcp_server",
                success: true,
                error: nil
              }} =
               NotificationAdapter.to_event("mcpServer/oauthLogin/completed", %{
                 "name" => "mcp_server",
                 "success" => true,
                 "error" => nil
               })

      assert {:ok,
              %Events.WindowsWorldWritableWarning{
                sample_paths: ["C:/tmp"],
                extra_count: 2,
                failed_scan: false
              }} =
               NotificationAdapter.to_event("windows/worldWritableWarning", %{
                 "samplePaths" => ["C:/tmp"],
                 "extraCount" => 2,
                 "failedScan" => false
               })
    end

    test "maps raw response item completion events" do
      params = %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "item" => %{
          "type" => "ghost_snapshot",
          "id" => "raw_1",
          "ghost_commit" => %{"id" => "ghost_1"}
        }
      }

      assert {:ok,
              %Events.RawResponseItemCompleted{
                thread_id: "thr_1",
                turn_id: "turn_1",
                item: %Items.GhostSnapshot{id: "raw_1", ghost_commit: %{"id" => "ghost_1"}}
              }} = NotificationAdapter.to_event("rawResponseItem/completed", params)
    end

    test "maps deprecation notices" do
      params = %{"summary" => "Deprecated endpoint", "details" => "Use thread/start instead."}

      assert {:ok,
              %Events.DeprecationNotice{
                summary: "Deprecated endpoint",
                details: "Use thread/start instead."
              }} = NotificationAdapter.to_event("deprecationNotice", params)
    end

    test "maps turn completed error payloads" do
      params = %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "turn_1", "status" => "failed", "error" => %{"message" => "boom"}}
      }

      assert {:ok,
              %Events.TurnCompleted{
                thread_id: "thr_1",
                turn_id: "turn_1",
                status: "failed",
                error: %{"message" => "boom"}
              }} = NotificationAdapter.to_event("turn/completed", params)
    end

    test "maps error notifications with additional details" do
      params = %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "willRetry" => true,
        "error" => %{
          "message" => "Reconnecting...",
          "additionalDetails" => "upstream timeout",
          "codexErrorInfo" => %{"code" => "rate_limit"}
        }
      }

      assert {:ok,
              %Events.Error{
                message: "Reconnecting...",
                thread_id: "thr_1",
                turn_id: "turn_1",
                additional_details: "upstream timeout",
                will_retry: true,
                codex_error_info: %{"code" => "rate_limit"}
              }} = NotificationAdapter.to_event("error", params)
    end

    test "passes unknown notifications through as raw events" do
      params = %{"threadId" => "thr_1", "foo" => "bar"}

      assert {:ok, %Events.AppServerNotification{method: "future/notification", params: ^params}} =
               NotificationAdapter.to_event("future/notification", params)
    end
  end
end
