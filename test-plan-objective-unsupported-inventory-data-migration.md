# Objective Rejection: Unsupported Objective Type

## Input
- Objective Statement: Perform inventory data migration dry run and reconciliation

## Status
- Rejected

## Reason
- Unsupported objective type. This objective does not map to one of the allowed QA objective types.

## Guidance
- Allowed objective types: `acceptance`, `bug`, `test-gap`, `flaky`, `refactor-for-testability`, `performance`.
- Rephrase the objective to match one allowed type.
- Example valid objective: `Investigate flaky checkout e2e around retries` (type: `flaky`).
