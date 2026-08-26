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

The serial catch-up agent ran after type consolidation merged. It re-read the
assessment and the resulting type-consolidation diff, then re-verified the
five deferred records before applying any source or test edit. The rest of
this file records the final result of that handoff.

## Handoff and catch-up result

This file recorded the phase-2 file collision. Type consolidation owned the
overlapping files, so five verified records were deferred. The serial
catch-up ran after the type-consolidation merge on current main
`531c3b1b649ea0aef9204e8b10ff963d712a3d23`.

Catch-up RED commit:
`65f43d8829e22566a6abe8d98a95ca331d793a20`.

The catch-up result is **4 APPLIED, 1 RESOLVED-UPSTREAM, 6 SKIPPED**.

## Deferred records

| Finding | Final status | Catch-up result | RED commit | GREEN commit |
| --- | --- | --- | --- | --- |
| dedup-001 | RESOLVED-UPSTREAM | `Severity.displayName` is used by MenuBuilder and ToastPolicy. ToastPolicy keeps the unreachable check. Statuspal keeps scheduled `Maintenance`. | `65f43d8829e22566a6abe8d98a95ca331d793a20` | `1fedc1a0fe471f4893747fb6571d63628e902c59` upstream |
| dedup-002 | APPLIED | Shared benchmark delay and green page fixture moved to `TestSupport`. | `65f43d8829e22566a6abe8d98a95ca331d793a20` | `9bcc849ded276f7e78ced261935444b8469abaa8` |
| dedup-003 | APPLIED | Shared `Duration.milliseconds` moved to the same benchmark support file. | `65f43d8829e22566a6abe8d98a95ca331d793a20` | `9bcc849ded276f7e78ced261935444b8469abaa8` |
| dedup-005 | APPLIED | One private generic `NSView` finder now serves the field and button helpers. | `65f43d8829e22566a6abe8d98a95ca331d793a20` | `f0e0a7d088b0d10019e8f0861d0efea21bf40227` |
| dedup-008 | APPLIED | One `TestSupport` persistence-break helper now serves both error-test files. | `65f43d8829e22566a6abe8d98a95ca331d793a20` | `3f07ee0788bc16063855d96467fc283d9548bdc1` |

`dedup-001` has no catch-up GREEN commit because its source change was
already complete upstream. The upstream GREEN commit is listed only as
evidence for the resolved status.

## Verification

Before the RED commit, `swift build` passed and `swift test` passed with 150
tests, 1 skipped test, and 0 failures. After each catch-up group, the focused
tests passed, then `swift build` passed and `swift test` passed with 150 tests,
1 skipped test, and 0 failures.

The skipped test is
`PerformanceHarnessTests.testEmitBenchTimings`; it requires `make bench`.

## Records not eligible for catch-up

These six records remain skipped and were not changed:

- `dedup-004` — `verified:false`.
- `dedup-006` — `verified:false`.
- `dedup-007` — `verified:false`, KEEP SEPARATE.
- `dedup-009` — `verified:false`, KEEP SEPARATE.
- `dedup-010` — `verified:false`, KEEP SEPARATE.
- `dedup-011` — `verified:false`.

No unverified or KEEP SEPARATE record was changed.

No item remains deferred.
