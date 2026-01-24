#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export CODEX_MODEL="${CODEX_MODEL:-gpt-5.1-codex-mini}"
export CODEX_MODEL_DEFAULT="${CODEX_MODEL_DEFAULT:-${CODEX_MODEL}}"

echo "Using model override: ${CODEX_MODEL}"
echo "Auth-aware defaults: chatgpt=gpt-5.2-codex api=gpt-5.1-codex-max"
echo

if [[ -z "${CODEX_API_KEY:-}" ]]; then
  echo "Warning: No CODEX_API_KEY set (CLI login required for live examples)"
  echo
fi

if [[ -n "${CODEX_PATH:-}" ]]; then
  if [[ ! -x "${CODEX_PATH}" ]]; then
    echo "CODEX_PATH is set but is not executable: ${CODEX_PATH}"
    exit 1
  fi
elif ! command -v codex >/dev/null 2>&1; then
  echo "codex binary not found - skipping examples"
  exit 0
fi

examples=(
  "examples/basic_usage.exs"
  "examples/streaming.exs"
  "examples/structured_output.exs"
  "examples/conversation_and_resume.exs"
  "examples/concurrency_and_collaboration.exs"
  "examples/tool_bridging_auto_run.exs"
  "examples/sandbox_warnings_and_approval_bypass.exs"
  "examples/live_app_server_basic.exs"
  "examples/live_app_server_streaming.exs"
  "examples/live_app_server_approvals.exs"
  "examples/live_app_server_mcp.exs"
  "examples/live_collaboration_modes.exs"
  "examples/live_personality.exs"
  "examples/live_thread_management.exs"
  "examples/live_web_search_modes.exs"
  "examples/live_rate_limits.exs"
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
  "examples/live_realtime_voice.exs"
  "examples/realtime_basic.exs"
  "examples/realtime_tools.exs"
  "examples/realtime_handoffs.exs"
  "examples/voice_pipeline.exs"
  "examples/voice_multi_turn.exs"
  "examples/voice_with_agent.exs"
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
