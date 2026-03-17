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

    test "parses guardian approval review lifecycle events" do
      started =
        Events.parse!(%{
          "type" => "guardian_approval_review_started",
          "thread_id" => "thr_1",
          "turn_id" => "turn_1",
          "target_item_id" => "item_1",
          "review" => %{
            "status" => "in_progress",
            "risk_score" => 42,
            "risk_level" => "medium",
            "rationale" => "Needs more context"
          },
          "action" => %{"type" => "allow"}
        })

      assert %Events.GuardianApprovalReviewStarted{
               thread_id: "thr_1",
               turn_id: "turn_1",
               target_item_id: "item_1",
               review: %Events.GuardianApprovalReview{
                 status: :in_progress,
                 risk_score: 42,
                 risk_level: :medium,
                 rationale: "Needs more context"
               },
               action: %{"type" => "allow"}
             } = started

      completed =
        Events.parse!(%{
          "type" => "guardian_approval_review_completed",
          "thread_id" => "thr_1",
          "turn_id" => "turn_1",
          "target_item_id" => "item_1",
          "review" => %{"status" => "approved"}
        })

      assert %Events.GuardianApprovalReviewCompleted{
               review: %Events.GuardianApprovalReview{status: :approved}
             } = completed

      assert %{
               "type" => "guardian_approval_review_started",
               "thread_id" => "thr_1",
               "turn_id" => "turn_1",
               "target_item_id" => "item_1",
               "review" => %{
                 "status" => "in_progress",
                 "risk_score" => 42,
                 "risk_level" => "medium",
                 "rationale" => "Needs more context"
               },
               "action" => %{"type" => "allow"}
             } = Events.to_map(started)
    end

    test "parses server request resolved events" do
      event =
        Events.parse!(%{
          "type" => "server_request_resolved",
          "thread_id" => "thr_1",
          "request_id" => 9
        })

      assert %Events.ServerRequestResolved{thread_id: "thr_1", request_id: 9} = event

      assert %{
               "type" => "server_request_resolved",
               "thread_id" => "thr_1",
               "request_id" => 9
             } = Events.to_map(event)
    end

    test "parses command and file approval request events" do
      command_event =
        Events.parse!(%{
          "type" => "command_approval_requested",
          "id" => 42,
          "thread_id" => "thr_1",
          "turn_id" => "turn_1",
          "item_id" => "item_1",
          "approval_id" => "approval_1",
          "reason" => "Need network access",
          "command" => "curl https://example.com",
          "cwd" => "/tmp/project",
          "command_actions" => [%{"type" => "search", "command" => "curl", "path" => nil}],
          "network_approval_context" => %{"host" => "example.com", "protocol" => "https"},
          "additional_permissions" => %{
            "network" => %{"enabled" => true},
            "fileSystem" => %{"write" => ["/tmp/project"]},
            "macos" => %{"accessibility" => true}
          },
          "skill_metadata" => %{"pathToSkillsMd" => "/tmp/project/SKILL.md"},
          "proposed_execpolicy_amendment" => ["curl", "https://example.com"],
          "proposed_network_policy_amendments" => [
            %{"host" => "example.com", "action" => "allow"}
          ],
          "available_decisions" => ["accept", %{"applyNetworkPolicyAmendment" => %{}}]
        })

      assert %Events.CommandApprovalRequested{
               id: 42,
               thread_id: "thr_1",
               turn_id: "turn_1",
               item_id: "item_1",
               approval_id: "approval_1",
               reason: "Need network access",
               command: "curl https://example.com",
               cwd: "/tmp/project",
               command_actions: [%{"type" => "search", "command" => "curl", "path" => nil}],
               network_approval_context: %{"host" => "example.com", "protocol" => "https"},
               additional_permissions:
                 %Codex.Protocol.RequestPermissions.RequestPermissionProfile{
                   network: %Codex.Protocol.RequestPermissions.AdditionalNetworkPermissions{
                     enabled: true
                   },
                   file_system:
                     %Codex.Protocol.RequestPermissions.AdditionalFileSystemPermissions{
                       write: ["/tmp/project"]
                     },
                   macos: %Codex.Protocol.RequestPermissions.AdditionalMacOsPermissions{
                     accessibility: true
                   }
                 },
               skill_metadata: %{"pathToSkillsMd" => "/tmp/project/SKILL.md"},
               proposed_execpolicy_amendment: ["curl", "https://example.com"],
               proposed_network_policy_amendments: [
                 %{"host" => "example.com", "action" => "allow"}
               ],
               available_decisions: ["accept", %{"applyNetworkPolicyAmendment" => %{}}]
             } = command_event

      file_event =
        Events.parse!(%{
          "type" => "file_approval_requested",
          "id" => 43,
          "thread_id" => "thr_1",
          "turn_id" => "turn_1",
          "item_id" => "item_2",
          "reason" => "Need extra write access",
          "grant_root" => "/tmp/project"
        })

      assert %Events.FileApprovalRequested{
               id: 43,
               thread_id: "thr_1",
               turn_id: "turn_1",
               item_id: "item_2",
               reason: "Need extra write access",
               grant_root: "/tmp/project"
             } = file_event

      assert %{
               "type" => "command_approval_requested",
               "additional_permissions" => %{
                 "network" => %{"enabled" => true},
                 "fileSystem" => %{"write" => ["/tmp/project"]},
                 "macos" => %{"accessibility" => true}
               }
             } = Events.to_map(command_event)

      assert %{
               "type" => "file_approval_requested",
               "grant_root" => "/tmp/project"
             } = Events.to_map(file_event)
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

    test "parses richer item variants and preserves agent phase" do
      plan_event =
        Events.parse!(%{
          "type" => "item.started",
          "item" => %{"id" => "plan_1", "type" => "plan", "text" => "Inspect repo"}
        })

      assert %Events.ItemStarted{item: %Items.Plan{id: "plan_1", text: "Inspect repo"}} =
               plan_event

      agent_event =
        Events.parse!(%{
          "type" => "item.completed",
          "item" => %{
            "id" => "msg_1",
            "type" => "agent_message",
            "text" => "done",
            "phase" => "final"
          }
        })

      assert %Events.ItemCompleted{
               item: %Items.AgentMessage{id: "msg_1", text: "done", phase: "final"}
             } = agent_event

      dynamic_event =
        Events.parse!(%{
          "type" => "item.completed",
          "item" => %{
            "id" => "dyn_1",
            "type" => "dynamic_tool_call",
            "tool" => "browser",
            "arguments" => %{"url" => "https://example.com"},
            "status" => "completed",
            "content_items" => [%{"type" => "inputText", "text" => "done"}],
            "success" => true
          }
        })

      assert %Events.ItemCompleted{
               item: %Items.DynamicToolCall{
                 id: "dyn_1",
                 tool: "browser",
                 status: :completed,
                 success: true
               }
             } = dynamic_event

      collab_event =
        Events.parse!(%{
          "type" => "item.completed",
          "item" => %{
            "id" => "collab_1",
            "type" => "collab_agent_tool_call",
            "tool" => "spawn",
            "status" => "in_progress",
            "sender_thread_id" => "sender",
            "receiver_thread_ids" => ["receiver"],
            "agents_states" => %{"receiver" => %{"status" => "running"}}
          }
        })

      assert %Events.ItemCompleted{
               item: %Items.CollabAgentToolCall{
                 id: "collab_1",
                 tool: "spawn",
                 status: :in_progress,
                 sender_thread_id: "sender",
                 receiver_thread_ids: ["receiver"]
               }
             } = collab_event

      image_event =
        Events.parse!(%{
          "type" => "item.completed",
          "item" => %{
            "id" => "img_1",
            "type" => "image_generation",
            "status" => "completed",
            "revised_prompt" => "contrast",
            "result" => "https://example.com/image.png",
            "saved_path" => "/tmp/image.png"
          }
        })

      assert %Events.ItemCompleted{
               item: %Items.ImageGeneration{
                 id: "img_1",
                 status: "completed",
                 revised_prompt: "contrast",
                 result: "https://example.com/image.png",
                 saved_path: "/tmp/image.png"
               }
             } = image_event

      compaction_event =
        Events.parse!(%{
          "type" => "item.completed",
          "item" => %{"id" => "compact_1", "type" => "context_compaction"}
        })

      assert %Events.ItemCompleted{item: %Items.ContextCompaction{id: "compact_1"}} =
               compaction_event
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
          "auth_mode" => "chatgpt",
          "plan_type" => "pro"
        })

      assert %Events.AccountUpdated{auth_mode: "chatgpt", plan_type: :pro} = updated

      assert %{
               "type" => "account/updated",
               "auth_mode" => "chatgpt",
               "plan_type" => "pro"
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

    test "parses thread, hook, reroute, fuzzy, and realtime notifications" do
      status_event =
        Events.parse!(%{
          "type" => "thread/status/changed",
          "thread_id" => "thr_1",
          "status" => %{"type" => "active", "active_flags" => ["waiting_on_approval"]}
        })

      assert %Events.ThreadStatusChanged{
               thread_id: "thr_1",
               status: %{type: :active, active_flags: [:waiting_on_approval]}
             } = status_event

      assert %{"type" => "thread/status/changed", "thread_id" => "thr_1"} =
               Events.to_map(status_event)

      assert %Events.ThreadArchived{thread_id: "thr_1"} =
               Events.parse!(%{"type" => "thread/archived", "thread_id" => "thr_1"})

      assert %Events.ThreadUnarchived{thread_id: "thr_1"} =
               Events.parse!(%{"type" => "thread/unarchived", "thread_id" => "thr_1"})

      assert %Events.SkillsChanged{} = Events.parse!(%{"type" => "skills/changed"})

      assert %Events.ThreadNameUpdated{thread_id: "thr_1", thread_name: "Main"} =
               Events.parse!(%{
                 "type" => "thread/name/updated",
                 "thread_id" => "thr_1",
                 "thread_name" => "Main"
               })

      run = %{"id" => "hook_1", "status" => "running"}

      assert %Events.HookStarted{thread_id: "thr_1", turn_id: "turn_1", run: ^run} =
               Events.parse!(%{
                 "type" => "hook/started",
                 "thread_id" => "thr_1",
                 "turn_id" => "turn_1",
                 "run" => run
               })

      assert %Events.HookCompleted{thread_id: "thr_1", turn_id: "turn_1", run: ^run} =
               Events.parse!(%{
                 "type" => "hook/completed",
                 "thread_id" => "thr_1",
                 "turn_id" => "turn_1",
                 "run" => run
               })

      reroute_event =
        Events.parse!(%{
          "type" => "model/rerouted",
          "thread_id" => "thr_1",
          "turn_id" => "turn_1",
          "from_model" => "gpt-5.2-codex",
          "to_model" => "gpt-5.4",
          "reason" => "highRiskCyberActivity"
        })

      assert %Events.ModelRerouted{
               thread_id: "thr_1",
               turn_id: "turn_1",
               from_model: "gpt-5.2-codex",
               to_model: "gpt-5.4",
               reason: :high_risk_cyber_activity
             } = reroute_event

      assert %Events.FuzzyFileSearchSessionUpdated{
               session_id: "ffs_1",
               query: "readme",
               files: [%{"path" => "README.md"}]
             } =
               Events.parse!(%{
                 "type" => "fuzzyFileSearch/sessionUpdated",
                 "session_id" => "ffs_1",
                 "query" => "readme",
                 "files" => [%{"path" => "README.md"}]
               })

      assert %Events.ThreadRealtimeStarted{thread_id: "thr_1", session_id: "rt_1"} =
               Events.parse!(%{
                 "type" => "thread/realtime/started",
                 "thread_id" => "thr_1",
                 "session_id" => "rt_1"
               })

      assert %Events.ThreadRealtimeItemAdded{
               thread_id: "thr_1",
               item: %{"type" => "message", "text" => "hello"}
             } =
               Events.parse!(%{
                 "type" => "thread/realtime/itemAdded",
                 "thread_id" => "thr_1",
                 "item" => %{"type" => "message", "text" => "hello"}
               })

      assert %Events.ThreadRealtimeOutputAudioDelta{
               thread_id: "thr_1",
               audio: %{"data" => "YWJj"}
             } =
               Events.parse!(%{
                 "type" => "thread/realtime/outputAudio/delta",
                 "thread_id" => "thr_1",
                 "audio" => %{"data" => "YWJj"}
               })

      assert %Events.ThreadRealtimeError{thread_id: "thr_1", message: "boom"} =
               Events.parse!(%{
                 "type" => "thread/realtime/error",
                 "thread_id" => "thr_1",
                 "message" => "boom"
               })

      assert %Events.ThreadRealtimeClosed{thread_id: "thr_1", reason: "done"} =
               Events.parse!(%{
                 "type" => "thread/realtime/closed",
                 "thread_id" => "thr_1",
                 "reason" => "done"
               })
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
          "thread_id" => "thr_1",
          "turn_id" => "turn_1",
          "item_id" => "item_1",
          "questions" => [
            %{
              "id" => "q1",
              "header" => "Pick one",
              "question" => "Which?",
              "isOther" => true,
              "isSecret" => true,
              "options" => [%{"label" => "A", "description" => "Option A"}]
            }
          ]
        })

      assert %Events.RequestUserInput{
               id: "req_1",
               thread_id: "thr_1",
               turn_id: "turn_1",
               item_id: "item_1",
               questions: [question]
             } = event

      assert %Codex.Protocol.RequestUserInput.Question{
               id: "q1",
               header: "Pick one",
               question: "Which?",
               is_other: true,
               is_secret: true,
               options: [%Codex.Protocol.RequestUserInput.Option{label: "A"}]
             } = question

      assert %{
               "type" => "request_user_input",
               "id" => "req_1",
               "thread_id" => "thr_1",
               "turn_id" => "turn_1",
               "item_id" => "item_1",
               "questions" => [
                 %{
                   "id" => "q1",
                   "header" => "Pick one",
                   "question" => "Which?",
                   "isOther" => true,
                   "isSecret" => true,
                   "options" => [%{"label" => "A", "description" => "Option A"}]
                 }
               ]
             } = Events.to_map(event)
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

    test "parses deprecation notice events" do
      event =
        Events.parse!(%{
          "type" => "deprecationNotice",
          "summary" => "Feature X is deprecated",
          "details" => "Use feature Y instead"
        })

      assert %Events.DeprecationNotice{
               summary: "Feature X is deprecated",
               details: "Use feature Y instead"
             } = event

      round_tripped = Events.to_map(event)
      assert round_tripped["type"] == "deprecationNotice"
      assert round_tripped["summary"] == "Feature X is deprecated"
      assert round_tripped["details"] == "Use feature Y instead"

      # Without details
      event_no_details =
        Events.parse!(%{
          "type" => "deprecationNotice",
          "summary" => "Old API removed"
        })

      assert %Events.DeprecationNotice{summary: "Old API removed", details: nil} =
               event_no_details

      map_no_details = Events.to_map(event_no_details)
      assert map_no_details["summary"] == "Old API removed"
      refute Map.has_key?(map_no_details, "details")
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
