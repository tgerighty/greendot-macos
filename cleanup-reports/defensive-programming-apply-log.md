# Defensive programming apply log

Branch: `cleanup/apply-20260826-defensive`

Base commit: `b7769c7` (`main`)

Assessment: `cleanup-reports/defensive-programming-assessment.md` at report commit `310032b`.

## Scope and baseline

The allowlist was enforced. Source and test changes were limited to:

- `Sources/StatusCore/Models.swift`
- `Sources/greendot/AppDelegate.swift`
- `Tests/StatusCoreTests/ComponentToggleTests.swift`
- `Tests/greendotTests/PanelLifecycleTests.swift`
- `Tests/greendotTests/AppDelegateRefreshErrorTests.swift`
- this apply log
- `cleanup-reports/defensive-programming-deferred.md`

The untouched baseline was clean. Fresh baseline `swift build` passed. Fresh baseline `swift test` passed: 150 tests, 1 intentional skip, 0 failures.

Each applied item has a separate RED test commit and GREEN implementation commit. RED commits intentionally record the defect or missing test seam before the implementation. No typing-006 or other `MainActor` change was made.

## Applied items

### defensive-001 — applied

Finding: `WatchedPage.displaySeverity` hid missing and empty status as green.

RED commit: `0f854cd` (`[TEST] cover missing and empty page severity`).

RED changes and evidence:

- Added `testMissingSnapshotIsGrey`.
- Added `testEmptyComponentsUsePageOverall` for red and yellow page-level status.
- Added `testAllDisabledComponentsRemainGreenWhenPageOverallIsRed` to retain the user-selected all-disabled result.
- Added `testPageOverallWithNoComponentsStillDeliversToast` to cover the hidden-outage toast path.
- `swift test --filter ComponentToggleTests/testMissingSnapshotIsGrey --filter ComponentToggleTests/testEmptyComponentsUsePageOverall --filter ComponentToggleTests/testAllDisabledComponentsRemainGreenWhenPageOverallIsRed` failed with 3 assertions: missing snapshot was `green` instead of `grey`; empty red and yellow pages were `green` instead of their page overall. The all-disabled characterization passed.
- `swift test --filter AppDelegateRefreshErrorTests/testPageOverallWithNoComponentsStillDeliversToast` failed with two assertions: display was `green` instead of `red`, and no toast was delivered.

GREEN commit: `ee8e412` (`[FIX] preserve page severity when components are absent`).

Implementation: `displaySeverity` now returns grey for no snapshot, grey for unreachable snapshots, the snapshot page overall for an empty raw component list, and the enabled-leaf aggregation for non-empty raw components. An all-disabled non-empty component list therefore remains green.

GREEN evidence:

- `swift test --filter ComponentToggleTests`: 18 passed.
- `swift test --filter AppDelegateRefreshErrorTests/testPageOverallWithNoComponentsStillDeliversToast`: passed.
- `swift build`: passed.
- Full `swift test`: 154 passed, 1 skipped, 0 failures.

Files and LOC:

- RED: `Tests/StatusCoreTests/ComponentToggleTests.swift` +40/-1; `Tests/greendotTests/AppDelegateRefreshErrorTests.swift` +30/-0.
- GREEN: `Sources/StatusCore/Models.swift` +3/-1.

### defensive-006 — applied

Finding: optional first-run OpenAI seed errors were discarded.

RED commit: `8e16bf9` (`[TEST] cover non-fatal seed diagnostics`).

RED changes and evidence:

- Added a failure-path test using a deterministic unsupported-provider response.
- Added a cancellation-path test using a client that throws `CancellationError`.
- The targeted compile failed because `AppDelegate` had no `seedFailureDiagnostic`, `maybeSeedOpenAI` was private, and the testable skip override did not exist. This is the missing observable seam in the old `try?` path.

GREEN commit: `baa8138` (`[FIX] report optional OpenAI seed failures`).

Implementation: `AppDelegate` now has an injectable `seedFailureDiagnostic` with a default `NSLog` reporter. The seed method remains optional and non-blocking, returns without reporting cancellation, and reports other seed errors without failing startup. A skip override makes the path deterministic in tests; production still reads `GREENDOT_SKIP_SEED`.

GREEN evidence:

- `swift test --filter PanelLifecycleTests/testSeedFailureIsReportedWithoutFailingStartup --filter PanelLifecycleTests/testSeedCancellationIsNotReported`: 2 passed.
- `swift build`: passed.
- Full `swift test`: 156 passed, 1 skipped, 0 failures.

Files and LOC:

- RED: `Tests/greendotTests/PanelLifecycleTests.swift` +36/-0.
- GREEN: `Sources/greendot/AppDelegate.swift` +12/-3.

### defensive-010 — applied

Finding: zero, negative, non-finite, and malformed poll intervals reached `Timer`.

RED commit: `9394dda` (`[TEST] cover poll interval validation`).

RED changes and evidence:

- Added invalid-value tests for missing, empty, malformed, zero, negative, NaN, positive infinity, and negative infinity.
- Added valid finite positive tests.
- `swift test --filter PanelLifecycleTests/testPollIntervalUsesDefaultForInvalidValues` failed to compile because `AppDelegate.pollInterval` did not exist.

GREEN commit: `9443b5f` (`[FIX] validate configured poll interval`).

Implementation: `pollInterval(from:)` accepts a parsed value only when it is finite and greater than zero. All other values return 60 seconds. The repeating timer now uses this helper.

GREEN evidence:

- `swift test --filter PanelLifecycleTests/testPollIntervalUsesDefaultForInvalidValues --filter PanelLifecycleTests/testPollIntervalAcceptsFinitePositiveValues`: 2 passed.
- `swift build`: passed.
- Full `swift test`: 158 passed, 1 skipped, 0 failures.

Files and LOC:

- RED: `Tests/greendotTests/PanelLifecycleTests.swift` +23/-0.
- GREEN: `Sources/greendot/AppDelegate.swift` +11/-3.

## Deferred or unchanged records

The following table gives a disposition for every record in the assessment. Unverified findings and `KEEP`/`REVIEW` records were not changed.

| ID | Disposition | Reason |
|---|---|---|
| defensive-001 | APPLIED | Verified and requested. RED `0f854cd`; GREEN `ee8e412`. |
| defensive-002 | SKIPPED | Unverified (`verified: false`); parser boundary left unchanged. |
| defensive-003 | SKIPPED | Unverified; `PageStore.swift` is outside this branch allowlist. |
| defensive-004 | SKIPPED | Unverified; `Monitor.swift` is outside this branch allowlist. |
| defensive-005 | SKIPPED | Unverified and recommendation `REVIEW`; stale context policy needs a product decision. |
| defensive-006 | APPLIED | Verified and requested. RED `8e16bf9`; GREEN `baa8138`. |
| defensive-007 | SKIPPED | Unverified; launch-at-login transaction was not changed. |
| defensive-008 | SKIPPED | Unverified; panel callback policy was not changed. |
| defensive-009 | SKIPPED | Unverified; notification delivery boundary was not changed. |
| defensive-010 | APPLIED | Verified and requested. RED `9394dda`; GREEN `9443b5f`. |
| defensive-011 | SKIPPED | Unverified; URL and HTTP boundary was not changed. |
| defensive-012 | SKIPPED | Unverified; launch-at-login UI feedback was not changed. |
| defensive-013 | SKIPPED | Unverified and recommendation `REVIEW`; parser diagnostic policy needs review. |
| defensive-014 | SKIPPED | Verified but recommendation is `REVIEW`, not an approved automatic change. `ProviderProbe.swift` was left unchanged. |
| defensive-015 | DEFERRED | Verified and requested, but `ProviderProbe.swift` is fully owned by the LOC-limits agent in this phase. Exact catch-up action is in `defensive-programming-deferred.md`. |
| defensive-016 | KEEP | Verified legitimate file/JSON boundary; unchanged. |
| defensive-017 | KEEP | Verified legitimate provider fallback and cancellation boundary; unchanged. |
| defensive-018 | KEEP | Verified legitimate UI operation and poll error catches; unchanged. |
| defensive-019 | KEEP | Verified legitimate cancellation and stale-poll transaction guards; unchanged. |
| defensive-020 | KEEP | Verified legitimate optional notification attachment degradation; unchanged. |
| defensive-021 | KEEP | Verified legitimate diagnostic and UI-test best-effort I/O; unchanged. |
| defensive-022 | SKIPPED | Unverified partial/review disposition; parser row filtering was unchanged. |
| defensive-023 | KEEP | Verified legitimate Codable compatibility defaults; unchanged. |
| defensive-024 | KEEP | Verified legitimate fail-closed status mappings; unchanged. |
| defensive-025 | KEEP | Verified proven local force unwrap; unchanged. |
| defensive-026 | KEEP | Verified normal UI and URL fallbacks; unchanged. |
| defensive-027 | KEEP | Verified legitimate fixture file boundary; unchanged. |

## Verification at handoff

- Final `swift build`: passed.
- Final full `swift test`: 158 passed, 1 intentional skip, 0 failures.
- Final `swiftlint lint --format json`: exit 0; 13 warning violations in 61 files and 0 serious violations. The findings are existing size/style issues, including the expected `ProviderProbe` size findings and test type-body size findings. No lint fix was in scope.
- Final `git diff --check`: passed with no output.
- Final worktree: clean after the apply-log commit.

No merge, push, or pull request was performed.
