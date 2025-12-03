#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

examples=(
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

for ex in "${examples[@]}"; do
  echo
  echo "==> mix run ${ex}"
  mix run "${ex}"
done
