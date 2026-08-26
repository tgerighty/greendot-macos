# Defensive programming apply log

Branch: `cleanup/apply-20260826-defensive-catchup`

Original phase base commit: `b7769c7` (`main`, before rebase).

Serial catch-up base commit: `ed38cde` (merged branch before defensive-015).

Assessment: `cleanup-reports/defensive-programming-assessment.md` at report commit `310032b`.

Historical phase commits, corrected to their final merged IDs: apply log `255a529`, lint
correction `d541fbd`, and heading correction `3401911`.

## Scope and baseline

The allowlist was enforced. Source and test changes were limited to:

- `Sources/StatusCore/Models.swift`
- `Sources/StatusCore/ProviderProbe.swift`
- `Sources/greendot/AppDelegate.swift`
- `Tests/StatusCoreTests/ComponentToggleTests.swift`
- `Tests/StatusCoreTests/ProbeAndMonitorTests.swift`
- `Tests/greendotTests/PanelLifecycleTests.swift`
- `Tests/greendotTests/AppDelegateRefreshErrorTests.swift`
- this apply log
- `cleanup-reports/defensive-programming-deferred.md`

The untouched baseline was clean. Fresh baseline `swift build` passed. Fresh baseline `swift test` passed: 150 tests, 1 intentional skip, 0 failures.

Each applied item has a separate RED test commit and GREEN implementation commit. RED commits intentionally record the defect or missing test seam before the implementation. No typing-006 or other `MainActor` change was made.

## Applied items

### defensive-001 — applied

Finding: `WatchedPage.displaySeverity` hid missing and empty status as green.

RED commit: `f43cdd2` (`[TEST] cover missing and empty page severity`).

RED changes and evidence:

- Added `testMissingSnapshotIsGrey`.
- Added `testEmptyComponentsUsePageOverall` for red and yellow page-level status.
- Added `testAllDisabledComponentsRemainGreenWhenPageOverallIsRed` to retain the user-selected all-disabled result.
- Added `testPageOverallWithNoComponentsStillDeliversToast` to cover the hidden-outage toast path.
- `swift test --filter ComponentToggleTests/testMissingSnapshotIsGrey --filter ComponentToggleTests/testEmptyComponentsUsePageOverall --filter ComponentToggleTests/testAllDisabledComponentsRemainGreenWhenPageOverallIsRed` failed with 3 assertions: missing snapshot was `green` instead of `grey`; empty red and yellow pages were `green` instead of their page overall. The all-disabled characterization passed.
- `swift test --filter AppDelegateRefreshErrorTests/testPageOverallWithNoComponentsStillDeliversToast` failed with two assertions: display was `green` instead of `red`, and no toast was delivered.

GREEN commit: `5c28959` (`[FIX] preserve page severity when components are absent`).

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

RED commit: `2637421` (`[TEST] cover non-fatal seed diagnostics`).

RED changes and evidence:

- Added a failure-path test using a deterministic unsupported-provider response.
- Added a cancellation-path test using a client that throws `CancellationError`.
- The targeted compile failed because `AppDelegate` had no `seedFailureDiagnostic`, `maybeSeedOpenAI` was private, and the testable skip override did not exist. This is the missing observable seam in the old `try?` path.

GREEN commit: `d3d4580` (`[FIX] report optional OpenAI seed failures`).

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

RED commit: `c408a6c` (`[TEST] cover poll interval validation`).

RED changes and evidence:

- Added invalid-value tests for missing, empty, malformed, zero, negative, NaN, positive infinity, and negative infinity.
- Added valid finite positive tests.
- `swift test --filter PanelLifecycleTests/testPollIntervalUsesDefaultForInvalidValues` failed to compile because `AppDelegate.pollInterval` did not exist.

GREEN commit: `0f3c31c` (`[FIX] validate configured poll interval`).

Implementation: `pollInterval(from:)` accepts a parsed value only when it is finite and greater than zero. All other values return 60 seconds. The repeating timer now uses this helper.

GREEN evidence:

- `swift test --filter PanelLifecycleTests/testPollIntervalUsesDefaultForInvalidValues --filter PanelLifecycleTests/testPollIntervalAcceptsFinitePositiveValues`: 2 passed.
- `swift build`: passed.
- Full `swift test`: 158 passed, 1 skipped, 0 failures.

Files and LOC:

- RED: `Tests/greendotTests/PanelLifecycleTests.swift` +23/-0.
- GREEN: `Sources/greendot/AppDelegate.swift` +11/-3.

### defensive-015 — applied (serial catch-up)

Finding: HTTP 429, 5xx, and status 0 responses were treated as provider misses, and a
reachability failure could lose to a later HTTP miss.

RED commit: `9bb3bd08f5d07f941c25716e0cc08cd05ae9ae0e`
(`[TEST] RED classify HTTP reachability failures`).

RED changes and evidence:

- Added `testProbeTreatsHTTP429AsUnreachable`,
  `testProbeTreatsRepresentative5xxAsUnreachable`,
  `testProbeTreatsMissingHTTPStatusAsUnreachable`,
  `testProbeKeepsHTTP404AsUnsupported`, and
  `testProbeTreatsStatuspalDiscoveryServerErrorAsUnreachable`.
- `swift test --filter ProbeAndMonitorTests/testProbeTreatsHTTP429AsUnreachable
  --filter ProbeAndMonitorTests/testProbeTreatsRepresentative5xxAsUnreachable
  --filter ProbeAndMonitorTests/testProbeTreatsMissingHTTPStatusAsUnreachable
  --filter ProbeAndMonitorTests/testProbeKeepsHTTP404AsUnsupported
  --filter ProbeAndMonitorTests/testProbeTreatsStatuspalDiscoveryServerErrorAsUnreachable`
  executed 5 tests: 4 failed because the implementation returned `.unsupported` for
  429, 503, status 0, and the Statuspal discovery 503; the 404 control passed.

GREEN commit: `4ffc3649b745c5d1fb91a874bdd236b1696ea61e`
(`[GREEN] classify HTTP reachability failures`).

Implementation: `ProviderProbe` now classifies status 0, 429, and 500...599 as
`.networkError` for standard provider requests and Statuspal discovery. Any recorded
reachability failure wins in the final error; 404 and other provider-mismatch responses
remain misses. Provider order, fallback parsing, cancellation, known-provider polling,
and the LOC decomposition remain unchanged. The unused `sawHTTP` flag was removed.

GREEN evidence:

- `swift test --filter ProbeAndMonitorTests --filter PollPerformanceTests`: 33 passed.
- `swift build`: passed.
- Full `swift test`: 163 passed, 1 intentional skip, 0 failures.
- `swiftlint lint --reporter json`: exit 0; 8 warning violations in 64 files and
  0 serious violations.
- `git diff --check`: passed with no output.

Files and LOC:

- RED: `Tests/StatusCoreTests/ProbeAndMonitorTests.swift` +49/-0.
- GREEN: `Sources/StatusCore/ProviderProbe.swift` +15/-8.

## Deferred or unchanged records

The following table gives a disposition for every record in the assessment. Unverified findings and `KEEP`/`REVIEW` records were not changed.

| ID | Disposition | Reason |
|---|---|---|
| defensive-001 | APPLIED | Verified and requested. RED `f43cdd2`; GREEN `5c28959`. |
| defensive-002 | SKIPPED | Unverified (`verified: false`); parser boundary left unchanged. |
| defensive-003 | SKIPPED | Unverified; `PageStore.swift` is outside this branch allowlist. |
| defensive-004 | SKIPPED | Unverified; `Monitor.swift` is outside this branch allowlist. |
| defensive-005 | SKIPPED | Unverified and recommendation `REVIEW`; stale context policy needs a product decision. |
| defensive-006 | APPLIED | Verified and requested. RED `2637421`; GREEN `d3d4580`. |
| defensive-007 | SKIPPED | Unverified; launch-at-login transaction was not changed. |
| defensive-008 | SKIPPED | Unverified; panel callback policy was not changed. |
| defensive-009 | SKIPPED | Unverified; notification delivery boundary was not changed. |
| defensive-010 | APPLIED | Verified and requested. RED `c408a6c`; GREEN `0f3c31c`. |
| defensive-011 | SKIPPED | Unverified; URL and HTTP boundary was not changed. |
| defensive-012 | SKIPPED | Unverified; launch-at-login UI feedback was not changed. |
| defensive-013 | SKIPPED | Unverified and recommendation `REVIEW`; parser diagnostic policy needs review. |
| defensive-014 | SKIPPED | Verified but recommendation is `REVIEW`, not an approved automatic change. `ProviderProbe.swift` was left unchanged. |
| defensive-015 | APPLIED | Serial catch-up completed. RED `9bb3bd0`; GREEN `4ffc364`. |
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

## Pre-catch-up merged baseline

- Final `swift build`: passed.
- Final full `swift test`: 158 passed, 1 intentional skip, 0 failures.
- Final `swiftlint lint --reporter json`: exit 0; 8 warning violations in 64 files and 0 serious violations. This was the merged baseline before the serial catch-up. No lint fix was in scope.
- Final `git diff --check`: passed with no output.
- The merged baseline was clean before the serial catch-up.

## Pre-merge lint correction (`d541fbd`)

The first pre-merge lint comparison found two new `type_body_length` warnings caused only by the added tests. The tests were moved into focused same-file extensions in `ComponentToggleTests.swift` and `PanelLifecycleTests.swift`. This changed no production behavior and kept the test names and coverage unchanged.

Correction evidence:

- Focused defensive tests: passed.
- `swift build`: passed.
- Full `swift test`: 158 passed, 1 skipped, 0 failures.
- `swiftlint lint --reporter json`: 11 warnings, 0 serious findings; no new findings versus the pre-merge phase baseline.
- `git diff --check`: passed.

No merge, push, or pull request was performed.
