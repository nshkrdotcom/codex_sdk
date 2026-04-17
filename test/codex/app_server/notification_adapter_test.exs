defmodule Codex.AppServer.NotificationAdapterTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.NotificationAdapter
  alias Codex.Events
  alias Codex.Items
  alias Codex.Protocol.RateLimit, as: RateLimitSnapshot

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

    test "maps thread lifecycle notifications" do
      assert {:ok,
              %Events.ThreadStatusChanged{
                thread_id: "thr_1",
                status: %{type: :active, active_flags: [:waiting_on_approval]}
              }} =
               NotificationAdapter.to_event("thread/status/changed", %{
                 "threadId" => "thr_1",
                 "status" => %{"type" => "active", "activeFlags" => ["waitingOnApproval"]}
               })

      assert {:ok, %Events.ThreadArchived{thread_id: "thr_1"}} =
               NotificationAdapter.to_event("thread/archived", %{"threadId" => "thr_1"})

      assert {:ok, %Events.ThreadUnarchived{thread_id: "thr_1"}} =
               NotificationAdapter.to_event("thread/unarchived", %{"threadId" => "thr_1"})

      assert {:ok, %Events.SkillsChanged{}} =
               NotificationAdapter.to_event("skills/changed", %{})

      assert {:ok, %Events.ThreadNameUpdated{thread_id: "thr_1", thread_name: "Main thread"}} =
               NotificationAdapter.to_event("thread/name/updated", %{
                 "threadId" => "thr_1",
                 "threadName" => "Main thread"
               })
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

    test "maps hook lifecycle notifications" do
      run = %{"id" => "hook_1", "eventName" => "sessionStart", "status" => "running"}

      assert {:ok, %Events.HookStarted{thread_id: "thr_1", turn_id: "turn_1", run: ^run}} =
               NotificationAdapter.to_event("hook/started", %{
                 "threadId" => "thr_1",
                 "turnId" => "turn_1",
                 "run" => run
               })

      assert {:ok, %Events.HookCompleted{thread_id: "thr_1", turn_id: "turn_1", run: ^run}} =
               NotificationAdapter.to_event("hook/completed", %{
                 "threadId" => "thr_1",
                 "turnId" => "turn_1",
                 "run" => run
               })
    end

    test "maps guardian approval review notifications" do
      params = %{
        "threadId" => "thr_1",
        "turnId" => "turn_1",
        "reviewId" => "review_1",
        "decisionSource" => "agent",
        "review" => %{
          "status" => "timedOut",
          "riskScore" => 7,
          "riskLevel" => "high",
          "rationale" => "Suspicious command"
        },
        "action" => %{"type" => "deny"}
      }

      assert {:ok,
              %Events.GuardianApprovalReviewStarted{
                thread_id: "thr_1",
                turn_id: "turn_1",
                review_id: "review_1",
                target_item_id: nil,
                review: %Events.GuardianApprovalReview{
                  status: :timed_out,
                  risk_score: 7,
                  risk_level: :high,
                  rationale: "Suspicious command"
                },
                action: %{"type" => "deny"}
              }} = NotificationAdapter.to_event("item/autoApprovalReview/started", params)

      assert {:ok,
              %Events.GuardianApprovalReviewCompleted{
                thread_id: "thr_1",
                turn_id: "turn_1",
                review_id: "review_1",
                target_item_id: nil,
                decision_source: :agent,
                review: %Events.GuardianApprovalReview{status: :timed_out}
              }} = NotificationAdapter.to_event("item/autoApprovalReview/completed", params)
    end

    test "maps resolved server requests" do
      assert {:ok, %Events.ServerRequestResolved{thread_id: "thr_1", request_id: "req_1"}} =
               NotificationAdapter.to_event("serverRequest/resolved", %{
                 "threadId" => "thr_1",
                 "requestId" => "req_1"
               })
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
      assert {:ok, %Events.AccountUpdated{auth_mode: "apiKey", plan_type: :pro}} =
               NotificationAdapter.to_event("account/updated", %{
                 "authMode" => "apiKey",
                 "planType" => "pro"
               })

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

    test "maps app, reroute, fuzzy search, and realtime notifications" do
      assert {:ok, %Events.AppListUpdated{data: [%{"id" => "app_1"}]}} =
               NotificationAdapter.to_event("app/list/updated", %{
                 "data" => [%{"id" => "app_1"}]
               })

      assert {:ok,
              %Events.ModelRerouted{
                thread_id: "thr_1",
                turn_id: "turn_1",
                from_model: "gpt-5.2-codex",
                to_model: "gpt-5.4",
                reason: :high_risk_cyber_activity
              }} =
               NotificationAdapter.to_event("model/rerouted", %{
                 "threadId" => "thr_1",
                 "turnId" => "turn_1",
                 "fromModel" => "gpt-5.2-codex",
                 "toModel" => "gpt-5.4",
                 "reason" => "highRiskCyberActivity"
               })

      assert {:ok,
              %Events.FuzzyFileSearchSessionUpdated{
                session_id: "ffs_1",
                query: "readme",
                files: [%{"path" => "README.md"}]
              }} =
               NotificationAdapter.to_event("fuzzyFileSearch/sessionUpdated", %{
                 "sessionId" => "ffs_1",
                 "query" => "readme",
                 "files" => [%{"path" => "README.md"}]
               })

      assert {:ok, %Events.FuzzyFileSearchSessionCompleted{session_id: "ffs_1"}} =
               NotificationAdapter.to_event("fuzzyFileSearch/sessionCompleted", %{
                 "sessionId" => "ffs_1"
               })

      assert {:ok, %Events.ThreadRealtimeStarted{thread_id: "thr_1", session_id: "rt_1"}} =
               NotificationAdapter.to_event("thread/realtime/started", %{
                 "threadId" => "thr_1",
                 "sessionId" => "rt_1"
               })

      assert {:ok,
              %Events.ThreadRealtimeItemAdded{
                thread_id: "thr_1",
                item: %{"type" => "message", "text" => "hello"}
              }} =
               NotificationAdapter.to_event("thread/realtime/itemAdded", %{
                 "threadId" => "thr_1",
                 "item" => %{"type" => "message", "text" => "hello"}
               })

      assert {:ok,
              %Events.ThreadRealtimeOutputAudioDelta{
                thread_id: "thr_1",
                audio: %{
                  "data" => "YWJj",
                  "sample_rate" => 24_000,
                  "num_channels" => 1,
                  "samples_per_channel" => 128
                }
              }} =
               NotificationAdapter.to_event("thread/realtime/outputAudio/delta", %{
                 "threadId" => "thr_1",
                 "audio" => %{
                   "data" => "YWJj",
                   "sampleRate" => 24_000,
                   "numChannels" => 1,
                   "samplesPerChannel" => 128
                 }
               })

      assert {:ok,
              %Events.ThreadRealtimeTranscriptDelta{
                thread_id: "thr_1",
                role: "assistant",
                delta: "Hello"
              }} =
               NotificationAdapter.to_event("thread/realtime/transcript/delta", %{
                 "threadId" => "thr_1",
                 "role" => "assistant",
                 "delta" => "Hello"
               })

      assert {:ok,
              %Events.ThreadRealtimeTranscriptDone{
                thread_id: "thr_1",
                role: "assistant",
                text: "Hello world"
              }} =
               NotificationAdapter.to_event("thread/realtime/transcript/done", %{
                 "threadId" => "thr_1",
                 "role" => "assistant",
                 "text" => "Hello world"
               })

      assert {:ok, %Events.ThreadRealtimeError{thread_id: "thr_1", message: "boom"}} =
               NotificationAdapter.to_event("thread/realtime/error", %{
                 "threadId" => "thr_1",
                 "message" => "boom"
               })

      assert {:ok, %Events.ThreadRealtimeClosed{thread_id: "thr_1", reason: "done"}} =
               NotificationAdapter.to_event("thread/realtime/closed", %{
                 "threadId" => "thr_1",
                 "reason" => "done"
               })
    end

    test "maps account rate limit updates" do
      params = %{"rateLimits" => %{"primary" => %{"usedPercent" => 10.0}}}

      assert {:ok,
              %Events.AccountRateLimitsUpdated{
                rate_limits: %RateLimitSnapshot.Snapshot{
                  primary: %RateLimitSnapshot.Window{used_percent: 10.0}
                }
              }} = NotificationAdapter.to_event("account/rateLimits/updated", params)
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

    test "maps MCP startup status notifications" do
      assert {:ok,
              %Events.McpServerStartupStatusUpdated{
                name: "filesystem",
                status: :failed,
                error: "boom"
              }} =
               NotificationAdapter.to_event("mcpServer/startupStatus/updated", %{
                 "name" => "filesystem",
                 "status" => "failed",
                 "error" => "boom"
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

    test "maps config warnings" do
      params = %{"summary" => "Deprecated", "details" => "Update config"}

      assert {:ok,
              %Events.ConfigWarning{
                summary: "Deprecated",
                details: "Update config"
              }} = NotificationAdapter.to_event("configWarning", params)
    end

    test "maps session configured notifications" do
      params = %{
        "sessionId" => "sess_1",
        "forkedFromId" => "sess_0",
        "model" => "gpt-5.1-codex",
        "modelProviderId" => "openai",
        "approvalPolicy" => "untrusted",
        "sandboxPolicy" => %{"type" => "read-only"},
        "cwd" => "/tmp",
        "reasoningEffort" => "high",
        "historyLogId" => 10,
        "historyEntryCount" => 2,
        "initialMessages" => [%{"type" => "warning", "message" => "heads up"}],
        "rolloutPath" => "/tmp/rollout"
      }

      assert {:ok,
              %Events.SessionConfigured{
                session_id: "sess_1",
                forked_from_id: "sess_0",
                model: "gpt-5.1-codex",
                model_provider_id: "openai",
                approval_policy: "untrusted",
                sandbox_policy: %{"type" => "read-only"},
                cwd: "/tmp",
                reasoning_effort: "high",
                history_log_id: 10,
                history_entry_count: 2,
                initial_messages: [%Events.Warning{message: "heads up"}],
                rollout_path: "/tmp/rollout"
              }} = NotificationAdapter.to_event("sessionConfigured", params)
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
