#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export CODEX_MODEL="${CODEX_MODEL:-gpt-5.1-codex-mini}"
export CODEX_MODEL_DEFAULT="${CODEX_MODEL_DEFAULT:-gpt-5.1-codex-mini}"

echo "Using model: ${CODEX_MODEL}"
echo

examples=(
  "examples/basic_usage.exs"
  "examples/streaming.exs"
  "examples/structured_output.exs"
  "examples/conversation_and_resume.exs"
  "examples/concurrency_and_collaboration.exs"
  "examples/tool_bridging_auto_run.exs"
  "examples/sandbox_warnings_and_approval_bypass.exs"
  "examples/live_cli_demo.exs"
  "examples/live_session_walkthrough.exs"
  "examples/live_exec_controls.exs"
  "examples/live_tooling_stream.exs"
  "examples/live_telemetry_stream.exs"
  "examples/live_usage_and_compaction.exs"
  "examples/live_multi_turn_runner.exs"
  "examples/live_tooling_guardrails_approvals.exs"
  "examples/live_structured_hosted_tools.exs"
  "examples/live_mcp_and_sessions.exs"
  "examples/live_model_streaming_tracing.exs"
  "examples/live_attachments_and_search.exs"
  "examples/live_parity_and_status.exs"
  "examples/live_realtime_voice_stub.exs"
)

failures=()

for ex in "${examples[@]}"; do
  echo "==> mix run ${ex}"
  if ! mix run "${ex}"; then
    echo
    echo "FAILED: ${ex}"
    failures+=("${ex}")
  fi
  echo
done

if ((${#failures[@]} > 0)); then
  echo "Some examples failed:"
  for ex in "${failures[@]}"; do
    echo "  - ${ex}"
  done
  exit 1
fi
