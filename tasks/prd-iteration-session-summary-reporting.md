# PRD: Ralph Iteration Session Orchestration + Per-Iteration Summary Reporting

## 1. Introduction/Overview

Enhance the Ralph development skill so each iteration runs in a separate isolated OpenClaw agent session (sequentially), and after each iteration completes, a concise Codex-derived summary is sent to the main agent session.

This improves observability, makes iteration outcomes explicit, and allows safer stop/retry behavior without losing control of long-running loops.

## 2. Goals

- Run Ralph iterations one-at-a-time in isolated sessions.
- Send an immediate summary message to the main agent after every iteration.
- Standardize summary content so progress is easy to parse.
- Support stop/retry policy: stop on blocked, retry once on failed, then continue policy-defined flow.
- Keep default behavior deterministic and traceable.

## 3. User Stories

### US-001: Isolated session per iteration
**Description:** As an operator, I want each Ralph iteration to run in its own isolated agent session so failures are contained and progress is auditable.

**Acceptance Criteria:**
- [ ] Iterations run sequentially, exactly one worker session per iteration.
- [ ] Worker session executes a single iteration against active `prd.json`.
- [ ] Main orchestration loop tracks `current_iteration` and `max_iterations`.
- [ ] Iteration completion status is returned to the orchestrator.

### US-002: Per-iteration summary message to main session
**Description:** As an operator, I want a concise summary message after each iteration so I can monitor progress without reading raw logs.

**Acceptance Criteria:**
- [ ] After each iteration, orchestrator reads `logs/codex-iteration-<n>-last-message.txt` as primary summary source.
- [ ] Orchestrator sends one message to main session after each iteration.
- [ ] Message includes: iteration `n/N`, story attempted, result, commit hash, and short summary text.
- [ ] Message format remains concise and consistent.

### US-003: Failure/blocked handling policy
**Description:** As an operator, I want predictable loop behavior when an iteration blocks or fails.

**Acceptance Criteria:**
- [ ] If result is **blocked**, loop stops and requests user decision.
- [ ] If result is **failed**, system retries that iteration once.
- [ ] If retry also fails, status is reported and loop follows configured continue/stop policy.
- [ ] Blocked/failed outcomes are included in iteration summary message.

### US-004: Completion handling
**Description:** As an operator, I want clean end-of-run behavior once work is complete or limit is reached.

**Acceptance Criteria:**
- [ ] Loop stops when all stories are `passes: true`, max iterations reached, or user stops.
- [ ] Final summary includes completed stories, remaining stories, and produced commits.
- [ ] Final summary is sent to main session.

## 4. Functional Requirements

- **FR-1:** Orchestrator must spawn one isolated OpenClaw worker session per iteration.
- **FR-2:** Iterations must execute sequentially (no parallel execution by default).
- **FR-3:** Worker must run one iteration and return structured outcome fields (`story`, `result`, `commit`, `summary`).
- **FR-4:** After each iteration, orchestrator must send a summary to main session (`sessions_send`).
- **FR-5:** Summary source priority must be:
  1. `logs/codex-iteration-<n>-last-message.txt`
  2. fallback to iteration JSONL/log parsing when needed.
- **FR-6:** On blocked result, orchestrator must stop and request explicit user input.
- **FR-7:** On failed result, orchestrator must retry once before finalizing failure outcome.
- **FR-8:** Orchestrator must preserve iteration index and attempt count for reporting.

## 5. Non-Goals (Out of Scope)

- Posting per-iteration updates directly to external chat channels.
- Parallel iteration execution.
- Automatic PR merge behavior.
- Redesigning Ralph’s PRD schema.

## 6. Design Considerations

- Use a strict summary template for consistent parsing by humans and tools.
- Keep message payload short to avoid noisy updates.
- Preserve compatibility with existing Ralph logs and branch workflow.

## 7. Technical Considerations

- Use OpenClaw session orchestration primitives for spawn/send/monitor.
- Ensure orchestration logic handles missing log files gracefully.
- Add clear result taxonomy: `completed`, `blocked`, `failed`, `no-op`.
- Maintain deterministic retry semantics (max one retry for failed iteration).

## 8. Success Metrics

- 100% of iterations produce one summary message to main session.
- 100% of blocked iterations stop and request user decision.
- Failed iterations are retried exactly once in all retry scenarios.
- Operators can identify iteration outcome in under 10 seconds from message content.

## 9. Open Questions

- If first failure and retry both fail, should default behavior be stop or continue to next story?
- Should retry delay/backoff be fixed or configurable?
- Should summary include changed files by default or only when commit exists?
