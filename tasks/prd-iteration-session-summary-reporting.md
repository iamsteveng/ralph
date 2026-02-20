# PRD: Ralph Iteration Update Messaging (Enhancement)

## 1) Overview

This is an **enhancement PRD**, not a ground-up redesign.

Ralph already runs iterative loops and already produces per-iteration Codex artifacts:
- `logs/codex-iteration-<n>.jsonl`
- `logs/codex-iteration-<n>-last-message.txt`
- `logs/codex-iteration-<n>-stderr.log`

The gap is that iteration progress is only visible in local logs/console. We need reliable, concise per-iteration updates sent to the main OpenClaw agent session.

## 2) Current State in Repo

From current `ralph.sh` behavior:
- Supports iterative execution with bounded `MAX_ITERATIONS`.
- Emits per-iteration logs and a last-message summary file.
- Detects completion via `<promise>COMPLETE</promise>`.
- Does **not** send per-iteration status back to main session.

## 3) Goal

Add minimal orchestration enhancements so that after each iteration finishes, the main agent receives a concise operational summary sourced from Codex output.

## 4) Scope (Enhancement Only)

In scope:
- One-iteration worker session pattern (sequential).
- Per-iteration summary message to main session.
- Stop on blocked; retry once on failed.

Out of scope:
- Rewriting Ralph loop from scratch.
- Replacing existing log format.
- Parallel execution.
- Auto-merge behavior.

## 5) User Stories

### US-001: Per-iteration main-session update
**Description:** As an operator, I want one update after each iteration so I can monitor progress without tailing logs.

**Acceptance Criteria:**
- [ ] After each iteration, system reads `logs/codex-iteration-<n>-last-message.txt`.
- [ ] Sends one concise message to main session.
- [ ] Message includes: `Iteration n/N`, `Story`, `Result`, `Commit`, `Summary`.
- [ ] Message is sent even when result is blocked/failed.

### US-002: Sequential worker-session orchestration
**Description:** As an operator, I want each iteration executed in an isolated worker session, sequentially.

**Acceptance Criteria:**
- [ ] Exactly one worker session is used per iteration.
- [ ] Iterations run in sequence (no overlap).
- [ ] Main loop tracks iteration index and total.
- [ ] Worker returns structured outcome to orchestrator.

### US-003: Failure policy (blocked + retry-once)
**Description:** As an operator, I want deterministic behavior for blocked/failed outcomes.

**Acceptance Criteria:**
- [ ] `blocked` stops the loop and requests user decision.
- [ ] `failed` retries the same iteration exactly once.
- [ ] If retry fails again, report terminal failure and stop.
- [ ] Summary messages clearly indicate original fail vs retry fail.

## 6) Functional Requirements

- **FR-1:** Keep existing Ralph log outputs unchanged.
- **FR-2:** Use `codex-iteration-<n>-last-message.txt` as primary summary source.
- **FR-3:** Send per-iteration update to main OpenClaw session via session messaging.
- **FR-4:** Use concise fixed message format for easy scanning.
- **FR-5:** Enforce sequential execution with one worker session per iteration.
- **FR-6:** Enforce policy: blocked => stop; failed => retry once => stop on second fail.

## 7) Message Format (Required)

- `Iteration n/N`
- `Story: US-### - <title|unknown>`
- `Result: completed | blocked | failed | no-op`
- `Commit: <hash|none>`
- `Summary: <1-3 lines from Codex last message>`

## 8) Success Criteria

- 100% of completed iterations produce one update to main session.
- 100% of blocked iterations stop immediately after reporting.
- Failed iterations are retried once, with both attempts visible in updates.
- No regressions to existing Ralph log generation.

## 9) Open Questions

- Should unknown story IDs be inferred from latest commit/progress text or shown as `unknown`?
- Should retry attempts be shown as `Iteration 2/5 (retry 1)` or separate label field?
