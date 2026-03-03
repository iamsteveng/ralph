# Objective Rejection: Ambiguous Objective Type

## Input
- Objective Statement: Improve checkout quality quickly and make it robust

## Status
- Rejected

## Reason
- Ambiguous objective type. Terms like `improve`, `quickly`, and `robust` are non-specific and map to multiple types.

## Guidance
- Choose exactly one objective type: `acceptance`, `bug`, `test-gap`, `flaky`, `refactor-for-testability`, or `performance`.
- Provide a concrete target and expected outcome.
- Example valid objective: `Benchmark checkout p95 latency under fixed workload` (type: `performance`).
