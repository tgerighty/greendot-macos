# Deduplication Assessment

## Executive Summary

- Scope: `Sources/StatusCore`, `Sources/greendot`, `Tests`, and `UITests/GreenDotUITests/GreenDotUITests.swift`. The generated `UITests/GreenDotUITests.xcodeproj`, `.build`, `greendot.app`, `.git`, and all `cleanup-reports/archive-*` content were excluded.
- Research: `cloc`, `rg`, manual Swift reading, a temporary normalized Swift line-block scan, `git log`, and `git blame`. `jscpd` is not installed, so no third-party clone percentage is reported.
- Total findings: **11** — **HIGH 3**, **MEDIUM 4**, **LOW 4**.
- Recommendation counts: **8 CONSOLIDATE**, **3 KEEP SEPARATE**.
- At least three exact copy blocks are actionable: the severity text switch, the benchmark page fixture, and the benchmark `Duration.milliseconds` extension. The remaining findings are smaller test helpers or deliberately provider/UI-specific code.

Top priorities:

1. Add one shared `Severity` display-text mapping for `ToastPolicy` and `MenuBuilder`; keep the Statuspal scheduled-maintenance exception at the provider boundary.
2. Move the identical benchmark page fixture (and its duplicated delay constant) into `Tests/TestSupport`, which is already a dependency of both test targets.
3. Move the identical benchmark `Duration.milliseconds` extension into `Tests/TestSupport` with the shared benchmark support.

The exact benchmark helper copies were introduced together in commit `e56941e`, so they are likely an accidental duplication rather than independent test intent. Commit `9afaaeb` already centralized the component-tree walk; the component-toggle finding below is the smaller remaining duplication after that refactor. Commit `276f0cb` already shared the controllable HTTP test client and should not be re-created.

## Critical Findings

### dedup-001 — Severity display text is copied in production code

- Severity: HIGH
- Confidence: CERTAIN
- Recommendation: CONSOLIDATE
- Evidence: `Sources/greendot/MenuBuilder.swift:185-191` implements the four `Severity` cases as `Operational`, `Degraded`, `Major outage`, and `Unreachable`. `Sources/StatusCore/ToastPolicy.swift:37-44` repeats the same four-case switch. `Sources/StatusCore/StatuspalParser.swift:45-50` repeats the same mapping with one provider-specific `scheduled` override for yellow.
- Why this is actionable: the two complete switches are exact copies in production paths. A future change to user-facing wording can update one path and leave menus or toasts inconsistent.
- Proposed extraction: add a small `public var displayText: String` (or `statusText`) on `Severity` in `Sources/StatusCore/Severity.swift`. Use it from `MenuBuilder.overallText` and `ToastPolicy.body`; in `StatuspalParser.node`, use the shared value and retain `type == "scheduled" ? "Maintenance" : severity.displayText` for the provider-specific exception. Do not put provider-specific maintenance logic in the shared enum.

### dedup-002 — Benchmark page fixture is an exact cross-target copy

- Severity: HIGH
- Confidence: CERTAIN
- Recommendation: CONSOLIDATE
- Evidence: `Tests/StatusCoreTests/PollPerformanceTests.swift:228-243` and `Tests/greendotTests/PerformanceHarnessTests.swift:333-348` contain the same `page(host:name:provider:)` implementation, including the same `WatchedPage`, `PageSnapshot`, API component, empty incidents, and green state. `Tests/StatusCoreTests/PollPerformanceTests.swift:5` and `Tests/greendotTests/PerformanceHarnessTests.swift:10` also duplicate `delayNs = 80_000_000`.
- Why this is actionable: this is exact copy-paste across two test targets and was introduced by the same commit (`e56941e`). A fixture field change can make the two benchmark suites measure different page shapes without an intentional test change.
- Proposed extraction: add `Tests/TestSupport/BenchmarkFixtures.swift` with `public static let delayNanoseconds: UInt64 = 80_000_000` and `public static func greenPage(host: String, name: String, provider: StatusProvider) -> WatchedPage`. Import `TestSupport` from both tests. Keep benchmark-specific nested pages local because their component trees intentionally differ.

### dedup-003 — Benchmark `Duration.milliseconds` is an exact copy

- Severity: HIGH
- Confidence: CERTAIN
- Recommendation: CONSOLIDATE
- Evidence: `Tests/StatusCoreTests/PollPerformanceTests.swift:282-287` and `Tests/greendotTests/PerformanceHarnessTests.swift:392-397` define the same private `Duration` extension and the same seconds/attoseconds conversion.
- Why this is actionable: both benchmark targets depend on the same conversion and currently carry identical maintenance code. The conversion is easy to correct in one target and accidentally leave stale in the other.
- Proposed extraction: place a public `Duration.milliseconds` extension in `Tests/TestSupport/BenchmarkFixtures.swift` (or a small adjacent timing file), then remove both private copies. Keep the conversion implementation in one place and add one focused test if the shared support target requires it.

## Medium Findings

### dedup-004 — Component-toggle planning is duplicated between core and AppKit

- Severity: MEDIUM
- Confidence: LIKELY
- Recommendation: CONSOLIDATE
- Evidence: `Sources/StatusCore/Monitor.swift:111-122` finds a component by id/name, collects the matched subtree, derives id/name keys, computes whether all nodes are enabled, and applies the toggle. `Sources/greendot/ComponentPicker.swift:110-124` repeats the same find/collect/empty-key/all-enabled decision before updating its local checkbox state.
- Why this is near duplication: commit `9afaaeb` correctly extracted `ComponentTree.find`, `collect`, and `componentKeys`, but the state decision and key derivation still have two implementations. The UI callback must remain authoritative because persistence can fail; a blind move of the whole toggle operation into AppKit or core would change that behavior.
- Proposed extraction: add a small core value such as `ComponentTogglePlan(keys: [String], currentlyEnabled: Bool)` and `ComponentTree.togglePlan(key:in:disabled:)`. `Monitor` applies the plan to the persisted `Set`; `ComponentPicker` applies the same plan only after `onToggleComponent` succeeds. Keep `setAllComponents` and checkbox presentation separate.

### dedup-005 — Two typed recursive view searches differ only by the control type

- Severity: MEDIUM
- Confidence: CERTAIN
- Recommendation: CONSOLIDATE
- Evidence: `Tests/greendotTests/StatusPageEditorTests.swift:250-259` (`field`) and `:261-269` (`button`) have the same nil guard, type cast, accessibility-id check, child recursion, and nil return. Only `NSTextField`/`NSButton` and the local variable type differ.
- Why this is actionable: the duplicate recursion is within one test file and can be replaced without coupling it to production UI code.
- Proposed extraction: use a private generic helper in the same test file, for example `findView<T: NSView>(_ type: T.Type, identifier: String, in view: NSView?) -> T?`, and make `field`/`button` one-line typed wrappers if their call sites read better. Do not reuse `UITestDriver.find` directly: that production helper searches application windows and `NSScrollView.documentView`, which is a different traversal contract.

### dedup-006 — The same green/red Statuspage JSON fixtures are repeated across test targets

- Severity: MEDIUM
- Confidence: LIKELY
- Recommendation: CONSOLIDATE
- Evidence: the green fixture is identical at `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:5-12`, `Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift:6-13`, `Tests/greendotTests/AppDelegateRefreshErrorTests.swift:8-15`, and `Tests/greendotTests/StatusPageEditorTests.swift:8-15`. The red fixture is identical at `Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift:24-31` and `Tests/greendotTests/AppDelegateRefreshErrorTests.swift:17-24`.
- Why this is near duplication: these are intentionally common provider payloads, but each copy can drift in fields that seed the same monitor behavior. The tests already depend on `TestSupport` in the two refresh suites, and the package exposes that target to both `StatusCoreTests` and `greendotTests`.
- Proposed extraction: add `Tests/TestSupport/StatusPageFixtures.swift` with named `Data` constants such as `greenGitHubSummary` and `redGitHubSummary`, or a narrowly parameterized `statuspageSummary(indicator:componentStatus:)`. Keep yellow, edited-page, grouped, and UI-only payloads local because their differences are part of the scenario.

### dedup-007 — Synchronous error-to-Boolean wrappers are similar but have different owners

- Severity: MEDIUM
- Confidence: LIKELY
- Recommendation: KEEP SEPARATE
- Evidence: `Sources/greendot/AppDelegate.swift:101-112` (`performStoreChange`) and `Sources/greendot/StatusPageEditor.swift:110-119` (`performChange`) both run a throwing closure, invoke a success callback, return `true`, and present an error/return `false` on failure.
- Why consolidation is not currently justified: `AppDelegate` rebuilds the status menu and is explicitly `@MainActor`; `StatusPageEditor` reports `onChange` and owns panel error presentation. A generic free function would need success and error closures and would be no simpler than these two short, readable methods. Revisit only if a third operation owner appears or the error policy becomes shared.

## Low / Debatable Findings

### dedup-008 — Test persistence-break helper is copied exactly

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: CONSOLIDATE
- Evidence: `Tests/greendotTests/AppDelegateRefreshErrorTests.swift:163-166` and `Tests/greendotTests/StatusPageEditorTests.swift:285-288` both remove a config path and recreate it as a directory to force save failure.
- Proposed extraction: add `public func breakPersistence(at:) throws` to `Tests/TestSupport` and import it in `StatusPageEditorTests`. This is low priority because the helper is only four lines and the test names make the failure simulation clear.

### dedup-009 — Provider parsers share a shape, not a safe abstraction

- Severity: LOW
- Confidence: LIKELY
- Recommendation: KEEP SEPARATE
- Evidence: page name/URL fallback appears at `Sources/StatusCore/StatuspageParser.swift:22-24`, `Sources/StatusCore/InstatusParser.swift:13-14`, and `Sources/StatusCore/StatuspalParser.swift:9-12`; incident mapping appears at `StatuspageParser.swift:27-31`, `InstatusParser.swift:15-19`, and `StatuspalParser.swift:15-18`; all three assemble `PageSnapshot` separately (`StatuspageParser.swift:33-41`, `InstatusParser.swift:34-42`, `StatuspalParser.swift:20-28`).
- Why to keep separate: the providers use different discriminator fields, incident title/url keys, status casing, and component schemas. A key-array or closure-heavy parser helper would hide those differences and make provider support harder to audit. The repeated `PageSnapshot` initializer is normal domain assembly, not harmful copy-paste.

### dedup-010 — Component/menu/view tree walks are coincidentally similar

- Severity: LOW
- Confidence: LIKELY
- Recommendation: KEEP SEPARATE
- Evidence: component recursion is used for checkbox rendering in `Sources/greendot/ComponentPicker.swift:75-95`, menu rendering in `Sources/greendot/MenuBuilder.swift:162-182`, test checkbox collection in `Tests/greendotTests/PanelLifecycleTests.swift:222-234`, and identifier lookup in `Sources/greendot/UITestDriver.swift:42-59` and `Tests/greendotTests/StatusPageEditorTests.swift:250-269`.
- Why to keep separate: these walks have different outputs and contracts: AppKit controls versus menu items versus a filtered test result; `UITestDriver` additionally traverses scroll-view document views. A generic visitor would add indirection and would not remove the domain-specific branches. `ComponentPicker.count` at `Sources/greendot/ComponentPicker.swift:24-26` is also a small count-only recursion next to `ComponentTree.collect`; adding a public count API is not worth the extra surface unless this is reused.

### dedup-011 — Small snapshot fixtures repeat a common constructor

- Severity: LOW
- Confidence: LIKELY
- Recommendation: CONSOLIDATE
- Evidence: `Tests/StatusCoreTests/AggregatorTests.swift:93-103` and `Tests/StatusCoreTests/ToastPolicyTests.swift:65-75` each define `snap(_ severity:) -> PageSnapshot` with the same fields and only different fixture name/URL values.
- Proposed extraction: if test fixture centralization is accepted for dedup-006, add a parameterized `TestSupport.snapshot(name:url:severity:) -> PageSnapshot` and use it in both suites. Otherwise keep these local; the six call sites are readable and the duplication is test-only.

## Recommendations

1. Consolidate dedup-001 first. A shared `Severity` display property removes a production drift point while preserving Statuspal's maintenance exception.
2. Add one `Tests/TestSupport/BenchmarkFixtures.swift` for dedup-002 and dedup-003. This is the highest-value test-only change because it removes exact copies across target boundaries and uses the existing support target.
3. Add a narrow `ComponentTogglePlan` only after tests cover both persistence failure and optimistic picker updates (dedup-004). Do not move persistence or UI callbacks into the shared helper.
4. Consolidate the generic view search and persistence-break helper (dedup-005 and dedup-008) when touching those tests.
5. Consolidate common green/red payloads and snapshot fixtures only if the team wants centralized test data (dedup-006 and dedup-011). Keep scenario-specific yellow, edited, grouped, and UI fixtures local.
6. Leave dedup-007, dedup-009, and dedup-010 separate. Their apparent similarity does not currently reduce complexity when abstracted.

## Out of Scope / Flagged for Review

- `jscpd` is unavailable in the environment. The report uses `cloc`, `rg`, manual comparison, and a temporary normalized line-block scan; no clone-percentage claim is made.
- Existing `cleanup-reports/archive-*` assessments were not used, as required. Generated UI project files and build artifacts were not inspected.
- This is a read-only analysis. No source, test, dependency, configuration, git state, or archived report was changed; only this assessment was created.
- The HIGH/CERTAIN labels are analysis-stage confidence labels. All machine-readable entries remain `verified: false` and require the independent verification gate before any automated remediation.
- Recent history shows deliberate prior consolidation: `9afaaeb` moved component-tree walking into `ComponentTree`, and `276f0cb` moved the shared controllable HTTP client into `TestSupport`. Any follow-up should preserve those boundaries.

## Independent Verification Disposition

The mandatory gate selected 5 of 11 records. Independent verifiers confirmed 5; those records now have `verified: true`. 6 lower-confidence records remain provisional.

Verification evidence: [verification-batch-1.md](verification-batch-1.md), [verification-batch-2.md](verification-batch-2.md).

Final machine-readable severity counts: HIGH 0, MEDIUM 3, LOW 8. The original prose above records the specialist's pre-verification assessment; this disposition and the JSON block below are authoritative after verification.
 
## Machine-Readable Findings

```json
{"findings":[{"id":"dedup-001","file":"Sources/greendot/MenuBuilder.swift","line":185,"severity":"LOW","confidence":"CERTAIN","recommendation":"CONSOLIDATE","detail":"Baseline mapping is duplicated, with ToastPolicy unreachable handling and Statuspal scheduled handling kept separate.","verified":true},{"id":"dedup-002","file":"Tests/StatusCoreTests/PollPerformanceTests.swift","line":228,"severity":"LOW","confidence":"CERTAIN","recommendation":"CONSOLIDATE","detail":"The page fixture and delay constant are duplicated across two test targets.","verified":true},{"id":"dedup-003","file":"Tests/StatusCoreTests/PollPerformanceTests.swift","line":282,"severity":"LOW","confidence":"CERTAIN","recommendation":"CONSOLIDATE","detail":"The milliseconds extension is duplicated once per test target.","verified":true},{"id":"dedup-004","file":"Sources/StatusCore/Monitor.swift","line":111,"severity":"MEDIUM","confidence":"LIKELY","recommendation":"CONSOLIDATE","detail":"Monitor.toggleComponent and ComponentPicker.componentClicked repeat match, subtree collection, key derivation, and all-enabled decisions at ComponentPicker.swift:110-124. Extract a small ComponentTogglePlan while leaving persistence and UI callbacks at their owners.","verified":false},{"id":"dedup-005","file":"Tests/greendotTests/StatusPageEditorTests.swift","line":250,"severity":"LOW","confidence":"CERTAIN","recommendation":"CONSOLIDATE","detail":"Field and button helpers duplicate traversal logic and can share a generic finder.","verified":true},{"id":"dedup-006","file":"Tests/StatusCoreTests/ProbeAndMonitorTests.swift","line":5,"severity":"MEDIUM","confidence":"LIKELY","recommendation":"CONSOLIDATE","detail":"The same green Statuspage JSON is copied in ProbeAndMonitorTests.swift:5-12, MonitorRefreshTransactionTests.swift:6-13, AppDelegateRefreshErrorTests.swift:8-15, and StatusPageEditorTests.swift:8-15; the red fixture is also copied in MonitorRefreshTransactionTests.swift:24-31 and AppDelegateRefreshErrorTests.swift:17-24. Centralize only these common payloads in TestSupport.","verified":false},{"id":"dedup-007","file":"Sources/greendot/AppDelegate.swift","line":101,"severity":"MEDIUM","confidence":"LIKELY","recommendation":"KEEP SEPARATE","detail":"performStoreChange and StatusPageEditor.performChange have a similar do/catch wrapper at StatusPageEditor.swift:110-119, but their success callbacks, owner lifetimes, and UI responsibilities differ. A generic wrapper would not currently reduce complexity.","verified":false},{"id":"dedup-008","file":"Tests/greendotTests/AppDelegateRefreshErrorTests.swift","line":163,"severity":"LOW","confidence":"CERTAIN","recommendation":"CONSOLIDATE","detail":"Exact two-method duplication is confirmed; consolidation is optional test maintenance.","verified":true},{"id":"dedup-009","file":"Sources/StatusCore/StatuspageParser.swift","line":22,"severity":"LOW","confidence":"LIKELY","recommendation":"KEEP SEPARATE","detail":"Statuspage, Instatus, and Statuspal parsers repeat page identity, incidents, and PageSnapshot assembly, but their schemas and discriminators differ at InstatusParser.swift:13-42 and StatuspalParser.swift:9-28. A generic parser helper would obscure provider behavior.","verified":false},{"id":"dedup-010","file":"Sources/greendot/ComponentPicker.swift","line":75,"severity":"LOW","confidence":"LIKELY","recommendation":"KEEP SEPARATE","detail":"ComponentPicker, MenuBuilder, PanelLifecycleTests, UITestDriver, and StatusPageEditorTests each walk AppKit/component trees for different outputs; evidence includes MenuBuilder.swift:162-182, PanelLifecycleTests.swift:222-234, and UITestDriver.swift:42-59. A generic visitor would add complexity; the count recursion at ComponentPicker.swift:24-26 is too small to justify a new API.","verified":false},{"id":"dedup-011","file":"Tests/StatusCoreTests/AggregatorTests.swift","line":93,"severity":"LOW","confidence":"LIKELY","recommendation":"CONSOLIDATE","detail":"The snap(severity:) PageSnapshot fixture is repeated at ToastPolicyTests.swift:65-75 with only name and URL values changed. A parameterized TestSupport snapshot fixture may remove this test-only copy if fixture centralization is accepted.","verified":false}]}
```
