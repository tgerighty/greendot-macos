# Type Consolidation Apply Log

## Scope

- Assessment: `cleanup-reports/type-consolidation-assessment.md`.
- Base: `7347b96` (`main`), worktree branch `cleanup/apply-20260826-type-consolidation`.
- Applied records: 6 (`types-001`, `types-002`, `types-004`, `types-005`, `types-006`, `types-007`).
- Skipped records: 3 (`types-003`, `types-008`, `types-009`).
- RED baseline commit: `b5ea6db` (`[TEST] Confirm type consolidation baseline`).
- No characterization tests were needed: existing tests cover every affected call site.

## RED baseline

The untouched branch passed both required checks:

- `swift build`: passed.
- `swift test`: 150 tests, 1 skipped, 0 failures.

Existing coverage map:

| Record | Existing coverage |
|---|---|
| `types-001` | `ParserTests` covers Statuspage, Instatus, and Statuspal parsing and provider rejection; `ProbeAndMonitorTests.testProbeUnknownFormat` covers probe handling of parser misses. |
| `types-002` | `ProbeAndMonitorTests` covers map-client URL/path lookup and monitor probes; `PollPerformanceTests` covers delayed and recording clients in poll paths; `PerformanceHarnessTests` covers all three doubles in the benchmark path. Additional map-client call sites are covered by `ComponentToggleTests`, `MonitorFirstRunTests`, `MonitorRefreshTransactionTests`, `MenuBuilderTests`, `PanelLifecycleTests`, `StatusPageEditorTests`, and `AppDelegateRefreshErrorTests`. |
| `types-004` | `ToastPolicyTests.testToastWhenOverallColourChanges` and `testToastOnRecoveryToGreen` assert toast labels; `PollPerformanceTests` and `ProbeAndMonitorTests` assert degraded, outage, and unreachable bodies; `MenuBuilderTests.testMenuFromPolledPagesKeepsTitlesActionsAndSeverities` and `testPerformPathOpensNestedEditAndLeaf` assert menu labels. |
| `types-005` | `ProbeAndMonitorTests` covers Statuspage, Instatus, Statuspal, fallback, cancellation, and unreachable probe outcomes; `PollPerformanceTests` covers body reuse and provider repoll paths. |
| `types-006` | All scheduler-injection paths are exercised by `StatusMenuControllerTests`, including deferred reload, deferred pop, tracking restart, and next-run-loop scheduling. |
| `types-007` | `StatusMenuControllerTests` exercises construction and all controller actions; `PanelLifecycleTests` exercises repeated status-menu/panel lifecycle interactions. |

## GREEN results

Each group was committed separately and passed `swift build` followed by full `swift test` before commit. Every GREEN test run reported 150 tests, 1 skipped, and 0 failures.

| Record(s) | Result | GREEN commit | Files and change size |
|---|---|---|---|
| `types-001` | Applied | `f81e062` | Added `Sources/StatusCore/ParserError.swift`; removed the unchanged enum and `LocalizedError` conformance from `Sources/StatusCore/StatuspageParser.swift`; 13 added, 12 removed LOC. |
| `types-002` | Applied | `e1a8e7f` | Moved `MapHTTPClient`, `DelayHTTPClient`, `RecordingHTTPClient`, and `RecordedURLs` to `Tests/TestSupport/HTTPClientDoubles.swift`; retained production HTTP clients; added `TestSupport` imports at actual call sites; 10 files, 74 added, 64 removed LOC. |
| `types-004` / `dedup-001` overlap | Applied | `1fedc1a` | Added `Severity.displayName`; used it from `ToastPolicy` and `MenuBuilder`; removed the duplicate menu switch; retained the unreachable guard and provider-specific mappings; 11 added, 16 removed LOC across 3 files. |
| `types-005` | Applied | `516c2d2` | Changed private `AttemptResult.hit` to carry `ProbeHit` and removed re-wrapping; 7 added, 7 removed LOC in `Sources/StatusCore/ProviderProbe.swift`. |
| `types-006` and `types-007` | Applied | `cd80e39` | Removed the test scheduler alias; used the production internal alias; removed only `StatusMenuController: NSObject` and `super.init()`; 1 added, 4 removed LOC across 2 files. |

## Skips

- `types-003`: skipped. The assessment marks it `REVIEW` and `verified: false`; it requires a backward-compatible page-condition design, not a safe type move.
- `types-008`: skipped. The assessment marks it `REVIEW` and `verified: false`; empty provider groups make the apparent overlap a design decision.
- `types-009`: skipped. The assessment marks it `REVIEW` and `verified: false`; configured page identity and provider identity must remain separate pending a naming/Codable decision.

No ownership item remained, so `cleanup-reports/type-consolidation-deferred.md` was not created.

## Final evidence

- Applied: 6/6 selected verified records.
- Skipped: 3/9 assessed records.
- Net diff from RED baseline: 18 unique files, 106 added, 103 removed LOC.
  `git diff --name-only b5ea6db..cd80e39` confirms the count. The five GREEN
  commit sets contain 2, 10, 3, 1, and 2 files, with no overlap.
- Final `swift build`: passed after `cd80e39`.
- Final `swift test`: 150 tests, 1 skipped, 0 failures after `cd80e39`.
