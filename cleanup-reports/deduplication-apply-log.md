# Deduplication cleanup apply log

## Scope and result

- Assessment: `cleanup-reports/deduplication-assessment.md`
- Branch: `cleanup/apply-20260826-deduplication`
- Worktree: `/Users/terry.gerighty/coding/greendot.cleanup-apply-20260826-deduplication`
- Base commit: `7347b965d278856b63660ae8f3f33931c1b17d34`
- Source and test changes: none
- Allowed files: this log and `cleanup-reports/deduplication-deferred.md`

The authoritative machine-readable assessment contains 11 findings. The
phase-2 collision priority assigns the complete overlapping file sets to type
consolidation. Therefore no deduplication code or test change was applied.

Result: **0 applied, 6 skipped, 5 deferred**.

## Baseline verification

Both commands were run before this documentation-only change from the clean
base commit above:

```text
$ swift build
Build complete! (20.70s)
Exit: 0

$ swift test
Test Suite 'All tests' passed at 2026-08-26 05:38:32.178.
    Executed 150 tests, with 1 test skipped and 0 failures (0 unexpected)
Exit: 0

Swift Testing summary:
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

The skipped test was
`PerformanceHarnessTests.testEmitBenchTimings`; it is the benchmark gate and
requires `make bench`.

## Item-by-item disposition

### Verified CONSOLIDATE records deferred by ownership

- **dedup-001 — DEFERRED.** The shared `Severity` display mapping spans
  `Sources/StatusCore/Severity.swift`,
  `Sources/greendot/MenuBuilder.swift`, and
  `Sources/StatusCore/ToastPolicy.swift`. It collides exactly with
  **types-004**, whose type-consolidation owner controls this complete set.
  Keep ToastPolicy's unreachable override and Statuspal's scheduled-maintenance
  exception at their existing boundaries. The serial catch-up pass should mark
  this **RESOLVED-UPSTREAM** only if types-004 completes the shared mapping.
- **dedup-002 — DEFERRED.** The benchmark page fixture and delay constant span
  `Tests/StatusCoreTests/PollPerformanceTests.swift` and
  `Tests/greendotTests/PerformanceHarnessTests.swift`. It collides exactly with
  **types-002**, whose import migration owns both test targets. No
  `TestSupport` fixture move is made in this pass.
- **dedup-003 — DEFERRED.** The duplicate `Duration.milliseconds` extension is
  in the same two benchmark files as dedup-002 and therefore collides exactly
  with **types-002**. The shared timing extension remains for the serial
  catch-up pass after type consolidation.
- **dedup-005 — DEFERRED.** The duplicate typed recursive view searches are in
  `Tests/greendotTests/StatusPageEditorTests.swift`. This file is part of the
  **types-002** import-migration ownership set, so the generic finder move is
  deferred even though it is test-local.
- **dedup-008 — DEFERRED.** The persistence-break helper is duplicated by
  `Tests/greendotTests/AppDelegateRefreshErrorTests.swift` and
  `Tests/greendotTests/StatusPageEditorTests.swift`. The latter file collides
  with **types-002**; that collision owns the complete helper move, even though
  the AppDelegate test file is otherwise free. Do not move only one copy.

### Unverified or KEEP SEPARATE records skipped

- **dedup-004 — SKIPPED.** `verified:false`; the proposed component-toggle
  plan was not eligible for this pass.
- **dedup-006 — SKIPPED.** `verified:false`; common Statuspage fixtures were
  not eligible for this pass.
- **dedup-007 — SKIPPED.** `verified:false` and `KEEP SEPARATE`; the two
  error-to-Boolean wrappers have different owners and UI policies.
- **dedup-009 — SKIPPED.** `verified:false` and `KEEP SEPARATE`; provider
  parser schemas and discriminators remain intentionally distinct.
- **dedup-010 — SKIPPED.** `verified:false` and `KEEP SEPARATE`; the tree walks
  have different contracts and outputs.
- **dedup-011 — SKIPPED.** `verified:false`; the small snapshot fixture was
  not eligible for this pass.

## Files changed

Only the two allowlisted documentation files were created. No source, test,
dependency, configuration, or generated file was changed. The deferred work
and the collision ownership matrix are recorded in
`cleanup-reports/deduplication-deferred.md`.
