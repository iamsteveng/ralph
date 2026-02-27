# PRD: QA Testing Skill Suite (Ralph-Pattern)

## 1) Introduction / Overview

Build a QA-focused skill suite by copying the proven 3-skill Ralph pattern and adapting it for testing workflows.

The suite should support:
1. Converting a PRD file or testing objective into a structured **test plan markdown**
2. Converting the test plan markdown into a **machine-executable JSON plan**
3. Executing and gatekeeping the plan with **Codex or Claude Code**, iterating fixes until all tests pass (or max loop limit is reached)

Primary outcome: **faster release confidence via pre-merge quality gating**.

---

## 2) Goals

- Reduce time from testing intent to executable QA plan
- Standardize test planning and execution across acceptance, bug, test-gap, flaky, refactor-for-testability, and performance objectives
- Provide deterministic pass/fail gate criteria for CI and release checks
- Support iterative auto-fix loops to improve first-pass merge readiness

---

## 3) User Stories

### US-001: Generate test plan from PRD file
**Description:** As a QA engineer, I want to provide a PRD markdown file and receive a complete test plan markdown so that I can quickly move from feature intent to test coverage.

**Acceptance Criteria:**
- [ ] Before generation logic is finalized, review `skills/prd/SKILL.md` and document its structure pattern (sections, flow, and output conventions) as a reference for this skill
- [ ] Skill accepts a PRD `.md` file path input
- [ ] Skill extracts requirements/user stories and maps them to test scenarios
- [ ] Skill outputs a test plan markdown file with deterministic section structure aligned to the documented pattern
- [ ] Skill validates missing/ambiguous requirements and records assumptions

### US-002: Generate test plan from test objective text
**Description:** As a developer, I want to provide a free-text testing objective (e.g., flaky test investigation) and receive a structured test plan markdown so that ad-hoc quality work is standardized.

**Acceptance Criteria:**
- [ ] Skill accepts free-text objective input
- [ ] Skill supports objective types: acceptance, bug, test gap, flaky, refactor for testability, performance
- [ ] Skill includes objective-specific strategy templates in generated output
- [ ] Skill writes output as markdown to a predictable file path

### US-003: Convert test plan markdown to executable JSON
**Description:** As an automation pipeline, I want to convert test plan markdown into a strict JSON schema so that downstream executors can run the plan deterministically.

**Acceptance Criteria:**
- [ ] Before conversion logic is finalized, review `skills/ralph/SKILL.md` and document the converter pattern to mirror (conversion rules, ordering discipline, and validation expectations)
- [ ] Skill accepts test plan `.md` input
- [ ] Skill outputs valid JSON conforming to a documented and versioned schema
- [ ] JSON includes deterministic test IDs, steps, commands, pass/fail criteria, retry rules, and evidence fields
- [ ] Validation errors are surfaced with actionable messages and source line references

### US-004: Execute JSON plan with model/tool choice
**Description:** As a release engineer, I want to run the JSON plan with either Codex or Claude Code so that execution uses the best agent for the task.

**Acceptance Criteria:**
- [ ] Before implementation, review `ralph.sh` as baseline executor and document what can be reused for QA execution (iteration loop, tool invocation, logging, retry, status reporting)
- [ ] Gap analysis is documented for `ralph.sh` vs QA needs (JSON plan ingestion, deterministic per-test execution, per-test result capture, strict gate semantics)
- [ ] Execution skill supports explicit tool choice per run (`codex` or `claude-code`)
- [ ] Execution skill reads JSON plan and runs test items in deterministic order
- [ ] Execution stores logs, per-test outcomes, and aggregate summary
- [ ] Execution exits with machine-readable status (`PASS`/`FAIL`)

### US-005: Iterative self-healing gate until all tests pass
**Description:** As a team lead, I want the executor to keep fixing and re-running until all tests pass (bounded by max loops/time) so that quality gates are reliable.

**Acceptance Criteria:**
- [ ] On failure, executor enters loop: diagnose -> patch -> rerun affected tests -> rerun full gate
- [ ] Gate passes only when all required tests pass
- [ ] Loop controls exist: `maxLoops`, optional `maxDuration`, optional `maxPatchCount`
- [ ] If loop limit is reached without full pass, exit `FAIL` with unresolved items and last known root causes

### US-006: Reuse Ralph architecture pattern
**Description:** As a maintainer, I want QA skills to mirror Ralph skill conventions so that onboarding and maintenance are consistent.

**Acceptance Criteria:**
- [ ] Skill layout and command conventions align with existing Ralph 3-skill pattern
- [ ] Documentation references clear handoff points between skill 1 -> skill 2 -> skill 3
- [ ] Script entrypoints and logs mirror Ralph operational ergonomics
- [ ] Naming convention implemented as:
  - `qa-plan-generator`
  - `qa-plan-json`
  - `qa-codex-loop`

---

## 4) Functional Requirements

- **FR-1:** Provide Skill 1 (`qa-plan-generator`) that first mirrors the documented structure conventions from `skills/prd/SKILL.md`, then accepts either PRD markdown input or free-text testing objective input.
- **FR-2:** Skill 1 must generate a standardized `test-plan-*.md` containing scope, risk areas, test matrix, commands, pass criteria, and evidence expectations.
- **FR-3:** Skill 1 must support objective categories: acceptance, bug, test gap, flaky, refactor for testability, performance.
- **FR-4:** Provide Skill 2 (`qa-plan-json`) that mirrors `skills/ralph/SKILL.md` converter discipline, parsing test plan markdown and emitting `test-plan-*.json` in a strict, versioned schema.
- **FR-5:** Skill 2 must validate schema and fail fast on malformed or incomplete plans.
- **FR-6:** Provide Skill 3 (`qa-codex-loop`) and script entrypoint to execute JSON plan using explicit tool choice (`codex` or `claude-code`), implemented either as a focused extension of `ralph.sh` or as a new executor script derived from its loop/logging patterns.
- **FR-7:** Skill 3 must implement strict gate semantics: success only when all required tests pass.
- **FR-8:** Skill 3 must implement iterative remediation loops with configurable max loop limits.
- **FR-9:** Skill 3 must produce machine-readable result artifacts and human-readable summary artifacts.
- **FR-10:** All three skills must include usage docs, examples, and file naming conventions aligned to Ralph patterns.

---

## 5) Non-Goals (Out of Scope)

- Full autonomous product implementation beyond test-related fixes
- Replacing existing CI systems; this suite integrates with them
- Auto-triaging organizational ownership across teams
- Building a custom test runner from scratch (reuse existing project test commands)

---

## 6) Design Considerations

- Mirror Ralph skill UX: clear input contract, deterministic output artifact, explicit next-step handoff
- Keep generated markdown readable for humans and structured enough for robust parsing
- Maintain stable JSON schema versioning for downstream compatibility

---

## 7) Technical Considerations

- Define and version a canonical JSON schema (e.g., `qaPlanSchemaVersion`)
- Use robust markdown parsing rules (headings + fenced code + structured bullet conventions)
- Store execution logs per iteration under predictable directories (e.g., `logs/qa-loop/<run-id>/`)
- Include retry/flaky metadata support without weakening strict gate requirement
- Provide config options for loop safety:
  - `maxLoops` (required)
  - `maxDurationMinutes` (optional)
  - `maxPatchAttemptsPerTest` (optional)

---

## 8) Success Metrics

- >= 80% of QA objectives can be transformed to executable plans without manual reformatting
- >= 50% reduction in time from test objective to first gated run
- >= 30% reduction in merge retries caused by avoidable test failures
- Deterministic gate outputs available for 100% of runs (`PASS`/`FAIL` with evidence)

---

## 9) Open Questions

- What should default `maxLoops` be (e.g., 5, 8, 10)?
- Should CI mode enforce stricter timeouts than local mode?
- Should flaky tests be allowed only with explicit waiver metadata, even in strict mode?
- What minimum evidence artifacts are required per test type (logs only vs logs + screenshots + perf traces)?
