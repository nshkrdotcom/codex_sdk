#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PROMPTS_DIR="$SCRIPT_DIR"
LOG_DIR="$PROJECT_ROOT/logs/gap-impl-$(date +%Y%m%d-%H%M%S)"

START_NUM=1
END_NUM=8

if ! command -v claude >/dev/null 2>&1; then
  echo "[ERROR] claude is not on PATH"
  exit 1
fi

mkdir -p "$LOG_DIR"
cd "$PROJECT_ROOT"

echo "Codex SDK Gap Analysis Implementation Runner"
echo "Project root: $PROJECT_ROOT"
echo "Prompts dir:  $PROMPTS_DIR"
echo "Log dir:      $LOG_DIR"
echo "Running prompts: $(printf '%02d' $START_NUM) through $(printf '%02d' $END_NUM)"
echo "Mode: AUTONOMOUS (--dangerously-skip-permissions)"
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
  echo "[Starting Claude Code for $prompt_name...]"
  echo ""

  if command -v stdbuf >/dev/null 2>&1; then
    if cat "$prompt_file" | stdbuf -oL -eL claude --dangerously-skip-permissions --verbose -p --output-format stream-json 2>&1 | tee "$log_file"; then
      SUCCESSFUL+=("$prompt_name")
      return 0
    else
      FAILED+=("$prompt_name")
      return 1
    fi
  else
    if cat "$prompt_file" | claude --dangerously-skip-permissions --verbose -p --output-format stream-json 2>&1 | tee "$log_file"; then
      SUCCESSFUL+=("$prompt_name")
      return 0
    else
      FAILED+=("$prompt_name")
      return 1
    fi
  fi
}

for i in $(seq -f "%02g" "$START_NUM" "$END_NUM"); do
  # Pattern matches files like 01-mcp-tool-discovery.md
  prompt_file="$PROMPTS_DIR/${i}-"*.md

  if ! ls $prompt_file >/dev/null 2>&1; then
    echo "[WARN] Prompt ${i} not found, skipping"
    continue
  fi

  prompt_file=$(ls $prompt_file)
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
