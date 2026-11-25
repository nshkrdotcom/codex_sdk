#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
PROMPTS_DIR="$SCRIPT_DIR"
LOG_DIR="$PROJECT_ROOT/logs/codex-gap-impl-$(date +%Y%m%d-%H%M%S)"

PROMPTS=(
  "prompt-01-exec-config-observability.md"
  "prompt-02-app-server-sessions.md"
  "prompt-03-tools-guardrails.md"
  "prompt-04-mcp-skills-prompts.md"
)

if ! command -v codex >/dev/null 2>&1; then
  echo "[ERROR] codex is not on PATH"
  exit 1
fi

mkdir -p "$LOG_DIR"
cd "$PROJECT_ROOT"

echo "Codex SDK Gap Analysis Prompt Runner"
echo "Project root: $PROJECT_ROOT"
echo "Prompts dir:  $PROMPTS_DIR"
echo "Log dir:      $LOG_DIR"
echo "Prompts:      ${#PROMPTS[@]}"
echo "Mode: AUTONOMOUS (--dangerously-bypass-approvals-and-sandbox)"
echo "Output: JSONL (--json)"
echo ""

SUCCESSFUL=()
FAILED=()

run_prompt() {
  local prompt_file="$1"
  local prompt_name
  local log_file

  prompt_name="$(basename "$prompt_file" .md)"
  log_file="$LOG_DIR/${prompt_name}.log"

  echo ""
  echo "------------------------------------------------------------"
  echo "[$(date '+%H:%M:%S')] Starting: $prompt_name"
  echo "------------------------------------------------------------"
  echo ""
  echo "[Starting codex exec for $prompt_name...]"
  echo ""

  if command -v stdbuf >/dev/null 2>&1; then
    if cat "$prompt_file" | stdbuf -oL -eL codex exec --json --color never --dangerously-bypass-approvals-and-sandbox - 2>&1 | tee "$log_file"; then
      SUCCESSFUL+=("$prompt_name")
      return 0
    else
      FAILED+=("$prompt_name")
      return 1
    fi
  else
    if cat "$prompt_file" | codex exec --json --color never --dangerously-bypass-approvals-and-sandbox - 2>&1 | tee "$log_file"; then
      SUCCESSFUL+=("$prompt_name")
      return 0
    else
      FAILED+=("$prompt_name")
      return 1
    fi
  fi
}

for prompt_name in "${PROMPTS[@]}"; do
  prompt_file="$PROMPTS_DIR/$prompt_name"

  if [ ! -f "$prompt_file" ]; then
    echo "[WARN] Prompt $prompt_name not found, skipping"
    continue
  fi

  if run_prompt "$prompt_file"; then
    echo ""
    echo "[$(date '+%H:%M:%S')] Completed: $(basename "$prompt_file" .md)"
  else
    echo ""
    echo "[ERROR] $(basename "$prompt_file") failed (see log in $LOG_DIR)"
  fi
done

echo ""
echo "Summary - $(date)"

if [ ${#SUCCESSFUL[@]} -gt 0 ]; then
  echo "Successful (${#SUCCESSFUL[@]}):"
  for name in "${SUCCESSFUL[@]}"; do
    echo "  - $name"
  done
fi

if [ ${#FAILED[@]} -gt 0 ]; then
  echo ""
  echo "Failed (${#FAILED[@]}):"
  for name in "${FAILED[@]}"; do
    echo "  - $name"
  done
fi

echo ""
echo "All logs saved to: $LOG_DIR"

if [ ${#FAILED[@]} -gt 0 ]; then
  exit 1
fi

exit 0
