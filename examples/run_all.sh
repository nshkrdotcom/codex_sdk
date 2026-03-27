#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage: bash examples/run_all.sh [--ollama] [--ollama-model MODEL] [--help]

Options:
  --ollama               Run all examples against local Codex OSS + Ollama.
  --ollama-model MODEL   Override the Ollama model. Default: gpt-oss:20b
  --help                 Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ollama)
      export CODEX_PROVIDER_BACKEND="oss"
      export CODEX_OSS_PROVIDER="ollama"
      shift
      ;;
    --ollama-model)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --ollama-model requires a model name." >&2
        exit 1
      fi

      export CODEX_PROVIDER_BACKEND="oss"
      export CODEX_OSS_PROVIDER="ollama"
      export CODEX_MODEL="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      echo >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "${CODEX_MODEL:-}" ]]; then
  echo "Using model override: ${CODEX_MODEL}"
else
  echo "Using shared core default model from cli_subprocess_core"
fi

if [[ "${CODEX_PROVIDER_BACKEND:-}" == "oss" && "${CODEX_OSS_PROVIDER:-}" == "ollama" ]]; then
  OLLAMA_MODEL="${CODEX_MODEL:-gpt-oss:20b}"
  export CODEX_MODEL="${OLLAMA_MODEL}"

  if ! command -v ollama >/dev/null 2>&1; then
    echo "ERROR: ollama binary not found for --ollama mode"
    exit 1
  fi

  echo "Using Codex local OSS provider: ollama"
  echo "  model: ${OLLAMA_MODEL}"
  echo
  echo "==> ollama --version"
  ollama --version
  echo
  echo "==> ollama show ${OLLAMA_MODEL}"
  if ! ollama show "${OLLAMA_MODEL}" >/dev/null 2>&1; then
    echo "ERROR: Ollama model not installed: ${OLLAMA_MODEL}" >&2
    exit 1
  fi

  export CODEX_API_KEY=""
fi

echo

if [[ "${CODEX_PROVIDER_BACKEND:-}" == "oss" && "${CODEX_OSS_PROVIDER:-}" == "ollama" ]]; then
  echo "CLI backend: Ollama via Codex OSS"
  echo "CLI model: ${CODEX_MODEL}"
  echo "CLI route: codex --oss --local-provider ollama --model ${CODEX_MODEL}"
  echo "Direct API examples: skipped in --ollama mode because they are OpenAI-only"
  EXAMPLE_TIMEOUT_SECONDS="${CODEX_EXAMPLES_TIMEOUT_SECONDS:-120}"
  echo "Per-example timeout: ${EXAMPLE_TIMEOUT_SECONDS}s"
  echo
else
  echo "CLI backend: standard Codex CLI"
  if [[ -n "${CODEX_MODEL:-}" ]]; then
    echo "CLI model override: ${CODEX_MODEL}"
  else
    echo "CLI model: shared core default"
  fi
  EXAMPLE_TIMEOUT_SECONDS="${CODEX_EXAMPLES_TIMEOUT_SECONDS:-}"
  echo
fi

if [[ "${CODEX_PROVIDER_BACKEND:-}" != "oss" || "${CODEX_OSS_PROVIDER:-}" != "ollama" ]] && [[ -z "${CODEX_API_KEY:-}" ]]; then
  echo "Warning: No CODEX_API_KEY set (CLI examples require codex login or CODEX_API_KEY)"
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

cli_examples=(
  "examples/basic_usage.exs"
  "examples/streaming.exs"
  "examples/structured_output.exs"
  "examples/conversation_and_resume.exs"
  "examples/concurrency_and_collaboration.exs"
  "examples/tool_bridging_auto_run.exs"
  "examples/sandbox_warnings_and_approval_bypass.exs"
  "examples/live_oauth_login.exs"
  "examples/live_app_server_basic.exs"
  "examples/live_app_server_filesystem.exs"
  "examples/live_app_server_plugins.exs"
  "examples/live_app_server_streaming.exs"
  "examples/live_app_server_approvals.exs"
  "examples/live_app_server_mcp.exs"
  "examples/live_collaboration_modes.exs"
  "examples/live_subagent_host_controls.exs"
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
  "examples/live_config_overrides.exs"
  "examples/live_options_config_overrides.exs"
  "examples/live_parity_and_status.exs"
)

direct_api_examples=(
  "examples/live_realtime_voice.exs"
  "examples/realtime_basic.exs"
  "examples/realtime_tools.exs"
  "examples/realtime_handoffs.exs"
  "examples/voice_pipeline.exs"
  "examples/voice_multi_turn.exs"
  "examples/voice_with_agent.exs"
)

failures=()
skipped=()

detect_direct_api_key() {
  if [[ -n "${CODEX_API_KEY:-}" || -n "${OPENAI_API_KEY:-}" ]]; then
    return 0
  fi

  if mix run -e 'if Codex.Auth.direct_api_key(), do: System.halt(0), else: System.halt(1)' >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

run_example_group() {
  local group_name="$1"
  shift
  local ex
  local rc

  echo "==> Running ${group_name}"
  for ex in "$@"; do
    echo "==> mix run ${ex}"

    rc=0

    if [[ -n "${EXAMPLE_TIMEOUT_SECONDS:-}" ]] && command -v timeout >/dev/null 2>&1; then
      timeout --foreground "${EXAMPLE_TIMEOUT_SECONDS}s" mix run "${ex}" || rc=$?
    else
      mix run "${ex}" || rc=$?
    fi

    if [[ "$rc" -ne 0 ]]; then
      echo
      if [[ "$rc" -eq 124 ]]; then
        echo "TIMED OUT: ${ex} (${EXAMPLE_TIMEOUT_SECONDS}s)"
        failures+=("${ex} (timeout=${EXAMPLE_TIMEOUT_SECONDS}s)")
      else
        echo "FAILED: ${ex} (exit=${rc})"
        failures+=("${ex} (exit=${rc})")
      fi
    fi
    echo
  done
}

run_example_group "CLI/Auth examples" "${cli_examples[@]}"

if [[ "${CODEX_PROVIDER_BACKEND:-}" == "oss" && "${CODEX_OSS_PROVIDER:-}" == "ollama" ]]; then
  echo "==> Skipping Direct OpenAI API examples in --ollama mode"
  for ex in "${direct_api_examples[@]}"; do
    skipped+=("${ex}")
    echo "SKIPPED: ${ex}"
  done
  echo
elif detect_direct_api_key; then
  run_example_group "Direct OpenAI API examples (realtime/voice)" "${direct_api_examples[@]}"
else
  echo "==> Skipping Direct OpenAI API examples (no CODEX_API_KEY/OPENAI_API_KEY/auth.json OPENAI_API_KEY)"
  for ex in "${direct_api_examples[@]}"; do
    skipped+=("${ex}")
    echo "SKIPPED: ${ex}"
  done
  echo
fi

if ((${#failures[@]} > 0)); then
  echo "Some examples failed:"
  for ex in "${failures[@]}"; do
    echo "  - ${ex}"
  done
  if ((${#skipped[@]} > 0)); then
    echo
    echo "Examples skipped:"
    for ex in "${skipped[@]}"; do
      echo "  - ${ex}"
    done
  fi
  exit 1
fi

if ((${#skipped[@]} > 0)); then
  echo "Examples completed with skips:"
  for ex in "${skipped[@]}"; do
    echo "  - ${ex}"
  done
else
  echo "All examples completed successfully."
fi
