defmodule Codex.EventsTest do
  use ExUnit.Case, async: true

  alias Codex.{Events, Items}
  alias Codex.Protocol.RateLimit, as: RateLimitSnapshot

  describe "parse!/1" do
    test "converts thread.started event map into typed struct" do
      event =
        Events.parse!(%{
          "type" => "thread.started",
          "thread_id" => "thread_abc123",
          "metadata" => %{"labels" => %{"topic" => "demo"}}
        })

      assert %Events.ThreadStarted{
               thread_id: "thread_abc123",
               metadata: %{"labels" => %{"topic" => "demo"}}
             } = event
    end

    test "raises for unknown event type" do
      assert_raise ArgumentError, fn ->
        Events.parse!(%{"type" => "unknown.event"})
      end
    end

    test "parses turn.completed with error payloads" do
      event =
        Events.parse!(%{
          "type" => "turn.completed",
          "thread_id" => "thread_error",
          "turn_id" => "turn_error",
          "status" => "failed",
          "error" => %{"message" => "boom"}
        })

      assert %Events.TurnCompleted{
               thread_id: "thread_error",
               turn_id: "turn_error",
               status: "failed",
               error: %{"message" => "boom"}
             } = event

      assert %{
               "type" => "turn.completed",
               "thread_id" => "thread_error",
               "turn_id" => "turn_error",
               "error" => %{"message" => "boom"}
             } = Events.to_map(event)
    end

    test "parses item.started and item.updated events into typed structs" do
      started =
        Events.parse!(%{
          "type" => "item.started",
          "item" => %{
            "id" => "item_1",
            "type" => "command_execution",
            "command" => "mix test",
            "aggregated_output" => "",
            "status" => "in_progress"
          }
        })

      assert %Events.ItemStarted{
               item: %Items.CommandExecution{
                 id: "item_1",
                 command: "mix test",
                 aggregated_output: "",
                 status: :in_progress,
                 exit_code: nil
               }
             } = started

      updated =
        Events.parse!(%{
          "type" => "item.updated",
          "item" => %{
            "id" => "item_1",
            "type" => "command_execution",
            "command" => "mix test",
            "aggregated_output" => "Running",
            "status" => "in_progress"
          }
        })

      assert %Events.ItemUpdated{
               item: %Items.CommandExecution{
                 id: "item_1",
                 command: "mix test",
                 aggregated_output: "Running",
                 status: :in_progress,
                 exit_code: nil
               }
             } = updated
    end

    test "parses item.completed events for todo list and file change" do
      todo_event =
        Events.parse!(%{
          "type" => "item.completed",
          "item" => %{
            "id" => "todo_1",
            "type" => "todo_list",
            "items" => [
              %{"text" => "step 1", "completed" => true},
              %{"text" => "step 2", "completed" => false}
            ]
          }
        })

      assert %Events.ItemCompleted{
               item: %Items.TodoList{
                 id: "todo_1",
                 items: [%{text: "step 1", completed: true}, %{text: "step 2", completed: false}]
               }
             } = todo_event

      file_event =
        Events.parse!(%{
          "type" => "item.completed",
          "item" => %{
            "id" => "patch_1",
            "type" => "file_change",
            "status" => "completed",
            "changes" => [
              %{"path" => "lib/app.ex", "kind" => "update"},
              %{"path" => "lib/new.ex", "kind" => "add"}
            ]
          }
        })

      assert %Events.ItemCompleted{
               item: %Items.FileChange{
                 id: "patch_1",
                 status: :completed,
                 changes: [
                   %{path: "lib/app.ex", kind: :update},
                   %{path: "lib/new.ex", kind: :add}
                 ]
               }
             } = file_event
    end

    test "parses MCP tool calls and web search items" do
      mcp_event =
        Events.parse!(%{
          "type" => "item.started",
          "item" => %{
            "id" => "mcp_1",
            "type" => "mcp_tool_call",
            "server" => "example",
            "tool" => "inspect",
            "status" => "in_progress"
          }
        })

      assert %Events.ItemStarted{
               item: %Items.McpToolCall{
                 id: "mcp_1",
                 server: "example",
                 tool: "inspect",
                 status: :in_progress
               }
             } = mcp_event

      web_event =
        Events.parse!(%{
          "type" => "item.completed",
          "item" => %{
            "id" => "search_1",
            "type" => "web_search",
            "query" => "elixir json decode"
          }
        })

      assert %Events.ItemCompleted{
               item: %Items.WebSearch{id: "search_1", query: "elixir json decode"}
             } = web_event
    end

    test "parses token usage and diff updates" do
      usage_event =
        Events.parse!(%{
          "type" => "thread/tokenUsage/updated",
          "thread_id" => "thread_usage",
          "turn_id" => "turn_usage",
          "usage" => %{"input_tokens" => 10, "output_tokens" => 2},
          "delta" => %{"output_tokens" => 2}
        })

      assert %Events.ThreadTokenUsageUpdated{
               thread_id: "thread_usage",
               turn_id: "turn_usage",
               usage: %{"input_tokens" => 10, "output_tokens" => 2},
               delta: %{"output_tokens" => 2}
             } = usage_event

      diff = %{"ops" => [%{"op" => "add", "text" => "Hello"}]}

      diff_event =
        Events.parse!(%{
          "type" => "turn/diff/updated",
          "thread_id" => "thread_usage",
          "turn_id" => "turn_usage",
          "diff" => diff
        })

      assert %Events.TurnDiffUpdated{
               thread_id: "thread_usage",
               turn_id: "turn_usage",
               diff: ^diff
             } = diff_event

      assert %{
               "type" => "turn/diff/updated",
               "thread_id" => "thread_usage",
               "turn_id" => "turn_usage",
               "diff" => ^diff
             } = Events.to_map(diff_event)
    end

    test "parses account events" do
      updated =
        Events.parse!(%{
          "type" => "account/updated",
          "auth_mode" => "chatgpt"
        })

      assert %Events.AccountUpdated{auth_mode: "chatgpt"} = updated

      assert %{
               "type" => "account/updated",
               "auth_mode" => "chatgpt"
             } = Events.to_map(updated)

      login =
        Events.parse!(%{
          "type" => "account/login/completed",
          "loginId" => "login_1",
          "success" => true
        })

      assert %Events.AccountLoginCompleted{login_id: "login_1", success: true} = login

      assert %{
               "type" => "account/login/completed",
               "login_id" => "login_1",
               "success" => true
             } = Events.to_map(login)

      rate_limits = %{"primary" => %{"usedPercent" => 10.0}}

      rate_event =
        Events.parse!(%{
          "type" => "account/rateLimits/updated",
          "rateLimits" => rate_limits,
          "thread_id" => "thread_1"
        })

      assert %Events.AccountRateLimitsUpdated{
               rate_limits: %RateLimitSnapshot.Snapshot{
                 primary: %RateLimitSnapshot.Window{used_percent: 10.0}
               },
               thread_id: "thread_1"
             } = rate_event

      assert %{
               "type" => "account/rateLimits/updated",
               "rate_limits" => %{"primary" => %{"used_percent" => 10.0}},
               "thread_id" => "thread_1"
             } = Events.to_map(rate_event)
    end

    test "parses session configured events with initial messages" do
      event =
        Events.parse!(%{
          "type" => "sessionConfigured",
          "sessionId" => "sess_1",
          "forkedFromId" => "sess_0",
          "model" => "gpt-5.1-codex",
          "modelProviderId" => "openai",
          "approvalPolicy" => "untrusted",
          "sandboxPolicy" => %{"type" => "read-only"},
          "cwd" => "/tmp",
          "reasoningEffort" => "high",
          "historyLogId" => 12,
          "historyEntryCount" => 3,
          "initialMessages" => [%{"type" => "warning", "message" => "heads up"}],
          "rolloutPath" => "/tmp/rollout"
        })

      assert %Events.SessionConfigured{
               session_id: "sess_1",
               forked_from_id: "sess_0",
               model: "gpt-5.1-codex",
               model_provider_id: "openai",
               approval_policy: "untrusted",
               sandbox_policy: %{"type" => "read-only"},
               cwd: "/tmp",
               reasoning_effort: "high",
               history_log_id: 12,
               history_entry_count: 3,
               initial_messages: [%Events.Warning{message: "heads up"}],
               rollout_path: "/tmp/rollout"
             } = event
    end

    test "parses request user input events" do
      event =
        Events.parse!(%{
          "type" => "request_user_input",
          "id" => "req_1",
          "turn_id" => "turn_1",
          "questions" => [
            %{
              "id" => "q1",
              "header" => "Pick one",
              "question" => "Which?",
              "options" => [%{"label" => "A", "description" => "Option A"}]
            }
          ]
        })

      assert %Events.RequestUserInput{id: "req_1", turn_id: "turn_1", questions: [question]} =
               event

      assert %Codex.Protocol.RequestUserInput.Question{
               id: "q1",
               header: "Pick one",
               question: "Which?",
               options: [%Codex.Protocol.RequestUserInput.Option{label: "A"}]
             } = question
    end

    test "parses MCP startup updates with status maps" do
      event =
        Events.parse!(%{
          "type" => "mcp_startup_update",
          "server" => "mcp",
          "status" => %{"state" => "failed", "error" => "boom"}
        })

      assert %Events.McpStartupUpdate{server_name: "mcp", status: "failed", message: "boom"} =
               event
    end

    test "parses config warnings" do
      event =
        Events.parse!(%{
          "type" => "configWarning",
          "summary" => "Deprecated setting",
          "details" => "Use new flag"
        })

      assert %Events.ConfigWarning{summary: "Deprecated setting", details: "Use new flag"} = event
    end

    test "parses compaction notifications and carries thread context" do
      compaction = %{"dropped_item_ids" => ["msg_1"], "token_savings" => 120}

      event =
        Events.parse!(%{
          "type" => "turn/compaction/completed",
          "thread_id" => "thread_usage",
          "turn_id" => "turn_usage",
          "compaction" => compaction
        })

      assert %Events.TurnCompaction{
               thread_id: "thread_usage",
               turn_id: "turn_usage",
               compaction: ^compaction,
               stage: :completed
             } = event

      assert %{
               "type" => "turn/compaction/completed",
               "thread_id" => "thread_usage",
               "turn_id" => "turn_usage",
               "compaction" => ^compaction
             } = Events.to_map(event)
    end

    test "keeps thread and turn ids on item and error notifications" do
      error =
        Events.parse!(%{
          "type" => "error",
          "message" => "boom",
          "thread_id" => "thread_123",
          "turn_id" => "turn_456"
        })

      assert %Events.Error{
               message: "boom",
               thread_id: "thread_123",
               turn_id: "turn_456"
             } = error

      assert %{
               "type" => "error",
               "message" => "boom",
               "thread_id" => "thread_123",
               "turn_id" => "turn_456"
             } = Events.to_map(error)

      completed =
        Events.parse!(%{
          "type" => "item.completed",
          "thread_id" => "thread_123",
          "turn_id" => "turn_456",
          "item" => %{"id" => "msg_1", "type" => "agent_message", "text" => "hi"}
        })

      assert %Events.ItemCompleted{
               thread_id: "thread_123",
               turn_id: "turn_456",
               item: %Items.AgentMessage{id: "msg_1", text: "hi"}
             } = completed

      assert %{
               "thread_id" => "thread_123",
               "turn_id" => "turn_456"
             } = Events.to_map(completed) |> Map.take(["thread_id", "turn_id"])
    end
  end

  describe "round trip encoding" do
    test "thread_basic fixture encodes back to original maps" do
      raw_events =
        Path.join([File.cwd!(), "integration", "fixtures", "python", "thread_basic.jsonl"])
        |> File.stream!([], :line)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&Jason.decode!/1)

      for raw <- raw_events do
        parsed = Events.parse!(raw)
        assert raw == Events.to_map(parsed)
      end
    end

    test "item events serialise back to protocol maps" do
      event = %Events.ItemCompleted{
        item: %Items.CommandExecution{
          id: "cmd_1",
          command: "mix test",
          aggregated_output: "ok",
          exit_code: 0,
          status: :completed
        }
      }

      assert %{
               "type" => "item.completed",
               "item" => %{
                 "id" => "cmd_1",
                 "type" => "command_execution",
                 "command" => "mix test",
                 "aggregated_output" => "ok",
                 "exit_code" => 0,
                 "status" => "completed"
               }
             } = Events.to_map(event)
    end
  end
end
