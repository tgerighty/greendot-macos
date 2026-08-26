# Deduplication deferred work

## Why this file exists

This is the phase-2 ownership record for the verified deduplication findings
in `deduplication-assessment.md`. The type-consolidation pass owns complete
cross-file sets where a deduplication move would otherwise collide. All five
verified `CONSOLIDATE` records are **DEFERRED** here; none was applied.

## Baseline at deferral

The clean base was commit `7347b965d278856b63660ae8f3f33931c1b17d34` on
`cleanup/apply-20260826-deduplication`.

```text
$ swift build
PASS — Build complete! (20.70s), exit 0

$ swift test
PASS — 150 tests executed, 1 skipped, 0 failures, exit 0
```

The single skipped test was
`PerformanceHarnessTests.testEmitBenchTimings` (the benchmark gate; run with
`make bench`). No production or test source was changed before or during this
deferral pass.

## Deferred items and exact collision ownership

| Finding | Status | Deduplication change | Collision owner and complete set | Catch-up action |
| --- | --- | --- | --- | --- |
| dedup-001 | DEFERRED | Centralize the baseline `Severity` display text used by `MenuBuilder` and `ToastPolicy`. | **types-004** owns `Sources/StatusCore/Severity.swift`, `Sources/greendot/MenuBuilder.swift`, and `Sources/StatusCore/ToastPolicy.swift`. Preserve `ToastPolicy` unreachable handling and `StatuspalParser` scheduled-maintenance handling. | After types-004, verify both call sites. Mark **RESOLVED-UPSTREAM** only if types-004 completed the shared mapping. |
| dedup-002 | DEFERRED | Move the identical benchmark page fixture and delay constant to `Tests/TestSupport`. | **types-002** owns the import migration for `Tests/StatusCoreTests/PollPerformanceTests.swift` and `Tests/greendotTests/PerformanceHarnessTests.swift`. | Rebase the fixture move after types-002 and compile both test targets. |
| dedup-003 | DEFERRED | Move the identical `Duration.milliseconds` extension to shared benchmark support. | **types-002** owns the same two benchmark files and their imports. | Rebase the timing-extension move after types-002; retain one shared definition. |
| dedup-005 | DEFERRED | Replace `field` and `button` recursive searches with a private generic finder. | **types-002** owns `Tests/greendotTests/StatusPageEditorTests.swift` for the import migration. | Apply the generic helper after types-002; retain the existing traversal contract. |
| dedup-008 | DEFERRED | Move the exact persistence-break helper to `Tests/TestSupport`. | **types-002** collision with `Tests/greendotTests/StatusPageEditorTests.swift` owns the complete two-file helper move; `Tests/greendotTests/AppDelegateRefreshErrorTests.swift` is free but must not be changed alone. | Move both copies together after types-002 and run the persistence-failure tests. |

## Non-deferred records

The remaining six records were not eligible for this phase: dedup-004,
dedup-006, and dedup-011 remain skipped because `verified:false`; dedup-007,
dedup-009, and dedup-010 remain skipped because they are `verified:false` and
`KEEP SEPARATE`.

## Handoff rule

The serial catch-up agent runs after type consolidation merges. It must
re-read the assessment and the resulting type-consolidation diff, then
re-verify the five deferred records before applying any source or test edit.
This file records deferral only; it is not evidence that any consolidation is
complete.
