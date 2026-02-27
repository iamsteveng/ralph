#!/bin/bash
# QA Codex Loop - deterministic JSON plan executor with optional remediation loops
# Usage: ./qa-codex-loop.sh --plan path/to/test-plan.json --tool codex|claude-code

set -euo pipefail

TOOL="codex"
PLAN_PATH=""
LOGS_ROOT="logs/qa-loop"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.3-codex}"
MAX_LOOPS="${QA_MAX_LOOPS:-3}"
MAX_DURATION="${QA_MAX_DURATION_SECONDS:-0}"
MAX_PATCH_COUNT="${QA_MAX_PATCH_COUNT:-0}"

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
    --max-loops)
      MAX_LOOPS="$2"
      shift 2
      ;;
    --max-duration)
      MAX_DURATION="$2"
      shift 2
      ;;
    --max-patch-count)
      MAX_PATCH_COUNT="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: ./qa-codex-loop.sh --plan <test-plan.json> --tool codex|claude-code [options]

Options:
  --logs-dir <path>         Logs directory root (default: logs/qa-loop)
  --max-loops <n>           Maximum remediation loops after initial full run (default: 3)
  --max-duration <seconds>  Optional max wall-clock duration, 0 disables limit (default: 0)
  --max-patch-count <n>     Optional max remediation patch attempts, 0 disables limit (default: 0)
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

if ! [[ "$MAX_LOOPS" =~ ^[0-9]+$ ]]; then
  echo "Error: --max-loops must be a non-negative integer"
  exit 1
fi

if ! [[ "$MAX_DURATION" =~ ^[0-9]+$ ]]; then
  echo "Error: --max-duration must be a non-negative integer (seconds)"
  exit 1
fi

if ! [[ "$MAX_PATCH_COUNT" =~ ^[0-9]+$ ]]; then
  echo "Error: --max-patch-count must be a non-negative integer"
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
RUN_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN_STARTED_EPOCH="$(date -u +%s)"
mkdir -p "$RUN_DIR/tests" "$RUN_DIR/attempts" "$RUN_DIR/remediation"

cp "$PLAN_PATH" "$RUN_DIR/plan.json"

echo "runId=$RUN_ID" > "$RUN_DIR/run.env"
echo "tool=$TOOL" >> "$RUN_DIR/run.env"
echo "plan=$PLAN_PATH" >> "$RUN_DIR/run.env"
echo "startedAt=$RUN_STARTED_AT" >> "$RUN_DIR/run.env"
echo "maxLoops=$MAX_LOOPS" >> "$RUN_DIR/run.env"
echo "maxDurationSeconds=$MAX_DURATION" >> "$RUN_DIR/run.env"
echo "maxPatchCount=$MAX_PATCH_COUNT" >> "$RUN_DIR/run.env"

extract_tag_text() {
  local file_path="$1"
  local tag="$2"

  perl -0777 -ne '
    use strict;
    use warnings;
    my ($tag) = @ARGV;
    if (/<$tag>\s*(.*?)\s*<\/$tag>/s) {
      my $text = $1;
      $text =~ s/\r/ /g;
      $text =~ s/\n+/ /g;
      $text =~ s/\s+/ /g;
      $text =~ s/^\s+|\s+$//g;
      print $text;
    }
  ' "$tag" "$file_path"
}

run_test() {
  local test_json="$1"
  local suite_tests_dir="$2"
  local suite_outcomes_file="$3"
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
  local reason=""
  local evidence=""

  test_id="$(jq -r '.id' <<< "$test_json")"
  title="$(jq -r '.title' <<< "$test_json")"
  level="$(jq -r '.level' <<< "$test_json")"
  priority="$(jq -r '.priority' <<< "$test_json")"

  test_dir="$suite_tests_dir/$test_id"
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

  reason="$(extract_tag_text "$output_file" "reason" || true)"
  evidence="$(extract_tag_text "$output_file" "evidence" || true)"

  echo "$status" > "$status_file"

  jq -n \
    --arg id "$test_id" \
    --arg title "$title" \
    --arg level "$level" \
    --arg priority "$priority" \
    --arg status "$status" \
    --arg reason "$reason" \
    --arg evidence "$evidence" \
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
      reason: $reason,
      evidence: $evidence,
      toolExitCode: $toolExit,
      outputFile: $outputFile,
      stderrFile: $stderrFile,
      executedAt: $executedAt
    }' > "$result_json"

  mkdir -p "$RUN_DIR/tests/$test_id"
  cp "$prompt_file" "$RUN_DIR/tests/$test_id/prompt.md"
  cp "$output_file" "$RUN_DIR/tests/$test_id/agent-output.txt"
  cp "$stderr_file" "$RUN_DIR/tests/$test_id/stderr.log"
  cp "$status_file" "$RUN_DIR/tests/$test_id/status.txt"
  cp "$result_json" "$RUN_DIR/tests/$test_id/result.json"

  cat "$result_json" >> "$suite_outcomes_file"
  echo >> "$suite_outcomes_file"
}

run_suite() {
  local suite_label="$1"
  local ids_json="$2"
  local suite_dir="$RUN_DIR/attempts/$suite_label"
  local suite_tests_dir="$suite_dir/tests"
  local suite_outcomes_file="$suite_dir/outcomes.jsonl"
  local suite_summary_file="$suite_dir/summary.json"
  local pass_count
  local fail_count
  local total_count
  local suite_status="PASS"

  mkdir -p "$suite_tests_dir"
  : > "$suite_outcomes_file"

  if [[ "$ids_json" == "[]" ]]; then
    while IFS= read -r test_json; do
      run_test "$test_json" "$suite_tests_dir" "$suite_outcomes_file"
    done < <(
      jq -c '.tests | sort_by((.id | ltrimstr("TC-") | tonumber))[]' "$PLAN_PATH"
    )
  else
    while IFS= read -r test_json; do
      run_test "$test_json" "$suite_tests_dir" "$suite_outcomes_file"
    done < <(
      jq -c --argjson ids "$ids_json" '
        .tests
        | map(select(.id as $id | $ids | index($id)))
        | sort_by((.id | ltrimstr("TC-") | tonumber))[]
      ' "$PLAN_PATH"
    )
  fi

  pass_count="$(jq -s '[.[] | select(.status == "PASS")] | length' "$suite_outcomes_file")"
  fail_count="$(jq -s '[.[] | select(.status == "FAIL")] | length' "$suite_outcomes_file")"
  total_count="$(jq -s 'length' "$suite_outcomes_file")"

  if [[ "$fail_count" -gt 0 ]]; then
    suite_status="FAIL"
  fi

  jq -n \
    --arg label "$suite_label" \
    --arg status "$suite_status" \
    --arg startedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson total "$total_count" \
    --argjson passed "$pass_count" \
    --argjson failed "$fail_count" \
    '{
      label: $label,
      status: $status,
      totals: {
        total: $total,
        passed: $passed,
        failed: $failed
      },
      completedAt: $startedAt
    }' > "$suite_summary_file"

  echo "$suite_status"
}

build_failed_ids_json() {
  local outcomes_file="$1"
  jq -s -c '[.[] | select(.status == "FAIL") | .id]' "$outcomes_file"
}

extract_root_causes_json() {
  local remediation_output="$1"

  perl -0777 -ne '
    use strict;
    use warnings;
    use JSON::PP;
    my @items = ();
    if (/<root_causes>\s*(.*?)\s*<\/root_causes>/s) {
      my $inner = $1;
      while ($inner =~ /<item>\s*(.*?)\s*<\/item>/sg) {
        my $item = $1;
        $item =~ s/\r/ /g;
        $item =~ s/\n+/ /g;
        $item =~ s/\s+/ /g;
        $item =~ s/^\s+|\s+$//g;
        push @items, $item if length $item;
      }
    }
    print encode_json(\@items);
  ' "$remediation_output"
}

run_remediation() {
  local loop_index="$1"
  local failed_ids_json="$2"
  local remediation_dir="$RUN_DIR/remediation/loop-$(printf '%02d' "$loop_index")"
  local prompt_file="$remediation_dir/prompt.md"
  local output_file="$remediation_dir/agent-output.txt"
  local stderr_file="$remediation_dir/stderr.log"
  local status_file="$remediation_dir/status.txt"
  local root_causes_file="$remediation_dir/root-causes.json"
  local test_context_file="$remediation_dir/failed-tests.json"
  local tool_exit=0

  mkdir -p "$remediation_dir"

  jq -s --argjson ids "$failed_ids_json" '
    map(select(.id as $id | $ids | index($id)))
    | map({id, title, reason, outputFile, stderrFile})
  ' "$LATEST_FULL_OUTCOMES_FILE" > "$test_context_file"

  {
    echo "# QA Remediation Loop"
    echo ""
    echo "Run ID: $RUN_ID"
    echo "Loop: $loop_index"
    echo ""
    echo "You are fixing failing QA tests in this repository."
    echo ""
    echo "## Failing Tests (Latest Full Gate)"
    jq '.' "$test_context_file"
    echo ""
    echo "## Required Actions"
    echo "1. Diagnose likely root causes from failing test output."
    echo "2. Apply minimal code changes to fix failures."
    echo "3. Do not edit generated logs under logs/qa-loop unless required by tooling."
    echo ""
    echo "Return exact tags in your final answer:"
    echo "<status>PATCHED</status> or <status>BLOCKED</status>"
    echo "<root_causes><item>cause 1</item><item>cause 2</item></root_causes>"
    echo "<summary>short description of code changes</summary>"
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

  if [[ "$tool_exit" -eq 0 ]] && grep -q "<status>PATCHED</status>" "$output_file"; then
    echo "PATCHED" > "$status_file"
  else
    echo "BLOCKED" > "$status_file"
  fi

  extract_root_causes_json "$output_file" > "$root_causes_file"

  LAST_ROOT_CAUSES_JSON="$(cat "$root_causes_file")"
}

LOOPS_PERFORMED=0
PATCH_ATTEMPTS=0
STOP_REASON="all_tests_passed"
LATEST_FULL_OUTCOMES_FILE=""
LAST_ROOT_CAUSES_JSON="[]"

INITIAL_STATUS="$(run_suite "loop-00-full" "[]")"
LATEST_FULL_OUTCOMES_FILE="$RUN_DIR/attempts/loop-00-full/outcomes.jsonl"

while [[ "$INITIAL_STATUS" == "FAIL" ]]; do
  now_epoch="$(date -u +%s)"
  elapsed_seconds="$((now_epoch - RUN_STARTED_EPOCH))"

  if [[ "$LOOPS_PERFORMED" -ge "$MAX_LOOPS" ]]; then
    STOP_REASON="max_loops_reached"
    break
  fi

  if [[ "$MAX_DURATION" -gt 0 && "$elapsed_seconds" -ge "$MAX_DURATION" ]]; then
    STOP_REASON="max_duration_reached"
    break
  fi

  if [[ "$MAX_PATCH_COUNT" -gt 0 && "$PATCH_ATTEMPTS" -ge "$MAX_PATCH_COUNT" ]]; then
    STOP_REASON="max_patch_count_reached"
    break
  fi

  LOOPS_PERFORMED="$((LOOPS_PERFORMED + 1))"

  FAILED_IDS_JSON="$(build_failed_ids_json "$LATEST_FULL_OUTCOMES_FILE")"

  run_remediation "$LOOPS_PERFORMED" "$FAILED_IDS_JSON"
  PATCH_ATTEMPTS="$((PATCH_ATTEMPTS + 1))"

  run_suite "loop-$(printf '%02d' "$LOOPS_PERFORMED")-affected" "$FAILED_IDS_JSON" >/dev/null
  INITIAL_STATUS="$(run_suite "loop-$(printf '%02d' "$LOOPS_PERFORMED")-full" "[]")"
  LATEST_FULL_OUTCOMES_FILE="$RUN_DIR/attempts/loop-$(printf '%02d' "$LOOPS_PERFORMED")-full/outcomes.jsonl"

done

FINAL_STATUS="PASS"
if [[ "$INITIAL_STATUS" == "FAIL" ]]; then
  FINAL_STATUS="FAIL"
fi

if [[ "$FINAL_STATUS" == "PASS" ]]; then
  STOP_REASON="all_tests_passed"
fi

cp "$LATEST_FULL_OUTCOMES_FILE" "$RUN_DIR/outcomes.jsonl"

PASS_COUNT="$(jq -s '[.[] | select(.status == "PASS")] | length' "$RUN_DIR/outcomes.jsonl")"
FAIL_COUNT="$(jq -s '[.[] | select(.status == "FAIL")] | length' "$RUN_DIR/outcomes.jsonl")"
TOTAL_COUNT="$(jq -s 'length' "$RUN_DIR/outcomes.jsonl")"
FAILED_IDS_JSON="$(build_failed_ids_json "$RUN_DIR/outcomes.jsonl")"

now_epoch="$(date -u +%s)"
ELAPSED_SECONDS="$((now_epoch - RUN_STARTED_EPOCH))"

jq -s --argjson ids "$FAILED_IDS_JSON" '
  map(select(.id as $id | $ids | index($id)))
  | map({id, title, reason})
' "$RUN_DIR/outcomes.jsonl" > "$RUN_DIR/unresolved.json"

jq -n \
  --arg runId "$RUN_ID" \
  --arg tool "$TOOL" \
  --arg status "$FINAL_STATUS" \
  --arg stopReason "$STOP_REASON" \
  --arg startedAt "$RUN_STARTED_AT" \
  --arg finishedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg planPath "$PLAN_PATH" \
  --argjson total "$TOTAL_COUNT" \
  --argjson passed "$PASS_COUNT" \
  --argjson failed "$FAIL_COUNT" \
  --argjson maxLoops "$MAX_LOOPS" \
  --argjson loopsPerformed "$LOOPS_PERFORMED" \
  --argjson maxDurationSeconds "$MAX_DURATION" \
  --argjson elapsedSeconds "$ELAPSED_SECONDS" \
  --argjson maxPatchCount "$MAX_PATCH_COUNT" \
  --argjson patchAttempts "$PATCH_ATTEMPTS" \
  --argjson unresolved "$(cat "$RUN_DIR/unresolved.json")" \
  --argjson lastRootCauses "$LAST_ROOT_CAUSES_JSON" \
  '{
    runId: $runId,
    tool: $tool,
    status: $status,
    stopReason: $stopReason,
    planPath: $planPath,
    startedAt: $startedAt,
    finishedAt: $finishedAt,
    totals: {
      total: $total,
      passed: $passed,
      failed: $failed
    },
    remediation: {
      maxLoops: $maxLoops,
      loopsPerformed: $loopsPerformed,
      maxDurationSeconds: $maxDurationSeconds,
      elapsedSeconds: $elapsedSeconds,
      maxPatchCount: $maxPatchCount,
      patchAttempts: $patchAttempts,
      unresolved: $unresolved,
      lastRootCauses: $lastRootCauses
    }
  }' > "$RUN_DIR/summary.json"

echo "$FINAL_STATUS" > "$RUN_DIR/status.txt"

echo "QA loop run directory: $RUN_DIR"
echo "Machine-readable status: $FINAL_STATUS"

if [[ "$FINAL_STATUS" == "PASS" ]]; then
  exit 0
fi

exit 1
