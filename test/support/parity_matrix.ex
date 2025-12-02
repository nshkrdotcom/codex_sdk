defmodule Codex.TestSupport.ParityMatrix do
  @moduledoc false

  @entries [
    %{
      category: :runner_loop,
      status: :complete,
      fixtures: [
        "thread_basic.jsonl",
        "thread_auto_run_step1.jsonl",
        "thread_auto_run_step2.jsonl",
        "thread_auto_run_pending.jsonl",
        "thread_new_command.jsonl",
        "thread_early_exit.jsonl"
      ],
      tests: [
        Codex.ThreadTest,
        Codex.AgentRunnerTest,
        Codex.ThreadAutoRunTest
      ]
    },
    %{
      category: :guardrails,
      status: :complete,
      fixtures: ["thread_basic.jsonl"],
      tests: [
        Codex.GuardrailTest,
        Codex.AgentRunnerStreamedTest
      ]
    },
    %{
      category: :function_tools,
      status: :complete,
      fixtures: [
        "thread_structured.jsonl",
        "thread_structured_invalid.jsonl"
      ],
      tests: [
        Codex.FunctionToolTest,
        Codex.ToolOutputTest
      ]
    },
    %{
      category: :hosted_tools,
      status: :partial,
      fixtures: [
        "thread_tool_auto_step1.jsonl",
        "thread_tool_auto_step2.jsonl",
        "thread_tool_auto_pending.jsonl",
        "thread_tool_retry_step1.jsonl",
        "thread_tool_retry_step2.jsonl",
        "thread_tool_retry_step3.jsonl",
        "thread_tool_requires_approval.jsonl",
        "thread_file_search_step1.jsonl",
        "thread_file_search_step2.jsonl"
      ],
      tests: [
        Codex.HostedToolsTest,
        Codex.AgentRunnerTest,
        Codex.ApprovalsSafetyTest
      ]
    },
    %{
      category: :mcp,
      status: :partial,
      fixtures: ["thread_mcp_rich.jsonl"],
      tests: [
        Codex.MCP.ClientTest,
        Codex.ThreadTest
      ]
    },
    %{
      category: :sessions,
      status: :partial,
      fixtures: [
        "thread_auto_run_step1.jsonl",
        "thread_auto_run_step2.jsonl"
      ],
      tests: [
        Codex.SessionTest,
        Codex.ThreadTest
      ]
    },
    %{
      category: :streaming,
      status: :complete,
      fixtures: [
        "thread_basic.jsonl",
        "thread_auto_run_step1.jsonl",
        "thread_auto_run_step2.jsonl",
        "thread_usage_events.jsonl"
      ],
      tests: [
        Codex.AgentRunnerStreamedTest,
        Codex.ThreadStreamTest
      ]
    },
    %{
      category: :tracing_usage,
      status: :complete,
      fixtures: [
        "thread_usage_events.jsonl",
        "thread_usage_compaction.jsonl"
      ],
      tests: [
        Codex.TracingUsageTest,
        Codex.TelemetryTest
      ]
    },
    %{
      category: :approvals_safety,
      status: :complete,
      fixtures: [
        "thread_tool_requires_approval.jsonl",
        "thread_error_sandbox_assessment.jsonl"
      ],
      tests: [
        Codex.ApprovalsSafetyTest,
        Codex.ApprovalsTest
      ]
    }
  ]

  @spec entries() :: [map()]
  def entries, do: @entries
end
