# Legacy Code Apply Log

## Scope

- Assessment: `cleanup-reports/legacy-code-assessment.md`
- Branch: `cleanup/apply-20260826-legacy`
- Date: 2026-08-26
- Source changes: none

The machine-readable assessment contains five findings and zero safe or
auto-applicable removals. This pass applied **0/5** findings and skipped
**5/5** findings. No source or test files were changed.

## Baseline verification

These commands were run before this documentation-only change:

```text
$ swift build
Build complete! (20.78s)
Exit: 0

$ swift test
Test Suite 'All tests' passed at 2026-08-26 05:31:20.341.
    Executed 150 tests, with 1 test skipped and 0 failures (0 unexpected) in 3.018 (3.031) seconds
Exit: 0

Swift Testing summary:
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

The skipped test was `PerformanceHarnessTests.testEmitBenchTimings`; it is
the benchmark gate and requires `GREENDOT_BENCH` (the test output says to run
the harness with `make bench`).

## Findings

### legacy-001 - AppKit panel keep-alive workaround — SKIPPED

The assessment records `UNCERTAIN` confidence and `REVIEW` recommendation.
The retained previous editor and next-run-loop handoff protect an active
AppKit lifecycle path. History records the crash reason, but the exact
`AppDelegate.openEditor` path does not have direct coverage. Removal is not
safe without a deliberate lifecycle replacement and macOS-version test
matrix.

### legacy-002 - WatchedPage decoder defaults — SKIPPED

The assessment records verified `KEEP`. The decoder defaults preserve older
persisted configuration fields. Removing these defaults could reject an old
`config.json` or lose intended values. Keep until an explicit migration and
backup/rollback plan proves that older files cannot exist.

### legacy-003 - ComponentStatus decoder defaults — SKIPPED

The assessment records verified `KEEP`. The custom decoder preserves
pre-nesting snapshots that omit fields added later. Removing it could make a
previously saved page unloadable. Keep until a populated pre-change fixture
and explicit migration are available.

### legacy-004 - AppConfig version guard — SKIPPED

The assessment records verified `KEEP`. The version field and forward-version
rejection are an active persisted-format boundary. Do not remove or weaken
them without an explicit migration for a future format.

### legacy-005 - Statuspal `.eu` support — SKIPPED

The assessment records unverified `REVIEW`. The alternate-domain host and API
fallback are current code, but provider and user support has not been
confirmed. Do not remove the `.eu` path until support is checked and affected
saved pages have a controlled migration or error path.

## Result

Applied: **0/5**

Skipped: **5/5**

Deferred ownership items: **none**. No `legacy-code-deferred.md` file was
created.
