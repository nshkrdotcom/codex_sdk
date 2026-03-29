#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage: bash examples/run_all.sh [--ollama] [--ollama-model MODEL] [--cwd PATH] [--ssh-host HOST] [--ssh-user USER] [--ssh-port PORT] [--ssh-identity-file PATH] [--help]

Options:
  --ollama               Run all examples against local Codex OSS + Ollama.
  --ollama-model MODEL   Override the Ollama model. Default: gpt-oss:20b
  --cwd PATH             Working directory override. In SSH mode, app-server thread demos require a trusted remote cwd.
  --ssh-host HOST        Run CLI/app-server examples over execution_surface=:ssh_exec.
  --ssh-user USER        Optional SSH user override.
  --ssh-port PORT        Optional SSH port override.
  --ssh-identity-file P  Optional SSH identity file.
  --help                 Show this help text.
EOF
}

example_args=()
ssh_enabled=false
cwd_configured=false
ssh_aux_args_set=false

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
    --cwd)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --cwd requires a value." >&2
        exit 1
      fi

      example_args+=("$1" "$2")
      cwd_configured=true
      shift 2
      ;;
    --cwd=*)
      example_args+=("$1")
      cwd_configured=true
      shift
      ;;
    --ssh-host|--ssh-user|--ssh-port|--ssh-identity-file)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: $1 requires a value." >&2
        exit 1
      fi

      example_args+=("$1" "$2")
      if [[ "$1" == "--ssh-host" ]]; then
        ssh_enabled=true
      else
        ssh_aux_args_set=true
      fi
      shift 2
      ;;
    --ssh-host=*|--ssh-user=*|--ssh-port=*|--ssh-identity-file=*)
      example_args+=("$1")
      if [[ "$1" == --ssh-host=* ]]; then
        ssh_enabled=true
      else
        ssh_aux_args_set=true
      fi
      shift
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

if [[ "$ssh_enabled" == true && "${CODEX_PROVIDER_BACKEND:-}" == "oss" && "${CODEX_OSS_PROVIDER:-}" == "ollama" ]]; then
  echo "ERROR: --ssh-host cannot be combined with --ollama/--ollama-model." >&2
  exit 1
fi

if [[ "$ssh_enabled" != true && "$ssh_aux_args_set" == true ]]; then
  echo "ERROR: --ssh-user/--ssh-port/--ssh-identity-file require --ssh-host." >&2
  exit 1
fi

ollama_enabled=false
if [[ "${CODEX_PROVIDER_BACKEND:-}" == "oss" && "${CODEX_OSS_PROVIDER:-}" == "ollama" ]]; then
  ollama_enabled=true
fi

if [[ -n "${CODEX_MODEL:-}" ]]; then
  echo "Using model override: ${CODEX_MODEL}"
else
  echo "Using shared core default model from cli_subprocess_core"
fi

if [[ "$ollama_enabled" == true ]]; then
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

if [[ "$ollama_enabled" == true ]]; then
  echo "CLI backend: Ollama via Codex OSS"
  echo "CLI model: ${CODEX_MODEL}"
  echo "CLI route: codex --oss --local-provider ollama --model ${CODEX_MODEL}"
  echo "Direct API examples: skipped in --ollama mode because they are OpenAI-only"
  EXAMPLE_TIMEOUT_SECONDS="${CODEX_EXAMPLES_TIMEOUT_SECONDS:-120}"
  echo "Per-example timeout: ${EXAMPLE_TIMEOUT_SECONDS}s"
  echo
else
  echo "CLI backend: standard Codex CLI"
  if [[ "$ssh_enabled" == true ]]; then
    echo "CLI execution surface: ssh_exec"
  else
    echo "CLI execution surface: local_subprocess"
  fi
  if [[ "$cwd_configured" == true ]]; then
    echo "CLI/App-server cwd override: configured via --cwd"
  elif [[ "$ssh_enabled" == true ]]; then
    echo "CLI/App-server cwd override: none"
    echo "App-server thread demos will be skipped unless --cwd points at a trusted remote directory."
  fi
  if [[ -n "${CODEX_MODEL:-}" ]]; then
    echo "CLI model override: ${CODEX_MODEL}"
  else
    echo "CLI model: shared core default"
  fi
  EXAMPLE_TIMEOUT_SECONDS="${CODEX_EXAMPLES_TIMEOUT_SECONDS:-}"
  echo
fi

if [[ "$ssh_enabled" != true && "$ollama_enabled" != true && -z "${CODEX_API_KEY:-}" ]]; then
  echo "Warning: No CODEX_API_KEY set (CLI examples require codex login or CODEX_API_KEY)"
  echo
fi

if [[ "$ssh_enabled" != true && -n "${CODEX_PATH:-}" ]]; then
  if [[ ! -x "${CODEX_PATH}" ]]; then
    echo "CODEX_PATH is set but is not executable: ${CODEX_PATH}"
    exit 1
  fi
elif [[ "$ssh_enabled" != true ]] && ! command -v codex >/dev/null 2>&1; then
  echo "codex binary not found - skipping examples"
  exit 0
fi

ssh_ready_cli_examples=(
  "examples/basic_usage.exs"
  "examples/streaming.exs"
  "examples/conversation_and_resume.exs"
  "examples/concurrency_and_collaboration.exs"
  "examples/tool_bridging_auto_run.exs"
  "examples/sandbox_warnings_and_approval_bypass.exs"
  "examples/live_app_server_filesystem.exs"
  "examples/live_app_server_mcp.exs"
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
  "examples/live_config_overrides.exs"
  "examples/live_options_config_overrides.exs"
  "examples/live_parity_and_status.exs"
)

ssh_requires_cwd_cli_examples=(
  "examples/live_app_server_basic.exs"
  "examples/live_app_server_streaming.exs"
  "examples/live_collaboration_modes.exs"
  "examples/live_subagent_host_controls.exs"
  "examples/live_personality.exs"
  "examples/live_thread_management.exs"
)

local_only_cli_examples=(
  "examples/structured_output.exs"
  "examples/live_app_server_plugins.exs"
  "examples/live_app_server_approvals.exs"
  "examples/live_attachments_and_search.exs"
  "examples/live_oauth_login.exs"
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
    if [[ ${#example_args[@]} -gt 0 ]]; then
      echo "==> mix run ${ex} -- ${example_args[*]}"
    else
      echo "==> mix run ${ex}"
    fi

    rc=0

    if [[ -n "${EXAMPLE_TIMEOUT_SECONDS:-}" ]] && command -v timeout >/dev/null 2>&1; then
      if [[ ${#example_args[@]} -gt 0 ]]; then
        timeout --foreground "${EXAMPLE_TIMEOUT_SECONDS}s" mix run "${ex}" -- "${example_args[@]}" ||
          rc=$?
      else
        timeout --foreground "${EXAMPLE_TIMEOUT_SECONDS}s" mix run "${ex}" || rc=$?
      fi
    else
      if [[ ${#example_args[@]} -gt 0 ]]; then
        mix run "${ex}" -- "${example_args[@]}" || rc=$?
      else
        mix run "${ex}" || rc=$?
      fi
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

run_example_group "CLI/App-server examples" "${ssh_ready_cli_examples[@]}"

if [[ "$ssh_enabled" == true && "$cwd_configured" == true ]]; then
  run_example_group "SSH app-server examples requiring --cwd" "${ssh_requires_cwd_cli_examples[@]}"
elif [[ "$ssh_enabled" == true ]]; then
  echo "==> Skipping SSH app-server examples that require --cwd"
  for ex in "${ssh_requires_cwd_cli_examples[@]}"; do
    skipped+=("${ex}")
    echo "SKIPPED: ${ex} (--cwd <remote trusted directory> is required for SSH app-server thread demos)"
  done
  echo
else
  run_example_group "App-server examples" "${ssh_requires_cwd_cli_examples[@]}"
fi

if [[ "$ssh_enabled" == true ]]; then
  echo "==> Skipping local-only examples in SSH mode"
  for ex in "${local_only_cli_examples[@]}"; do
    skipped+=("${ex}")
    case "$ex" in
      "examples/live_oauth_login.exs")
        echo "SKIPPED: ${ex} (local OAuth/browser/device flow is not execution_surface-based)"
        ;;
      "examples/live_app_server_plugins.exs")
        echo "SKIPPED: ${ex} (provisions host-local plugin fixtures that do not exist on the remote host)"
        ;;
      "examples/live_app_server_approvals.exs")
        echo "SKIPPED: ${ex} (provisions host-local approval fixtures and isolated CODEX_HOME state)"
        ;;
      "examples/structured_output.exs")
        echo "SKIPPED: ${ex} (writes a host-local output schema file that is not copied to the remote host)"
        ;;
      "examples/live_attachments_and_search.exs")
        echo "SKIPPED: ${ex} (stages host-local attachment paths that are not copied to the remote host)"
        ;;
      *)
        echo "SKIPPED: ${ex}"
        ;;
    esac
  done
  echo
else
  run_example_group "Local-only examples" "${local_only_cli_examples[@]}"
fi

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
