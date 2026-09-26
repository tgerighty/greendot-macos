ponytail full-intensity: apply the YAGNI ladder; prefer reuse, standard library, and native code; keep diffs small; retain trust-boundary validation, security, and accessibility.

# LOC Limits Assessment

## Executive Summary

This report measures the tracked Swift source and test files at commit `9320756`. The Swift package defines the production and unit-test targets (`Package.swift:4`), and the UI test source is separate (`UITests/GreenDotUITests/GreenDotUITests.swift:7`). I excluded `Package.swift` as configuration. I counted each nonblank line that contains code, including string literals, and excluded comment-only lines. A function count includes its declaration and closing brace. `wc -l` supplied the physical-line baseline. The repository config includes `Sources` and `Tests` for SwiftLint (`.swiftlint.yml:1`), but neither SwiftLint nor `cloc` was available here; the counts below come from a read-only local lexer and manual boundary checks.

- **11 threshold signals:** nine files over 300 code LOC and two methods over 50 counted code LOC. Severity: **HIGH 0, MEDIUM 1, LOW 10**. The nine files hold 2,935 code LOC; eight are tests. The two methods are in test files (`Sources/greendot/AppDelegate.swift:5`, `Tests/greendotTests/StatusPageEditorTests.swift:72`, `Tests/StatusCoreTests/RssRedirectTests.swift:38`).
- **Top priorities:** (1) split the polling and toast concern out of `AppDelegate.swift` when that area next changes (`Sources/greendot/AppDelegate.swift:269`); (2) consider separating the mixed probe/store tests when editing them (`Tests/StatusCoreTests/ProbeAndMonitorTests.swift:69`, `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:219`); (3) consider separating the startup tests from panel tests when editing them (`Tests/greendotTests/PanelLifecycleTests.swift:163`, `Tests/greendotTests/PanelLifecycleTests.swift:267`). Only the first is a production concern.
- **Estimated impact:** one production file of 341 code LOC, eight test files of 2,594 code LOC, and two test methods. A file split relocates code; it does not imply safe LOC deletion. The two 51-line methods have 49 code lines inside their braces (`Tests/greendotTests/StatusPageEditorTests.swift:72`, `Tests/StatusCoreTests/RssRedirectTests.swift:38`).

### All files over 300 code LOC

| File and evidence | Code LOC | Physical LOC | Concern count | Severity | Recommendation |
|---|---:|---:|---:|---|---|
| `Tests/greendotTests/AppDelegateReloadTests.swift:8` | 344 | 400 | 1 reload concern | LOW | EXEMPT |
| `Tests/StatusCoreTests/ComponentToggleTests.swift:5` | 342 | 388 | 1 component concern | LOW | EXEMPT |
| `Sources/greendot/AppDelegate.swift:5` | 341 | 380 | 4 | MEDIUM | SPLIT |
| `Tests/greendotTests/PerformanceHarnessTests.swift:10` | 328 | 351 | 1 benchmark harness | LOW | EXEMPT |
| `Tests/greendotTests/PanelLifecycleTests.swift:8` | 326 | 357 | 3 | LOW | SPLIT when touched |
| `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:5` | 321 | 364 | 3 | LOW | SPLIT when touched |
| `Tests/StatusCoreTests/StateFileSplitTests.swift:4` | 317 | 400 | 1 state persistence concern | LOW | EXEMPT |
| `Tests/greendotTests/StatusPageEditorTests.swift:8` | 312 | 357 | 1 editor concern | LOW | EXEMPT |
| `Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift:5` | 304 | 355 | 1 transaction concern | LOW | EXEMPT |

Concern counts group related behavior; they are review judgments, not a metric. The cited lines show each grouping. A 300-line limit alone does not justify moving a cohesive test suite into more files.

## Critical Findings

None. The sole production file above 300 code LOC is 41 lines over the threshold and has an existing same-type extension pattern (`Sources/greendot/AppDelegate.swift:5`, `Sources/greendot/AppDelegate+Config.swift:13`). I found no production method above 50 counted code LOC; the closest measured method is `probeMicrosoftHub` at 50 (`Sources/StatusCore/ProviderProbe+RSS.swift:158`).

## Medium Findings

### loc-001 — AppDelegate holds several concerns in one file

`Sources/greendot/AppDelegate.swift:5` has 341 code LOC. It initializes the app and timers (`Sources/greendot/AppDelegate.swift:36`), wires menu and editor actions (`Sources/greendot/AppDelegate.swift:137`, `Sources/greendot/AppDelegate.swift:169`), installs UI-test hooks (`Sources/greendot/AppDelegate.swift:207`), and handles reachability, toasts, and poll refresh (`Sources/greendot/AppDelegate.swift:270`, `Sources/greendot/AppDelegate.swift:281`, `Sources/greendot/AppDelegate.swift:350`). These are four practical navigation areas, though one app delegate still coordinates them.

**SPLIT proposal:** keep launch, menu, editor, and UI-test hook code in `Sources/greendot/AppDelegate.swift`; keep existing config handling in `Sources/greendot/AppDelegate+Config.swift:13`; move the reachability, toast, and poll methods from `Sources/greendot/AppDelegate.swift:269` into `Sources/greendot/AppDelegate+Polling.swift`. This uses the existing extension pattern. The stored poll invocation state must stay in the main type (`Sources/greendot/AppDelegate.swift:15`); a cross-file extension needs deliberate access to it. Preserve the stale-poll check and error gate (`Sources/greendot/AppDelegate.swift:353`, `Sources/greendot/AppDelegate.swift:365`). This is a navigation change with concurrency risk, so make it only with nearby polling work and run the reload and refresh tests (`Tests/greendotTests/AppDelegateReloadTests.swift:51`, `Tests/greendotTests/AppDelegateRefreshErrorTests.swift:87`). Do not introduce a new state object solely to satisfy the line cap.

## Low / Debatable Findings

### loc-002 through loc-009 — test-file size

The eight test files in the table exceed 300 code LOC. Six are cohesive suites and should be **EXEMPT**: reload behavior spans three related test classes (`Tests/greendotTests/AppDelegateReloadTests.swift:8`, `Tests/greendotTests/AppDelegateReloadTests.swift:218`, `Tests/greendotTests/AppDelegateReloadTests.swift:352`); component toggling shares local fixtures (`Tests/StatusCoreTests/ComponentToggleTests.swift:5`, `Tests/StatusCoreTests/ComponentToggleTests.swift:204`); benchmark measurements share one gated entry point (`Tests/greendotTests/PerformanceHarnessTests.swift:26`); state-file behavior includes the related launch flag (`Tests/StatusCoreTests/StateFileSplitTests.swift:4`, `Tests/StatusCoreTests/StateFileSplitTests.swift:270`); editor behavior uses a local pending-save gate (`Tests/greendotTests/StatusPageEditorTests.swift:8`, `Tests/greendotTests/StatusPageEditorTests.swift:328`); and transaction tests share race fixtures (`Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift:5`, `Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift:337`). Splitting these now adds files without a demonstrated navigation or behavior gain.

Two test files mix subjects. **SPLIT when touched**, with no immediate change: `PanelLifecycleTests.swift` combines panel behavior, status-dot rendering, and app startup (`Tests/greendotTests/PanelLifecycleTests.swift:9`, `Tests/greendotTests/PanelLifecycleTests.swift:110`, `Tests/greendotTests/PanelLifecycleTests.swift:163`). If a startup test changes, move the startup and seed tests to `Tests/greendotTests/AppDelegateStartupTests.swift`, keeping their fixtures with them (`Tests/greendotTests/PanelLifecycleTests.swift:267`, `Tests/greendotTests/PanelLifecycleTests.swift:328`). `ProbeAndMonitorTests.swift` combines provider, directory-client, and store cases (`Tests/StatusCoreTests/ProbeAndMonitorTests.swift:15`, `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:69`, `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:219`). If store tests change, place the store-load cases in the existing `Tests/StatusCoreTests/PageStoreValidationTests.swift:4` and review the file-local fixtures before moving them (`Tests/StatusCoreTests/ProbeAndMonitorTests.swift:325`).

### All methods over 50 counted code LOC

| File and method | Counted LOC | Physical span | Body-only code LOC | Recommendation |
|---|---:|---:|---:|---|
| `Tests/greendotTests/StatusPageEditorTests.swift:72` `testFailedEditKeepsEditorOpenAndRetainsEnteredValues` | 51 | 72–128 | 49 | EXEMPT: one end-to-end failure case; keep its state and assertions together (`Tests/greendotTests/StatusPageEditorTests.swift:90`, `Tests/greendotTests/StatusPageEditorTests.swift:114`). |
| `Tests/StatusCoreTests/RssRedirectTests.swift:38` `testSameHostRedirectPolicy` | 51 | 38–88 | 49 | EXEMPT: each assertion checks a redirect or feed-URL boundary (`Tests/StatusCoreTests/RssRedirectTests.swift:46`, `Tests/StatusCoreTests/RssRedirectTests.swift:70`). |

These are two-line counting-edge cases: removing the declaration and closing brace puts both bodies below 50. Decomposing either test would add helpers without reducing the test's logical scope. Keep the redirect assertions because they cover trust-boundary policy (`Sources/StatusCore/HTTPClient.swift:16`, `Sources/StatusCore/ProviderProbe+RSS.swift:118`). Keep the icon accessibility assertion if panel tests ever move (`Tests/greendotTests/PanelLifecycleTests.swift:138`).

## Recommendations

1. **SPLIT, MEDIUM, conditional:** use the existing extension layout for polling and toasts during the next relevant production change; preserve poll ordering and error behavior (`Sources/greendot/AppDelegate.swift:269`, `Sources/greendot/AppDelegate.swift:353`, `Sources/greendot/AppDelegate+Config.swift:13`). This is the only production size action supported by a clear concern boundary.
2. **SPLIT, LOW, conditional:** move startup tests away from panel tests, or store-load tests into the existing store suite, only when those tests need maintenance (`Tests/greendotTests/PanelLifecycleTests.swift:163`, `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:219`, `Tests/StatusCoreTests/PageStoreValidationTests.swift:4`). Keep test fixtures near their users.
3. **EXEMPT, LOW:** leave the six cohesive large test suites and both 51-line test methods intact (`Tests/StatusCoreTests/ComponentToggleTests.swift:5`, `Tests/greendotTests/StatusPageEditorTests.swift:72`, `Tests/StatusCoreTests/RssRedirectTests.swift:38`). Their size alone is insufficient reason for a diff.

## Out of Scope / Flagged for Review

- This is a static LOC and concern-boundary review. It does not assert a runtime defect or test pass status. The available build and lint commands depend on Swift tools (`Makefile:10`, `Makefile:19`), which were unavailable in this Linux worktree.
- `UITests/GreenDotUITests/GreenDotUITests.swift:7` is 289 code LOC despite 329 physical lines, so it is below the file threshold. `Sources/StatusCore/ProviderProbe+RSS.swift:3` is 292 code LOC despite 318 physical lines; its largest measured method has 50 counted code LOC (`Sources/StatusCore/ProviderProbe+RSS.swift:158`). Neither is a threshold finding.
- No generated Swift file was identified among the tracked source/test paths. `Package.swift:1` is package configuration and is excluded from the file-size table. No recommendation here removes input validation, redirect checks, accessibility assertions, or other security behavior (`Sources/StatusCore/HTTPClient.swift:16`, `Tests/greendotTests/PanelLifecycleTests.swift:138`).

## Machine-Readable Findings

```json
{"findings":[
  {"id":"loc-001","file":"Sources/greendot/AppDelegate.swift","line":5,"severity":"MEDIUM","confidence":"LIKELY","recommendation":"SPLIT","detail":"Sources/greendot/AppDelegate.swift:5 has 341 code LOC and four concern areas; split polling and toast methods into a same-type extension when touched.","verified":false},
  {"id":"loc-002","file":"Tests/greendotTests/AppDelegateReloadTests.swift","line":8,"severity":"LOW","confidence":"CERTAIN","recommendation":"EXEMPT","detail":"Tests/greendotTests/AppDelegateReloadTests.swift:8 has 344 code LOC of related reload tests.","verified":false},
  {"id":"loc-003","file":"Tests/StatusCoreTests/ComponentToggleTests.swift","line":5,"severity":"LOW","confidence":"CERTAIN","recommendation":"EXEMPT","detail":"Tests/StatusCoreTests/ComponentToggleTests.swift:5 has 342 code LOC of related component tests.","verified":false},
  {"id":"loc-004","file":"Tests/greendotTests/PerformanceHarnessTests.swift","line":10,"severity":"LOW","confidence":"CERTAIN","recommendation":"EXEMPT","detail":"Tests/greendotTests/PerformanceHarnessTests.swift:10 has 328 code LOC in one benchmark harness.","verified":false},
  {"id":"loc-005","file":"Tests/greendotTests/PanelLifecycleTests.swift","line":8,"severity":"LOW","confidence":"LIKELY","recommendation":"SPLIT","detail":"Tests/greendotTests/PanelLifecycleTests.swift:8 has 326 code LOC across panel, icon, and startup tests; split by subject when touched.","verified":false},
  {"id":"loc-006","file":"Tests/StatusCoreTests/ProbeAndMonitorTests.swift","line":5,"severity":"LOW","confidence":"LIKELY","recommendation":"SPLIT","detail":"Tests/StatusCoreTests/ProbeAndMonitorTests.swift:5 has 321 code LOC across probe, directory-client, and store tests; reuse the existing store suite when touched.","verified":false},
  {"id":"loc-007","file":"Tests/StatusCoreTests/StateFileSplitTests.swift","line":4,"severity":"LOW","confidence":"CERTAIN","recommendation":"EXEMPT","detail":"Tests/StatusCoreTests/StateFileSplitTests.swift:4 has 317 code LOC of related state persistence tests.","verified":false},
  {"id":"loc-008","file":"Tests/greendotTests/StatusPageEditorTests.swift","line":8,"severity":"LOW","confidence":"CERTAIN","recommendation":"EXEMPT","detail":"Tests/greendotTests/StatusPageEditorTests.swift:8 has 312 code LOC of related editor tests.","verified":false},
  {"id":"loc-009","file":"Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift","line":5,"severity":"LOW","confidence":"CERTAIN","recommendation":"EXEMPT","detail":"Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift:5 has 304 code LOC of related transaction tests.","verified":false},
  {"id":"loc-010","file":"Tests/greendotTests/StatusPageEditorTests.swift","line":72,"severity":"LOW","confidence":"CERTAIN","recommendation":"EXEMPT","detail":"Tests/greendotTests/StatusPageEditorTests.swift:72 has 51 counted method lines but 49 body-only lines; keep the single failure scenario intact.","verified":false},
  {"id":"loc-011","file":"Tests/StatusCoreTests/RssRedirectTests.swift","line":38,"severity":"LOW","confidence":"CERTAIN","recommendation":"EXEMPT","detail":"Tests/StatusCoreTests/RssRedirectTests.swift:38 has 51 counted method lines but 49 body-only lines; keep redirect policy assertions intact.","verified":false}
]}
```
