---
name: qa-plan-generator
description: "Generate a deterministic QA test plan markdown from a PRD markdown file. Use when you have a PRD and need structured test coverage planning output."
user-invocable: true
---

# QA Plan Generator

Generate a complete, deterministic QA test plan from a PRD markdown file.

---

## Pattern Mirror (from skills/prd/SKILL.md)

This skill intentionally mirrors the `skills/prd` structure pattern:

1. Clear job definition with explicit inputs/outputs
2. Step-based flow with deterministic section ordering
3. Strict markdown output conventions and file path rules
4. Validation checklist before final output

---

## The Job

1. Accept a PRD markdown file path
2. Extract goals, user stories, functional requirements, and constraints
3. Map extracted requirements to concrete QA scenarios
4. Emit a deterministic `test-plan-*.md` artifact
5. Validate missing/ambiguous requirements and record assumptions explicitly

---

## Step 1: Input Contract

Required input:

- PRD file path ending in `.md` (for example: `tasks/prd-qa-testing-skill-suite.md`)

If the file path is missing, unreadable, or not markdown, stop and report:

- what is invalid
- what input is expected
- one valid example path

---

## Step 2: Parse PRD Content

Extract, at minimum:

- PRD title
- goals
- user stories (`US-###`, title, description, acceptance criteria)
- functional requirements (`FR-*` style when present)
- non-goals/out-of-scope
- open questions

If a section is absent, continue and track it in assumptions/risks.

---

## Step 3: Map Requirements to Test Scenarios

For each user story and requirement:

- create positive-path scenarios
- create negative-path/error scenarios
- create edge-case scenarios
- identify required test level (unit, integration, e2e, manual/exploratory)
- define evidence and pass/fail criteria

Coverage rules:

- every user story must map to at least one scenario
- every explicit acceptance criterion must map to at least one scenario
- non-goals must be listed as exclusions (not test targets)

---

## Step 4: Deterministic Output Structure

Output section order must always be:

1. `# Test Plan: <PRD Title>`
2. `## Source`
3. `## Scope`
4. `## Out of Scope`
5. `## Assumptions and Ambiguities`
6. `## Risk Areas`
7. `## Scenario Matrix`
8. `## Execution Strategy`
9. `## Entry/Exit Criteria`
10. `## Evidence Requirements`
11. `## Traceability`

Scenario IDs must be deterministic:

- `TC-001`, `TC-002`, ... in stable order by source story ID, then criterion order

Required Scenario Matrix columns:

- `ID`
- `Source` (US/FR reference)
- `Level` (unit/integration/e2e/manual)
- `Scenario`
- `Steps`
- `Expected Result`
- `Evidence`
- `Priority` (P0/P1/P2)

---

## Step 5: Validate Ambiguity and Record Assumptions

Before finalizing output:

- flag ambiguous language (`fast`, `user-friendly`, `robust`, etc.)
- flag missing acceptance criteria or missing expected outcomes
- flag missing environment/setup details needed for execution

Record each issue under `## Assumptions and Ambiguities` using:

- `A-001`, `A-002`, ...
- issue description
- assumed interpretation used for planning
- impact if assumption is wrong

---

## Output

- **Format:** Markdown (`.md`)
- **Location:** same directory as input PRD by default
- **Filename:** `test-plan-<prd-file-basename>.md`

Example:

- input: `tasks/prd-qa-testing-skill-suite.md`
- output: `tasks/test-plan-prd-qa-testing-skill-suite.md`

---

## Checklist

Before returning the plan:

- [ ] Input path is a readable PRD markdown file
- [ ] All user stories mapped to scenarios
- [ ] Acceptance criteria mapped to scenarios
- [ ] Deterministic section order is followed
- [ ] Deterministic scenario IDs are used
- [ ] Ambiguities and assumptions are explicitly documented
