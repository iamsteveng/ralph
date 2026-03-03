# Test Plan: Objective - Reproduce tax rounding discrepancy
## Source
- Mode: Objective
- Objective Statement: Reproduce and verify fix for tax rounding discrepancy in cart totals
- Objective Type: bug

## Scope
- Cart subtotal to tax-total calculation path
- Regression-sensitive total rendering

## Out of Scope
- New tax-rule feature implementation
- International tax-jurisdiction modeling

## Assumptions and Ambiguities
- A-001: Reported bug reproduces with known SKU/price fixture set. Assumed available for deterministic repro.

## Risk Areas
- Floating-point precision drift
- Hidden formatting/parsing transformations
- Regression in adjacent total-calculation branches

## Scenario Matrix
| ID | Source | Level | Scenario | Steps | Expected Result | Evidence | Priority |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-001 | OBJ-bug | integration | Deterministic reproduction | Build cart with fixture SKUs and inspect computed totals | Mismatch reproduces consistently pre-fix | Repro script output and snapshots | P0 |
| TC-002 | OBJ-bug | unit | Root-cause hypothesis check | Run focused calculation unit checks around rounding boundary | Failure aligns with suspected rounding branch | Unit test output and traced values | P0 |
| TC-003 | OBJ-bug | integration | Post-fix regression guard | Apply fix and rerun repro + adjacent tax scenarios | Original mismatch resolved; adjacent totals unchanged | Before/after comparison report | P0 |

## Execution Strategy
- Lock fixtures for deterministic reproduction before fix validation.
- Re-run adjacent scenarios after fix to guard regressions.

## Entry/Exit Criteria
- Entry: Bug fixture data and baseline failing signal are available.
- Exit: Repro resolved and regression checks remain stable.

## Evidence Requirements
- Reproduction logs
- Calculation trace around rounding boundary
- Post-fix comparison artifact

## Traceability
- Objective Type: bug
- Target: tax rounding in cart totals
- Primary Risk: latent regression while fixing rounding logic
- Expected Outcome: bug eliminated with regression guard coverage

## Objective Strategy
- focus: reproduce -> isolate -> verify fix -> guard regression
- required scenarios: deterministic repro, root-cause hypothesis check, post-fix regression
