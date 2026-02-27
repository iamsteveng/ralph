# Ralph Agent Instructions

## Overview

Ralph is an autonomous AI agent loop that runs AI coding tools (Amp or Claude Code) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context.

## Commands

```bash
# Run the flowchart dev server
cd flowchart && npm run dev

# Build the flowchart
cd flowchart && npm run build

# Run Ralph with Amp (default)
./ralph.sh [max_iterations]

# Run Ralph with Claude Code
./ralph.sh --tool claude [max_iterations]
```

## Key Files

- `ralph.sh` - The bash loop that spawns fresh AI instances (supports `--tool amp` or `--tool claude`)
- `prompt.md` - Instructions given to each AMP instance
-  `CLAUDE.md` - Instructions given to each Claude Code instance
- `prd.json.example` - Example PRD format
- `flowchart/` - Interactive React Flow diagram explaining how Ralph works

## Flowchart

The `flowchart/` directory contains an interactive visualization built with React Flow. It's designed for presentations - click through to reveal each step with animations.

To run locally:
```bash
cd flowchart
npm install
npm run dev
```

## Patterns

- Each iteration spawns a fresh AI instance (Amp or Claude Code) with clean context
- Memory persists via git history, `progress.txt`, and `prd.json`
- Stories should be small enough to complete in one context window
- Always update AGENTS.md with discovered patterns for future iterations
- Codex iterations now emit `logs/codex-iteration-<n>-summary.txt` with `Iteration`, `Story`, `Result`, `Commit`, and `Summary` fields for downstream reporting
- Iteration updates to the main OpenClaw session are sent via `openclaw agent --session-id`; `OPENCLAW_SESSION_ID` and `OPENCLAW_SESSION_KEY` can override session targeting
- Iteration failure handling is deterministic: retry a `failed` outcome exactly once in the same iteration, but stop immediately on `blocked` or terminal retry failure
- In `flowchart/src/App.tsx`, avoid reading `useRef().current` from render-time initialization paths; `eslint` enforces `react-hooks/refs` and fails on ref access during render.
- `skills/qa-plan-generator/SKILL.md` supports two exclusive input modes (PRD path or free-text objective); objective mode must normalize to one allowed objective type and use deterministic filename `test-plan-objective-<objective-type>-<slug>.md`.
- `skills/qa-plan-json/SKILL.md` defines a strict, versioned converter contract (`qaPlanSchemaVersion: 1.0.0`); keep Scenario Matrix column mapping deterministic and require actionable validation errors in format `E-<code> [line <n>] <message> :: <fix guidance>`.
- `qa-codex-loop.sh` is the QA executor entrypoint: it requires `qaPlanSchemaVersion: 1.0.0`, sorts tests by numeric `TC-###`, and treats PASS strictly as zero exit plus `<status>PASS</status>` in agent output.
- `qa-codex-loop.sh` remediation mode runs full-gate first, then bounded loops (`--max-loops`, optional `--max-duration`, optional `--max-patch-count`) with sequence: patch attempt -> failed-test rerun -> full-gate rerun; inspect `summary.json` `stopReason` and `unresolved.json` for terminal failures.
