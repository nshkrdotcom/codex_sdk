defmodule Codex.AppServer.NotificationAdapterTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.NotificationAdapter
  alias Codex.Events

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

    test "passes unknown notifications through as raw events" do
      params = %{"threadId" => "thr_1", "foo" => "bar"}

      assert {:ok, %Events.AppServerNotification{method: "future/notification", params: ^params}} =
               NotificationAdapter.to_event("future/notification", params)
    end
  end
end
