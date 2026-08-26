# Type Consolidation Assessment

## Executive Summary

This read-only review covers commit `310032b` and the current Swift source and test tree. It excludes `.git`, `.build`, `greendot.app`, archived cleanup reports, and generated UI-test project files. Definitions and usages were found with `rg`, then traced through the call sites. The inventory contains **101 Swift type definitions**:

- **67 production definitions**: 40 in `Sources/StatusCore` and 27 in `Sources/greendot`.
- **34 test/support definitions**: 33 under `Tests` and 1 under `UITests`.
- The inventory includes nested `CodingKeys`, private helper types, test doubles, and type aliases. It does not count extensions as new types.

There are **9 findings**: **0 HIGH**, **3 MEDIUM**, and **6 LOW**. The code is not currently failing because of these findings. `swift build -Xswiftc -warn-concurrency` passed, and `swift test` passed with 150 tests, 1 skipped, and 0 failures. `swiftlint lint --strict` reported 11 existing violations, but none changes the finding count below.

Top priorities:

1. **TYPE-002**: move the three test-only HTTP client helpers out of the production `StatusCore` module. They are public production types with no production call sites.
2. **TYPE-003**: decide how unreachable state is represented before adding more status or persistence behaviour. `PageSnapshot.overall` and `PageSnapshot.isUnreachable` can disagree.
3. **TYPE-001**: move the shared `ParserError` out of `StatuspageParser.swift`; it is used by all three provider parsers.

The existing architecture has useful boundaries. `WatchedPage` is persisted configuration, `PageSnapshot` is the latest provider observation, and `DirectoryHTTPClient` remains a production type because the executable selects it for `GREENDOT_FIXTURE_DIR` UI tests. The recommendations below preserve those boundaries and do not propose one large shared model or generic test framework.

## Type Inventory by Domain

### StatusCore models and status behaviour — 13

`StatusProvider`, `ComponentStatus`, `ComponentStatus.CodingKeys`, `Incident`, `PageSnapshot`, `WatchedPage`, `WatchedPage.CodingKeys`, `Severity`, `Aggregator`, `ComponentTree`, `GreyPulse`, `Toast`, and `ToastPolicy`.

### StatusCore provider parsing and probing — 11

`ParserError`, `StatuspageParser`, `StatuspageParser.Row`, `InstatusParser`, `StatuspalParser`, `StatusMapping`, `ProbeError`, `ProviderProbe`, `ProviderProbe.AttemptResult`, `ProbeHit`, and `CountBox`.

`ParserError` is listed with parsing because it is shared by the provider parsers. `CountBox` is private probe instrumentation, not a public domain model.

### StatusCore monitor and persistence — 8

`AppConfig`, `StoreError`, `PageStore`, `Monitor`, `MonitorError`, `WatchedPagePollResult`, `WatchedPagePollStart`, and `WatchedPagePollMerge`.

### StatusCore transport and file safety — 8

`HTTPClient`, `URLSessionHTTPClient`, `MapHTTPClient`, `DelayHTTPClient`, `RecordingHTTPClient`, `RecordedURLs`, `DirectoryHTTPClient`, and `PathSafety`.

### greendot menu and status-item UI — 11

`StatusMenuState`, `StatusMenuState.Content`, `StatusMenuHandlers`, `MenuBuilder`, `TargetAction`, `MenuClickOpener`, `MenuCommands`, `ScheduledMainActorWork`, `StatusMenuController`, `StatusDot`, and `StatusDot.Key`.

### greendot panels and component editing — 4

`ComponentPicker`, `KeyablePanel`, `PagePanelController`, and `StatusPageEditor`.

### greendot application integration — 7

`AppDelegate`, `AppEditMenu`, `BuildInfo`, `AboutPanel`, `LaunchAtLogin`, `URLOpener`, and `UITestDriver`.

### greendot notification delivery — 5

`ToastDelivery`, `UserNotificationCenterClient`, `LiveUserNotificationCenterClient`, `ToastScheduler`, and `SystemToastDelivery`.

### StatusCore test and support definitions — 15

The ten `XCTestCase` types `AggregatorTests`, `ComponentToggleTests`, `GreyPulseTests`, `MonitorFirstRunTests`, `MonitorRefreshTransactionTests`, `PageStoreValidationTests`, `ParserTests`, `PollPerformanceTests`, `ProbeAndMonitorTests`, and `ToastPolicyTests`; the test clients `ConcurrencyProbeHTTPClient`, `FailingHTTPClient`, and `CancellationHTTPClient`; and the support types `ControllableHTTPClient` and `ControllableLock`.

### greendot test definitions — 18

The eleven `XCTestCase` types `AboutTests`, `AppDelegateRefreshErrorTests`, `CopyrightTests`, `MenuBuilderTests`, `PanelLifecycleTests`, `PanelReleaseTests`, `PerformanceHarnessTests`, `StatusMenuControllerTests`, `StatusPageEditorTests`, `SystemToastDeliveryTests`, and `URLOpenerTests`; plus `InMemoryToastDelivery`, `SequenceHTTPClient`, `RecordingUserNotificationCenter`, `WeakReference`, `StatusMenuControllerTests.ScheduledMainActorWork`, `PerformanceHarnessTests.MenuMetrics`, and `PerformanceHarnessTests.RemainingMetrics`.

### UI test definitions — 1

`GreenDotUITests`.

## Critical Findings

There are no HIGH-severity type-consolidation findings. The current build and test results do not show a type-level runtime break. The MEDIUM findings are maintainability and model-integrity risks that should be handled before the next expansion of providers or persisted status behaviour.

## Medium Findings

### TYPE-001 — Shared parser error is owned by one provider parser

- **Evidence:** `Sources/StatusCore/StatuspageParser.swift:3-13` defines `ParserError`; `Sources/StatusCore/InstatusParser.swift:8,11` and `Sources/StatusCore/StatuspalParser.swift:7` throw the same type. `ProviderProbe` treats all parser errors as provider misses at `Sources/StatusCore/ProviderProbe.swift:151-155`.
- **Canonical location:** a shared `Sources/StatusCore/ParserError.swift` (or a provider-parsing module file), not `StatuspageParser.swift`.
- **Migration plan:** move the unchanged enum and its `LocalizedError` implementation to the shared parsing file. Leave the parser call sites unchanged, then run parser tests and verify that provider mismatch and invalid JSON still produce the same cases.
- **Severity:** MEDIUM. The current behaviour is correct, but the file ownership is misleading and creates a hidden dependency on the first parser when more providers are added.
- **Confidence:** CERTAIN.
- **Recommendation:** `COLOCATE`.

### TYPE-002 — Test-only HTTP client family is part of the production module

- **Evidence:** `Sources/StatusCore/HTTPClient.swift:21-66` defines `MapHTTPClient`, `DelayHTTPClient`, and `RecordingHTTPClient` (with `RecordedURLs` at line 68). `rg` finds their uses only under `Tests`; there are no production call sites. `Package.swift:18-24` already gives both test targets the `TestSupport` target. `DirectoryHTTPClient` is different: `Sources/greendot/AppDelegate.swift:25-30` uses it for the fixture environment and it is required by the UI-test design.
- **Canonical location:** `Tests/TestSupport/HTTPClientDoubles.swift` for the map, delay, and recording helpers. Keep `HTTPClient`, `URLSessionHTTPClient`, and the fixture-backed `DirectoryHTTPClient` in production.
- **Migration plan:** move the three test helpers and their private recording state to `TestSupport`; add `import TestSupport` to the affected test files; keep the public `HTTPClient` contract unchanged. Run both test targets and the fixture UI-test build after the move.
- **Severity:** MEDIUM. The public `StatusCore` surface contains test machinery, which makes the production domain harder to understand and encourages new tests to depend on non-production APIs.
- **Confidence:** CERTAIN.
- **Recommendation:** `EXTRACT_TEST_SUPPORT`.

### TYPE-003 — Snapshot severity and reachability are two sources of truth

- **Evidence:** `Sources/StatusCore/Models.swift:60-67` stores both `PageSnapshot.overall: Severity` and `PageSnapshot.isUnreachable: Bool`. `Sources/StatusCore/Monitor.swift:211-218` writes `.grey` and `true` together for a failed poll. Other code still checks the flag separately: `Models.swift:127-130`, `Monitor.swift:177-183`, `ToastPolicy.swift:37-44`, and `MenuBuilder.swift:102-123`. Tests can construct a contradictory `.green` plus `isUnreachable: true` snapshot at `Tests/StatusCoreTests/ComponentToggleTests.swift:263-271`.
- **Canonical location:** a single page-condition value (for example `PageCondition.reachable(Severity)` / `.unreachable`) should own the relationship. `Severity.grey` can remain a display result for the grey pulse, but it should not be a second persisted reachability signal.
- **Migration plan:** first record the current JSON format and add compatibility decoding. Introduce the condition value, make the old fields computed or migration-only, then update `WatchedPage.displaySeverity`, `Monitor.displayedSeverity`, `ToastPolicy`, and menu rendering. Preserve the existing grey-pulse rule and add tests for reachable grey, unreachable pages, and mixed red/unreachable pages before removing any stored field.
- **Severity:** MEDIUM. The context document intentionally describes both fields, so this is a design consolidation decision rather than a confirmed runtime bug; however, callers can currently construct inconsistent values.
- **Confidence:** LIKELY.
- **Recommendation:** `REVIEW`.

## Low / Debatable Findings

### TYPE-004 — Overall status text is duplicated in core and UI

- **Evidence:** `Sources/StatusCore/ToastPolicy.swift:37-44` and `Sources/greendot/MenuBuilder.swift:185-191` contain the same severity-to-label switch (`Operational`, `Degraded`, `Major outage`, `Unreachable`). Provider-specific component text is separately mapped by `Sources/StatusCore/StatusMapping.swift:20-29`, so only the overall label should be shared.
- **Canonical location:** `Severity` in `Sources/StatusCore/Severity.swift`, as a `displayName` or equivalent property.
- **Migration plan:** add the four-label mapping once, use it from `ToastPolicy` and `MenuBuilder`, and retain provider-specific component labels in `StatusMapping`. Existing toast and menu assertions should remain the regression checks.
- **Severity:** LOW. The duplicate switches are small and currently agree, but a future label change can update one surface only.
- **Confidence:** CERTAIN.
- **Recommendation:** `CONSOLIDATE`.

### TYPE-005 — Probe hit payload is represented twice

- **Evidence:** `Sources/StatusCore/ProviderProbe.swift:129-133` defines `AttemptResult.hit(PageSnapshot, Data)`, while `ProviderProbe.swift:241-244` defines `ProbeHit` with the same two values. The tuple is unpacked at `ProviderProbe.swift:45-55` and `197-210`, then rebuilt as `ProbeHit`.
- **Canonical location:** `ProbeHit` as the payload of `AttemptResult.hit`.
- **Migration plan:** change the private enum case to `hit(ProbeHit)`, construct `ProbeHit` in `attempt`, and pass it through the provider-specific switch without re-wrapping. Keep `AttemptResult` private because its miss/network-error states are local to probing.
- **Severity:** LOW. The duplicate is internal and small, but the two shapes can drift if the hit payload gains another field.
- **Confidence:** CERTAIN.
- **Recommendation:** `CONSOLIDATE`.

### TYPE-006 — Test redeclares the production scheduler alias

- **Evidence:** `Sources/greendot/StatusMenuController.swift:4` defines `ScheduledMainActorWork`; `Tests/greendotTests/StatusMenuControllerTests.swift:6` defines the identical private alias. The test imports the executable with `@testable` and uses the alias at lines 53, 97, and 166.
- **Canonical location:** the production alias at `Sources/greendot/StatusMenuController.swift:4` (or one shared internal scheduling file).
- **Migration plan:** remove the private test alias and use the internal production alias. If the contract must be shared by more UI types, move one alias to a dedicated internal file instead of keeping parallel declarations.
- **Severity:** LOW. The signatures currently match exactly, but the test can stop checking the production contract if the production alias changes later.
- **Confidence:** CERTAIN.
- **Recommendation:** `CONSOLIDATE`.

### TYPE-007 — `StatusMenuController` has an unnecessary `NSObject` base class

- **Evidence:** `Sources/greendot/StatusMenuController.swift:6-7` declares `final class StatusMenuController: NSObject`. The file has no `@objc` methods, `#selector` use, Objective-C protocol conformance, or `NSObject` API. The AppKit Objective-C types that do need the base class are separately visible in `ComponentPicker.swift:4`, `MenuClickOpener.swift:5`, `MenuBuilder.swift:207`, `PagePanelController.swift:9`, and `AppDelegate.swift:4`.
- **Canonical location:** a plain `@MainActor final class StatusMenuController`.
- **Migration plan:** remove only the `NSObject` inheritance, compile with the concurrency probe, and run `StatusMenuControllerTests`. Do not remove `NSObject` from delegate or selector-backed types.
- **Severity:** LOW. It adds no current behaviour and makes the inheritance model less precise.
- **Confidence:** CERTAIN.
- **Recommendation:** `REMOVE_INHERITANCE`.

### TYPE-008 — Component hierarchy has overlapping group state

- **Evidence:** `Sources/StatusCore/Models.swift:9-16` stores both `children` and `isGroup`. `StatuspageParser.Row` repeats grouping state with `isGroup` and `groupID` at `Sources/StatusCore/StatuspageParser.swift:44-50`; `StatuspalParser` derives `isGroup` from nested children at `Sources/StatusCore/StatuspalParser.swift:51-59`. Model and UI code repeatedly checks `isGroup || !children.isEmpty` at `Models.swift:145-150`, `ComponentPicker.swift:79-82`, and `MenuBuilder.swift:167-169`.
- **Canonical location:** one explicit component-kind decision, such as a computed `isContainer` or a `ComponentKind` value, while preserving the provider requirement for an empty declared group.
- **Migration plan:** document and test the empty-group case first. Then centralize the display predicate, or replace the persisted pair with one kind value while keeping backward-compatible decoding for existing config files. Do not remove `isGroup` solely because most groups have children.
- **Severity:** LOW. The fields are not fully redundant because an empty provider group is meaningful; the repeated predicate is the maintenance risk.
- **Confidence:** LIKELY.
- **Recommendation:** `REVIEW`.

### TYPE-009 — Watched-page identity overlaps snapshot identity

- **Evidence:** `WatchedPage` stores `url` and `name` at `Sources/StatusCore/Models.swift:99-105`; `PageSnapshot` stores another `url` and `name` at `Models.swift:60-67`. `Monitor.add/edit` uses `snapshot.name` to fill the configured page name at `Sources/StatusCore/Monitor.swift:58-63,70-84`, while the UI uses `page.name` for the title and `snapshot.url ?? page.url` for links at `Sources/greendot/MenuBuilder.swift:80-139`.
- **Canonical location:** keep the two concepts separate, but make the authority explicit with names such as configured/display identity versus provider/canonical identity. Do not merge `WatchedPage` and `PageSnapshot`.
- **Migration plan:** review field names and add documentation or computed aliases first. If renaming, preserve the existing Codable keys and migrate callers in one change; add a test for a provider URL/name that differs from the user-entered values.
- **Severity:** LOW. The design intentionally has a persisted watch and an observed snapshot, but the identical field names make an authority mistake easy.
- **Confidence:** LIKELY.
- **Recommendation:** `REVIEW`.

## Recommendations

1. Co-locate shared parsing errors and remove test HTTP helpers from production before adding another provider or another test harness.
2. Resolve the `PageSnapshot` condition model with a backward-compatible Codable plan. Treat this as a design review, not a field deletion.
3. Add one `Severity` display-label API and use it in both toast and menu paths.
4. Replace the private probe tuple with `ProbeHit` and remove the duplicate scheduler alias.
5. Remove only the unnecessary `NSObject` inheritance from `StatusMenuController`; retain Objective-C inheritance where selectors or AppKit delegate protocols require it.
6. Keep local helpers local. `StatuspageParser.Row`, `ProviderProbe.AttemptResult`, `ProviderProbe.CountBox`, `HTTPClient.RecordedURLs`, `StatusDot.Key`, `KeyablePanel`, and one-test doubles such as `FailingHTTPClient`, `CancellationHTTPClient`, `SequenceHTTPClient`, and `WeakReference` should not be promoted to a global model or generic utility merely to reduce the type count.

## Out of Scope / Flagged for Review

- `StatusMapping` is a single cross-provider namespace at `Sources/StatusCore/StatusMapping.swift:1-53`. It is currently a small and clear canonical mapping point. If provider-specific rules grow substantially, split provider mappers then; do not add a generic mapper or inheritance hierarchy now.
- `StatusMenuState.Content`, `StatusMenuHandlers`, and the three poll transaction structs are boundary/value types with distinct consumers. Their similar struct syntax is not duplication.
- `DirectoryHTTPClient` is intentionally in the production target: `AppDelegate` selects it for `GREENDOT_FIXTURE_DIR`, and the UI-test design calls for fixture files without a test HTTP server. It should not be moved with the other test-only clients.
- `RecordedURLs`, `CountBox`, `StatusDot.Key`, `KeyablePanel`, parser `Row`, and one-off test doubles are correctly scoped. Centralizing them would increase coupling and make local test intent less clear.
- SwiftLint reports length and tuple issues in `ProviderProbe` and performance tests. Those are function/test-shape concerns, not evidence that a new generic or inheritance type is needed, so they are not counted as type findings here.

## Independent Verification Disposition

The mandatory gate selected 6 of 9 records. Independent verifiers confirmed 6; those records now have `verified: true`. 3 lower-confidence records remain provisional.

Verification evidence: [verification-batch-1.md](verification-batch-1.md), [verification-batch-3.md](verification-batch-3.md).

Final machine-readable severity counts: HIGH 0, MEDIUM 1, LOW 8. The original prose above records the specialist's pre-verification assessment; this disposition and the JSON block below are authoritative after verification.

## Machine-Readable Findings

```json
{"findings":[{"id":"types-001","file":"Sources/StatusCore/StatuspageParser.swift","line":3,"severity":"LOW","confidence":"CERTAIN","recommendation":"COLOCATE","detail":"A shared parser error is located in the Statuspage parser file despite use by all providers.","verified":true},{"id":"types-002","file":"Sources/StatusCore/HTTPClient.swift","line":21,"severity":"LOW","confidence":"CERTAIN","recommendation":"EXTRACT_TEST_SUPPORT","detail":"In-memory test doubles are shipped in production despite test-only consumers.","verified":true},{"id":"types-003","file":"Sources/StatusCore/Models.swift","line":60,"severity":"MEDIUM","confidence":"LIKELY","recommendation":"REVIEW","detail":"PageSnapshot stores overall Severity and isUnreachable Bool, while Monitor writes grey plus true and several consumers branch on the Bool. Define one backward-compatible page-condition value before extending persisted status behaviour.","verified":false},{"id":"types-004","file":"Sources/StatusCore/Severity.swift","line":1,"severity":"LOW","confidence":"CERTAIN","recommendation":"CONSOLIDATE","detail":"Centralize Severity display names but retain provider-specific component text.","verified":true},{"id":"types-005","file":"Sources/StatusCore/ProviderProbe.swift","line":129,"severity":"LOW","confidence":"CERTAIN","recommendation":"CONSOLIDATE","detail":"Use ProbeHit as the private AttemptResult payload.","verified":true},{"id":"types-006","file":"Sources/greendot/StatusMenuController.swift","line":4,"severity":"LOW","confidence":"CERTAIN","recommendation":"CONSOLIDATE","detail":"Use one internal production/shared alias.","verified":true},{"id":"types-007","file":"Sources/greendot/StatusMenuController.swift","line":7,"severity":"LOW","confidence":"CERTAIN","recommendation":"REMOVE_INHERITANCE","detail":"Remove only StatusMenuController NSObject inheritance and super.init.","verified":true},{"id":"types-008","file":"Sources/StatusCore/Models.swift","line":9,"severity":"LOW","confidence":"LIKELY","recommendation":"REVIEW","detail":"ComponentStatus stores children and isGroup, and UI/parser code repeats the isGroup-or-children predicate. Preserve explicit empty groups, then centralize the component-kind decision or use a documented kind value.","verified":false},{"id":"types-009","file":"Sources/StatusCore/Models.swift","line":60,"severity":"LOW","confidence":"LIKELY","recommendation":"REVIEW","detail":"WatchedPage and PageSnapshot both expose name and url, but one is configured identity and the other is provider identity. Keep the types separate and clarify or rename the fields with Codable compatibility.","verified":false}]}
```
