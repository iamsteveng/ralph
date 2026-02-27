#!/bin/bash
# QA Codex Loop - deterministic JSON plan executor with tool choice
# Usage: ./qa-codex-loop.sh --plan path/to/test-plan.json --tool codex|claude-code

set -euo pipefail

TOOL="codex"
PLAN_PATH=""
LOGS_ROOT="logs/qa-loop"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.3-codex}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)
      PLAN_PATH="$2"
      shift 2
      ;;
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --logs-dir)
      LOGS_ROOT="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: ./qa-codex-loop.sh --plan <test-plan.json> --tool codex|claude-code [--logs-dir logs/qa-loop]
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$PLAN_PATH" ]]; then
  echo "Error: --plan is required"
  exit 1
fi

if [[ "$TOOL" != "codex" && "$TOOL" != "claude-code" ]]; then
  echo "Error: --tool must be 'codex' or 'claude-code'"
  exit 1
fi

if [[ ! -f "$PLAN_PATH" ]]; then
  echo "Error: plan file not found: $PLAN_PATH"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required"
  exit 1
fi

if [[ "$TOOL" == "codex" ]] && ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI not found"
  exit 1
fi

if [[ "$TOOL" == "claude-code" ]] && ! command -v claude >/dev/null 2>&1; then
  echo "Error: claude CLI not found"
  exit 1
fi

SCHEMA_VERSION="$(jq -r '.qaPlanSchemaVersion // empty' "$PLAN_PATH")"
if [[ "$SCHEMA_VERSION" != "1.0.0" ]]; then
  echo "Error: unsupported qaPlanSchemaVersion '$SCHEMA_VERSION' (expected 1.0.0)"
  exit 1
fi

TEST_COUNT="$(jq '.tests | length' "$PLAN_PATH")"
if [[ "$TEST_COUNT" -eq 0 ]]; then
  echo "Error: plan contains no tests"
  exit 1
fi

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$LOGS_ROOT/$RUN_ID"
mkdir -p "$RUN_DIR/tests"

cp "$PLAN_PATH" "$RUN_DIR/plan.json"

echo "runId=$RUN_ID" > "$RUN_DIR/run.env"
echo "tool=$TOOL" >> "$RUN_DIR/run.env"
echo "plan=$PLAN_PATH" >> "$RUN_DIR/run.env"
echo "startedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$RUN_DIR/run.env"

run_test() {
  local test_json="$1"
  local test_id
  local title
  local level
  local priority
  local test_dir
  local prompt_file
  local output_file
  local stderr_file
  local status_file
  local result_json
  local tool_exit=0
  local status="FAIL"

  test_id="$(jq -r '.id' <<< "$test_json")"
  title="$(jq -r '.title' <<< "$test_json")"
  level="$(jq -r '.level' <<< "$test_json")"
  priority="$(jq -r '.priority' <<< "$test_json")"

  test_dir="$RUN_DIR/tests/$test_id"
  mkdir -p "$test_dir"

  prompt_file="$test_dir/prompt.md"
  output_file="$test_dir/agent-output.txt"
  stderr_file="$test_dir/stderr.log"
  status_file="$test_dir/status.txt"
  result_json="$test_dir/result.json"

  {
    echo "# QA Test Execution"
    echo ""
    echo "Test ID: $test_id"
    echo "Title: $title"
    echo "Level: $level"
    echo "Priority: $priority"
    echo ""
    echo "You are executing one deterministic QA test case from a JSON test plan."
    echo "Run the provided commands exactly and evaluate pass criteria."
    echo ""
    echo "## Steps"
    jq -r '.steps[] | "- " + .' <<< "$test_json"
    echo ""
    echo "## Commands"
    if jq -e '.commands | length > 0' <<< "$test_json" >/dev/null; then
      jq -r '.commands[]' <<< "$test_json" | sed 's/^/- `&`/'
    else
      echo "- No commands provided (manual verification path)."
    fi
    echo ""
    echo "## Pass Criteria"
    jq -r '.passCriteria[] | "- " + .' <<< "$test_json"
    echo ""
    echo "## Evidence Required"
    jq -r '.evidence.required[] | "- " + .' <<< "$test_json"
    echo ""
    echo "Return exact tags in your final answer:"
    echo "<status>PASS</status> or <status>FAIL</status>"
    echo "<evidence>...concise evidence...</evidence>"
    echo "<reason>...concise failure reason when FAIL...</reason>"
  } > "$prompt_file"

  if [[ "$TOOL" == "codex" ]]; then
    set +e
    codex exec \
      --model "$CODEX_MODEL" \
      --dangerously-bypass-approvals-and-sandbox \
      "$(cat "$prompt_file")" \
      > "$output_file" \
      2> "$stderr_file"
    tool_exit=$?
    set -e
  else
    set +e
    claude --dangerously-skip-permissions --print < "$prompt_file" > "$output_file" 2> "$stderr_file"
    tool_exit=$?
    set -e
  fi

  if [[ "$tool_exit" -eq 0 ]] && grep -q "<status>PASS</status>" "$output_file"; then
    status="PASS"
  fi

  echo "$status" > "$status_file"

  jq -n \
    --arg id "$test_id" \
    --arg title "$title" \
    --arg level "$level" \
    --arg priority "$priority" \
    --arg status "$status" \
    --arg tool "$TOOL" \
    --arg outputFile "$output_file" \
    --arg stderrFile "$stderr_file" \
    --arg executedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson toolExit "$tool_exit" \
    '{
      id: $id,
      title: $title,
      level: $level,
      priority: $priority,
      tool: $tool,
      status: $status,
      toolExitCode: $toolExit,
      outputFile: $outputFile,
      stderrFile: $stderrFile,
      executedAt: $executedAt
    }' > "$result_json"

  cat "$result_json" >> "$RUN_DIR/outcomes.jsonl"
  echo >> "$RUN_DIR/outcomes.jsonl"
}

: > "$RUN_DIR/outcomes.jsonl"

while IFS= read -r test_json; do
  run_test "$test_json"
done < <(
  jq -c '.tests | sort_by((.id | ltrimstr("TC-") | tonumber))[]' "$PLAN_PATH"
)

PASS_COUNT="$(jq -s '[.[] | select(.status == "PASS")] | length' "$RUN_DIR/outcomes.jsonl")"
FAIL_COUNT="$(jq -s '[.[] | select(.status == "FAIL")] | length' "$RUN_DIR/outcomes.jsonl")"
TOTAL_COUNT="$(jq -s 'length' "$RUN_DIR/outcomes.jsonl")"
FINAL_STATUS="PASS"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  FINAL_STATUS="FAIL"
fi

jq -n \
  --arg runId "$RUN_ID" \
  --arg tool "$TOOL" \
  --arg status "$FINAL_STATUS" \
  --arg startedAt "$(grep '^startedAt=' "$RUN_DIR/run.env" | cut -d= -f2-)" \
  --arg finishedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg planPath "$PLAN_PATH" \
  --argjson total "$TOTAL_COUNT" \
  --argjson passed "$PASS_COUNT" \
  --argjson failed "$FAIL_COUNT" \
  '{
    runId: $runId,
    tool: $tool,
    status: $status,
    planPath: $planPath,
    startedAt: $startedAt,
    finishedAt: $finishedAt,
    totals: {
      total: $total,
      passed: $passed,
      failed: $failed
    }
  }' > "$RUN_DIR/summary.json"

echo "$FINAL_STATUS" > "$RUN_DIR/status.txt"

echo "QA loop run directory: $RUN_DIR"
echo "Machine-readable status: $FINAL_STATUS"

if [[ "$FINAL_STATUS" == "PASS" ]]; then
  exit 0
fi

exit 1
