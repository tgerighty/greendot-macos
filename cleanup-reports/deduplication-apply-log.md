# Deduplication cleanup apply log

## Scope and result

- Assessment: `cleanup-reports/deduplication-assessment.md`.
- Catch-up branch: `cleanup/apply-20260826-dedup-catchup`.
- Worktree: `/Users/terry.gerighty/coding/greendot.cleanup-apply-20260826-dedup-catchup`.
- Current main before the catch-up: `531c3b1b649ea0aef9204e8b10ff963d712a3d23`.
- Selected records: `dedup-001`, `dedup-002`, `dedup-003`, `dedup-005`, `dedup-008`.
- Code and test files changed: only the files in the allowlist.

Result: **4 APPLIED, 1 RESOLVED-UPSTREAM, 6 SKIPPED**.

The four applied records removed 92 lines and added 78 lines. The net change
is 14 fewer lines. The six skipped records were not changed.

## RED baseline

The branch was clean before the catch-up. The current main already contained
the type-consolidation changes. Existing tests cover the affected benchmark,
editor, and persistence paths, so no new characterization test was needed.

```text
$ git status --short --branch
## cleanup/apply-20260826-dedup-catchup

$ swift build
PASS — Build complete! (22.39s), exit 0

$ swift test
PASS — 150 tests, 1 skipped, 0 failures, exit 0
```

The skipped test was
`PerformanceHarnessTests.testEmitBenchTimings`; it requires `make bench`.

RED commit: `65f43d8829e22566a6abe8d98a95ca331d793a20`
(`[TEST] Confirm deduplication catch-up baseline`).

## Item-by-item disposition

### dedup-001 — RESOLVED-UPSTREAM

Re-verification against current main found the required behavior:

- `Severity.displayName` is used by `ToastPolicy` and `MenuBuilder`.
- `ToastPolicy` checks `snapshot.isUnreachable` first and still returns
  `Unreachable` for that case.
- `StatuspalParser` keeps its provider rule: `scheduled` yellow status text
  is `Maintenance`; other yellow status text is `Degraded`.

The shared mapping was completed by type consolidation in GREEN commit
`1fedc1a0fe471f4893747fb6571d63628e902c59`. No catch-up source change was
needed. Catch-up RED commit: `65f43d8829e22566a6abe8d98a95ca331d793a20`.
Catch-up GREEN commit: **none**. Catch-up file/LOC change: **0/0**.

### dedup-002 and dedup-003 — APPLIED together

`Tests/TestSupport/BenchmarkFixtures.swift` now owns the shared
`BenchmarkFixtures.delayNanoseconds` value (`80_000_000`), the green page
fixture, and the public `Duration.milliseconds` conversion. Both benchmark
test files use the shared definitions. Their duplicate definitions were
removed.

RED commit: `65f43d8829e22566a6abe8d98a95ca331d793a20`.
GREEN commit: `9bcc849ded276f7e78ced261935444b8469abaa8`.

File/LOC changes in the GREEN commit:

- `Tests/TestSupport/BenchmarkFixtures.swift`: +34 / -0.
- `Tests/StatusCoreTests/PollPerformanceTests.swift`: +11 / -35.
- `Tests/greendotTests/PerformanceHarnessTests.swift`: +14 / -37.
- Group total: **+59 / -72**.

Focused and post-change checks:

```text
$ swift test --filter PollPerformanceTests
PASS — 9 tests, 0 failures.

$ swift test --filter PerformanceHarnessTests
PASS — 1 test, 1 skipped, 0 failures.

$ swift build
PASS — Build complete, exit 0.

$ swift test
PASS — 150 tests, 1 skipped, 0 failures.
```

### dedup-005 — APPLIED

`Tests/greendotTests/StatusPageEditorTests.swift` now has one private generic
`NSView` finder. The field and button helpers call it, so the original
depth-first child traversal and accessibility identifiers remain unchanged.

RED commit: `65f43d8829e22566a6abe8d98a95ca331d793a20`.
GREEN commit: `f0e0a7d088b0d10019e8f0861d0efea21bf40227`.
File/LOC change: `StatusPageEditorTests.swift` **+13 / -12**.

Focused and post-change checks:

```text
$ swift test --filter StatusPageEditorTests
PASS — 7 tests, 0 failures.

$ swift build
PASS — Build complete, exit 0.

$ swift test
PASS — 150 tests, 1 skipped, 0 failures.
```

### dedup-008 — APPLIED

`Tests/TestSupport/PersistenceFailure.swift` now provides the shared
`breakPersistence(at:)` helper. Both
`AppDelegateRefreshErrorTests` and `StatusPageEditorTests` use it. The helper
still removes the config path and creates a directory at that path to force a
save failure.

RED commit: `65f43d8829e22566a6abe8d98a95ca331d793a20`.
GREEN commit: `3f07ee0788bc16063855d96467fc283d9548bdc1`.

File/LOC changes in the GREEN commit:

- `Tests/TestSupport/PersistenceFailure.swift`: +6 / -0.
- `Tests/greendotTests/AppDelegateRefreshErrorTests.swift`: +0 / -4.
- `Tests/greendotTests/StatusPageEditorTests.swift`: +0 / -4.
- Group total: **+6 / -8**.

Focused and post-change checks:

```text
$ swift test --filter AppDelegateRefreshErrorTests
PASS — 4 tests, 0 failures.

$ swift test --filter StatusPageEditorTests
PASS — 7 tests, 0 failures.

$ swift build
PASS — Build complete, exit 0.

$ swift test
PASS — 150 tests, 1 skipped, 0 failures.
```

## Skipped records

These records were outside the selected verified catch-up scope. They remain
unchanged:

- `dedup-004` — SKIPPED; `verified:false`.
- `dedup-006` — SKIPPED; `verified:false`.
- `dedup-007` — SKIPPED; `verified:false`, KEEP SEPARATE.
- `dedup-009` — SKIPPED; `verified:false`, KEEP SEPARATE.
- `dedup-010` — SKIPPED; `verified:false`, KEEP SEPARATE.
- `dedup-011` — SKIPPED; `verified:false`.

## Files changed

Code and test files changed by this catch-up:

- `Tests/TestSupport/BenchmarkFixtures.swift` (new).
- `Tests/TestSupport/PersistenceFailure.swift` (new).
- `Tests/StatusCoreTests/PollPerformanceTests.swift`.
- `Tests/greendotTests/PerformanceHarnessTests.swift`.
- `Tests/greendotTests/StatusPageEditorTests.swift`.
- `Tests/greendotTests/AppDelegateRefreshErrorTests.swift`.

The two report files are updated by the final documentation commit. No other
file was changed. No merge, push, or pull request was made.
