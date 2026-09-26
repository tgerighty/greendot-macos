Ponytail: full intensity. Climb the YAGNI ladder. Prefer reuse, stdlib, and native features. Use minimal diffs. Preserve trust-boundary validation, security, and accessibility.

# Type Consolidation Assessment

## Executive Summary

- Total findings: **2 LOW / debatable observations**. Severity: **HIGH=0, MEDIUM=0, LOW=2**. Both concern duplicated test clients. Sources: `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:360`, `Tests/greendotTests/PanelLifecycleTests.swift:353`, `Tests/StatusCoreTests/NetworkReachabilityTests.swift:132`, `Tests/greendotTests/AppDelegateNetworkToastTests.swift:187`.
- **Recommended consolidation now: none.** Each duplicate contains five or six lines. Sharing requires a public test helper for a small reduction. Sources: `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:360`, `Tests/StatusCoreTests/NetworkReachabilityTests.swift:132`, `Tests/TestSupport/HTTPClientDoubles.swift:4`, `Package.swift:9`.
- The main domain concepts already have shared definitions. Keep `WatchedPage`, `PageSnapshot`, `ComponentStatus`, `Incident`, and `Severity` in `StatusCore`. Sources: `Sources/StatusCore/Models.swift:21`, `Sources/StatusCore/Models.swift:62`, `Sources/StatusCore/Models.swift:72`, `Sources/StatusCore/Models.swift:100`, `Sources/StatusCore/Severity.swift:1`.
- Estimated immediate impact: **0 product lines and 0 product files**. The two observations cover **22 existing lines in four test files**. Sources: `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:360`, `Tests/greendotTests/PanelLifecycleTests.swift:353`, `Tests/StatusCoreTests/NetworkReachabilityTests.swift:132`, `Tests/greendotTests/AppDelegateNetworkToastTests.swift:187`.

Top three priorities:

1. Keep the existing shared domain model. The desktop imports `StatusCore` and consumes its page and severity types directly. Sources: `Sources/greendot/MenuBuilder.swift:2`, `Sources/greendot/MenuBuilder.swift:4`, `Sources/greendot/ComponentPicker.swift:13`.
2. Keep the two small test-client pairs local. Reconsider only when their behavior requires coordinated changes. Sources: `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:360`, `Tests/greendotTests/PanelLifecycleTests.swift:353`, `Tests/StatusCoreTests/NetworkReachabilityTests.swift:132`, `Tests/greendotTests/AppDelegateNetworkToastTests.swift:187`.
3. Preserve the distinction between settings, cached state, and poll results. Their fields and storage rules differ. Sources: `Sources/StatusCore/PageStore.swift:3`, `Sources/StatusCore/StateFile.swift:4`, `Sources/StatusCore/MonitorPollTransaction.swift:3`, `Sources/StatusCore/Models.swift:180`.

## Pre-flight and Method

Scope: Agent 2, type-consolidation only. This assessment records static analysis. It does not authorize source changes.

The package declares Swift tools 5.9 and macOS 13. Its targets are `StatusCore`, `greendot`, `TestSupport`, and two test targets. Sources: `Package.swift:1`, `Package.swift:6`, `Package.swift:8`, `Package.swift:9`, `Package.swift:14`, `Package.swift:18`, `Package.swift:22`.

The repository provides `swift test` and `swiftlint lint --strict`. SwiftLint includes `Sources` and `Tests` and excludes generated build output and `UITests`. Sources: `Makefile:12`, `Makefile:18`, `.swiftlint.yml:1`, `.swiftlint.yml:4`.

Recorded session observations:

- `git rev-parse --short HEAD` returned `9320756`.
- `command -v` found `rg`, `python3`, and `node`.
- `command -v` did not find `swift`, `swiftc`, `swiftlint`, `xcodebuild`, `tsc`, `mypy`, `pyright`, or `cloc`.
- A read-only Python standard-library scan counted 147 Swift files under `Sources`, `Tests`, and `UITests`.
- The scan found 211 named declarations: 69 in `StatusCore`, 35 in `greendot`, 36 test helpers, and 71 test suites.
- A second broad declaration search found no additional declaration candidates. The complete declaration catalogue below records the source locations.

Method: use `rg` to locate declarations, imports, tuples, generic declarations, and callers. Read candidate definitions and their consumers. Compare duplicate bodies with Python. Exclude Markdown examples, resources, and generated output from the declaration census. Extensions add members or conformances and are not counted as new types. Examples: `Sources/StatusCore/Models.swift:46`, `Sources/StatusCore/StateFile.swift:38`.

No compiler, lint, or runtime test result is claimed. The required platform and commands are documented at `README.md:30`, `Makefile:12`, and `Makefile:18`.

## Critical Findings

None supported by this static assessment. The central page, component, incident, and severity types already have common definitions. Sources: `Sources/StatusCore/Models.swift:21`, `Sources/StatusCore/Models.swift:62`, `Sources/StatusCore/Models.swift:72`, `Sources/StatusCore/Models.swift:100`, `Sources/StatusCore/Severity.swift:1`.

## Medium Findings

None supported by this static assessment. Similar transport, cache, and poll records carry different information. Their differences are detailed below. Sources: `Sources/StatusCore/HTTPClient.swift:3`, `Sources/StatusCore/StateFile.swift:4`, `Sources/StatusCore/ProviderProbe.swift:244`, `Sources/StatusCore/MonitorPollTransaction.swift:3`.

## Low / Debatable Findings

### type-consolidation-001 — Two local cancellation clients

**Severity:** LOW. **Confidence:** CERTAIN about the duplicate bodies. **Recommendation:** KEEP SEPARATE. **Verified:** false.

Both `CancellationHTTPClient` definitions implement `get(_:)` by throwing `CancellationError()`. Their method bodies are identical. The desktop test explicitly repeats `Sendable`, which the shared protocol already requires. Sources: `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:360`, `Tests/greendotTests/PanelLifecycleTests.swift:353`, `Sources/StatusCore/HTTPClient.swift:42`.

The core consumer checks cancellation propagation from provider discovery. The desktop consumer checks that cancelled startup seeding does not report an error. Sources: `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:156`, `Tests/greendotTests/PanelLifecycleTests.swift:282`.

Keep these five-line definitions local. A shared definition would need public access and a public initializer across the existing module boundary. The existing shared clients show this pattern. Sources: `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:360`, `Tests/greendotTests/PanelLifecycleTests.swift:353`, `Tests/TestSupport/HTTPClientDoubles.swift:4`, `Tests/TestSupport/HTTPClientDoubles.swift:8`, `Package.swift:18`, `Package.swift:22`.

**Deferred consolidation plan:** If the behavior later needs one shared implementation, use `Tests/TestSupport/HTTPClientDoubles.swift`. Keep the name `CancellationHTTPClient` and the existing `HTTPClient` conformance. Add a public zero-argument initializer and public `get(_:)`. Remove the two private copies. Both consumer files already import `TestSupport`. Sources: `Tests/TestSupport/HTTPClientDoubles.swift:4`, `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:3`, `Tests/greendotTests/PanelLifecycleTests.swift:5`.

**Estimated impact of that deferred plan:** three test files, ten existing declaration lines replaced by about six shared lines. This estimate excludes blank lines. It is too small to justify a standalone change. Sources: `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:360`, `Tests/greendotTests/PanelLifecycleTests.swift:353`, `Tests/TestSupport/HTTPClientDoubles.swift:8`.

If that plan is selected later, run the existing cancellation tests on macOS. Preserve their assertions and the concrete `CancellationError` behavior. Sources: `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:156`, `Tests/greendotTests/PanelLifecycleTests.swift:282`.

### type-consolidation-002 — Two local clients that fail on unexpected HTTP

**Severity:** LOW. **Confidence:** CERTAIN about the duplicate definitions. **Recommendation:** KEEP SEPARATE. **Verified:** false.

The two `FailIfCalledHTTPClient` definitions are identical. Each records `XCTFail` and then throws `URLError(.notConnectedToInternet)`. Sources: `Tests/StatusCoreTests/NetworkReachabilityTests.swift:132`, `Tests/greendotTests/AppDelegateNetworkToastTests.swift:187`.

The core tests use the client to detect requests while offline. The desktop test uses it when a failed config load must prevent polling. Sources: `Tests/StatusCoreTests/NetworkReachabilityTests.swift:48`, `Tests/greendotTests/AppDelegateNetworkToastTests.swift:124`.

Keep these six-line definitions with their tests. Sharing requires a public helper and moves XCTest assertion behavior into `TestSupport`. The existing HTTP helpers import Foundation and `StatusCore`. Sources: `Tests/StatusCoreTests/NetworkReachabilityTests.swift:132`, `Tests/greendotTests/AppDelegateNetworkToastTests.swift:187`, `Tests/TestSupport/HTTPClientDoubles.swift:1`, `Tests/TestSupport/HTTPClientDoubles.swift:2`.

Do not replace this type with `MapHTTPClient`. That client returns an empty 404 response for an unknown request. It does not record the assertion that makes an unexpected request fail the test. Sources: `Tests/TestSupport/HTTPClientDoubles.swift:13`, `Tests/StatusCoreTests/NetworkReachabilityTests.swift:134`.

**Consolidation plan:** no move. Retain both local definitions and their assertions. There is no demonstrated need for a configurable failure-client abstraction. The existing definitions contain the complete required behavior. Sources: `Tests/StatusCoreTests/NetworkReachabilityTests.swift:132`, `Tests/greendotTests/AppDelegateNetworkToastTests.swift:187`.

## Recommendations

1. **Keep canonical domain types in their current files.** Use `Models.swift` for the page, snapshot, component, incident, and provider concepts. Keep `Severity` in `Severity.swift`. Avoid a new global `types/` directory. Sources: `Sources/StatusCore/Models.swift:3`, `Sources/StatusCore/Models.swift:21`, `Sources/StatusCore/Models.swift:62`, `Sources/StatusCore/Models.swift:72`, `Sources/StatusCore/Models.swift:100`, `Sources/StatusCore/Severity.swift:1`.
2. **Keep storage types beside storage behavior.** `AppConfig` belongs with `PageStore`. `PageState` and `StateFile` belong with the storage encoding rules. Preserve validation and rollback if this area changes. Sources: `Sources/StatusCore/PageStore.swift:3`, `Sources/StatusCore/StateFile.swift:4`, `Sources/StatusCore/StateFile.swift:10`, `Sources/StatusCore/PageStore.swift:185`, `Sources/StatusCore/PageStore.swift:264`.
3. **Keep parser intermediates local.** `Row`, `HostGroup`, and `ServiceRecord` represent provider input before conversion to `ComponentStatus`. Sharing them would mix different input schemas. Sources: `Sources/StatusCore/StatuspageParser.swift:32`, `Sources/StatusCore/StatuspageParser.swift:74`, `Sources/StatusCore/IcingaParser.swift:75`, `Sources/StatusCore/IcingaParser.swift:87`, `Sources/StatusCore/IcingaParser.swift:122`.
4. **Use the existing shared test target only when sharing pays for itself.** The deferred cancellation plan above is the only specific merge candidate. Retain the other local fixtures and test assertions. Sources: `Package.swift:9`, `Tests/TestSupport/HTTPClientDoubles.swift:4`, `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:360`, `Tests/StatusCoreTests/NetworkReachabilityTests.swift:134`.
5. **Preserve boundary and accessibility behavior.** Type cleanup must retain redirect checks, XML entity restrictions, URL credential stripping, file permissions, and accessibility labels/actions. Sources: `Sources/StatusCore/HTTPClient.swift:88`, `Sources/StatusCore/RssParser.swift:10`, `Sources/greendot/URLOpener.swift:14`, `Sources/StatusCore/PageStore.swift:261`, `Sources/greendot/StatusMenuController.swift:82`, `Sources/greendot/PersistentToastPresenter.swift:192`, `Sources/greendot/PersistentToastPresenter.swift:209`.

## Type Usage and Consolidation Decisions

### Existing shared types and consumers

Swift uses module imports here. The package gives both test targets access to `StatusCore` and `TestSupport`. The desktop target depends on `StatusCore`. Sources: `Package.swift:14`, `Package.swift:18`, `Package.swift:22`.

| Concept | Canonical definition | Observed consumers and decision |
|---|---|---|
| Watched page and snapshot | `Sources/StatusCore/Models.swift:72`, `Sources/StatusCore/Models.swift:100` | Polling uses the same types at `Sources/StatusCore/Monitor+Polling.swift:20`. Menus and editing use them at `Sources/greendot/MenuBuilder.swift:6` and `Sources/greendot/ComponentPicker.swift:14`. Keep. |
| Component tree | `Sources/StatusCore/Models.swift:21`, `Sources/StatusCore/ComponentTree.swift:1` | Parsers produce it at `Sources/StatusCore/StatuspageParser.swift:74`. The picker consumes it at `Sources/greendot/ComponentPicker.swift:11`. Keep one domain type. |
| Incident | `Sources/StatusCore/Models.swift:62` | Statuspage and Flashduty use it at `Sources/StatusCore/StatuspageParser.swift:16` and `Sources/StatusCore/FlashdutyParser.swift:26`. Keep. |
| Severity | `Sources/StatusCore/Severity.swift:1` | Provider mappings use it at `Sources/StatusCore/StatusMapping.swift:68`. Icon rendering uses it at `Sources/greendot/StatusDot.swift:13`. Keep. |
| Provider identity | `Sources/StatusCore/Models.swift:3` | Discovery switches on it at `Sources/StatusCore/ProviderProbe+Hit.swift:45`. The snapshot stores it at `Sources/StatusCore/Models.swift:75`. Keep. |
| Poll result | `Sources/StatusCore/MonitorPollTransaction.swift:3` | Polling and confirmation share it at `Sources/StatusCore/Monitor+Polling.swift:24` and `Sources/StatusCore/Monitor+PollConfirmation.swift:7`. Keep beside poll code. |
| Probe context, attempt, flags, and hit | `Sources/StatusCore/ProviderProbe.swift:73`, `Sources/StatusCore/ProviderProbe.swift:79`, `Sources/StatusCore/ProviderProbe.swift:87`, `Sources/StatusCore/ProviderProbe.swift:244` | The dispatcher uses them at `Sources/StatusCore/ProviderProbe+Hit.swift:11`. Provider extensions use them at `Sources/StatusCore/ProviderProbe+Icinga.swift:22`. Keep. |
| HTTP client and located response | `Sources/StatusCore/HTTPClient.swift:3`, `Sources/StatusCore/HTTPClient.swift:42` | Provider discovery uses `get` at `Sources/StatusCore/ProviderProbe.swift:155`. RSS uses `getLocated` at `Sources/StatusCore/ProviderProbe+RSS.swift:12`. Keep the located URL. |
| Reachability interface | `Sources/StatusCore/NetworkReachability.swift:5` | The monitor consumes it at `Sources/StatusCore/Monitor.swift:11`. A test implementation exists at `Tests/TestSupport/FakeNetworkReachability.swift:5`. Keep. |
| Toast | `Sources/StatusCore/ToastPolicy.swift:3` | Policy constructs it at `Sources/StatusCore/ToastPolicy.swift:37`. Delivery accepts it at `Sources/greendot/ToastDelivery.swift:9`. Keep one payload. |
| Toast interfaces | `Sources/greendot/ToastDelivery.swift:4`, `Sources/greendot/PersistentToastPresenter.swift:5`, `Sources/greendot/SystemToastDelivery.swift:5` | Separate test implementations exist at `Tests/greendotTests/InMemoryToastDelivery.swift:5`, `Tests/greendotTests/ToastDeliveryDoubles.swift:5`, and `Tests/greendotTests/ToastDeliveryDoubles.swift:24`. Keep their distinct responsibilities. |
| Component selection counts | `Sources/greendot/ComponentSelectionIndex.swift:3`, `Sources/greendot/ComponentSelectionIndex.swift:8` | The picker uses the summary at `Sources/greendot/ComponentPicker.swift:149` and `Sources/greendot/ComponentPicker.swift:162`. Keep this UI model outside `StatusCore`. |
| Menu state and callbacks | `Sources/greendot/MenuBuilder.swift:4`, `Sources/greendot/MenuBuilder.swift:20` | The delegate constructs them at `Sources/greendot/AppDelegate.swift:128` and `Sources/greendot/AppDelegate.swift:137`. The controller accepts them at `Sources/greendot/StatusMenuController.swift:19`. Keep. |
| JSON scalar conversion | `Sources/StatusCore/StatusioParser.swift:49` | Apple, Google, and Slack reuse it at `Sources/StatusCore/AppleParser.swift:22`, `Sources/StatusCore/GoogleParser.swift:25`, and `Sources/StatusCore/SlackParser.swift:31`. No second shared type or file is needed. |

### Similar definitions that must remain distinct or local

| Types or shapes | Evidence and decision |
|---|---|
| `WatchedPage` and `PageSnapshot` | The watched page has user identity and selections. The snapshot has provider observations. A page can lack a snapshot. Keep separate. `Sources/StatusCore/Models.swift:72`, `Sources/StatusCore/Models.swift:100`. |
| `PageState`, `ProbeHit`, `WatchedPagePollResult` | Stored state pairs a URL with a snapshot. A successful probe pairs bytes with a snapshot. A poll result adds page identity and permits missing bytes. Keep separate. `Sources/StatusCore/StateFile.swift:4`, `Sources/StatusCore/ProviderProbe.swift:244`, `Sources/StatusCore/MonitorPollTransaction.swift:3`, `Sources/StatusCore/Monitor+Polling.swift:87`. |
| `AppConfig` and `StateFile` | Encoding writes settings and cached state separately. Reusing one encoded record would cross this boundary. Keep separate. `Sources/StatusCore/StateFile.swift:10`, `Sources/StatusCore/StateFile.swift:57`, `Sources/StatusCore/PageStore.swift:198`. |
| Four `CodingKeys` enums | Each belongs to a different containing type and lists different keys. These are not duplicate domain definitions. Keep nested. `Sources/StatusCore/Models.swift:47`, `Sources/StatusCore/Models.swift:164`, `Sources/StatusCore/StateFile.swift:11`, `Sources/StatusCore/StateFile.swift:39`. |
| `HostGroup` and `ServiceRecord` | Their common name/state fields do not erase the host's service collection or the service's host identity. Keep both private. `Sources/StatusCore/IcingaParser.swift:122`, `Sources/StatusCore/IcingaParser.swift:130`. |
| `RSSHubFeed` and `WatchedPage` | The feed record identifies a fixed child feed. A watched page holds settings and a snapshot. Keep the feed record private. `Sources/StatusCore/ProviderProbe+RSS.swift:127`, `Sources/StatusCore/ProviderProbe+RSS.swift:246`, `Sources/StatusCore/Models.swift:100`. |
| `IcingaObjectResponse`, `(Data, Int)`, and `HTTPGet` | The local Icinga record names data/status after status checks. `HTTPGet` additionally carries the final URL for redirect handling. A global response migration is unnecessary. Keep local records and current interfaces. `Sources/StatusCore/ProviderProbe+Icinga.swift:66`, `Sources/StatusCore/ProviderProbe+Icinga.swift:80`, `Sources/StatusCore/HTTPClient.swift:3`, `Sources/StatusCore/HTTPClient.swift:43`, `Sources/StatusCore/ProviderProbe+RSS.swift:16`. |
| Repeated `(severity: Severity, text: String)` | Mapping methods use a small labeled tuple. Salesforce passes the same shape to one helper. No alias or struct is needed now. Keep provider-specific text such as maintenance and unknown. `Sources/StatusCore/StatusMapping.swift:68`, `Sources/StatusCore/StatusMapping.swift:100`, `Sources/StatusCore/StatusMapping.swift:150`, `Sources/StatusCore/StatusMapping.swift:161`, `Sources/StatusCore/SalesforceParser.swift:51`. |
| `StatusMenuState` and nested `Content` | `Content` deliberately excludes severity. Menu caching compares it while the controller updates the icon separately. Keep both shapes. `Sources/greendot/MenuBuilder.swift:5`, `Sources/greendot/MenuBuilder.swift:14`, `Sources/greendot/MenuBuilder.swift:44`, `Sources/greendot/StatusMenuController.swift:45`. |
| `ScheduledMainActorWork` and `ToastScheduler` | One is a callback. The other schedules a callback after a duration. They are not interchangeable aliases. Keep them by their consumers. `Sources/greendot/StatusMenuController.swift:4`, `Sources/greendot/StatusMenuController.swift:13`, `Sources/greendot/SystemToastDelivery.swift:69`, `Sources/greendot/SystemToastDelivery.swift:79`. |
| Two identical private `Seed` records | Both store monitor, page ID, and directory. Their setup differs: reload a saved page versus prepare an editor with a red page. Keep these local return records. `Tests/greendotTests/AppDelegateToastClearTests.swift:78`, `Tests/greendotTests/AppDelegateToastClearTests.swift:84`, `Tests/greendotTests/StatusPageEditorToastTests.swift:185`, `Tests/greendotTests/StatusPageEditorToastTests.swift:191`. |
| Other `Seed`, `Seeded`, and `Fixture` records | These contain different combinations of monitor, store, client, delegate, delivery, and directory. Their local names do not denote one shared contract. Keep local. `Tests/StatusCoreTests/NetworkReachabilityTests.swift:108`, `Tests/greendotTests/AppDelegateNetworkToastTests.swift:144`, `Tests/greendotTests/AppDelegateConfigMenuTests.swift:9`, `Tests/greendotTests/AppDelegateReloadTests.swift:219`. |
| Benchmark metric records | Parse, poll, menu, and remaining metrics contain different measures. `BenchmarkRunMetrics` combines them. Preserve their measurement names. `Tests/greendotTests/PerformanceHarnessMetrics.swift:6`, `Tests/greendotTests/PerformanceHarnessMetrics.swift:12`, `Tests/greendotTests/PerformanceHarnessMetrics.swift:18`, `Tests/greendotTests/PerformanceHarnessMetrics.swift:24`, `Tests/greendotTests/PerformanceHarnessMetrics.swift:30`, `Tests/greendotTests/PerformanceHarnessMetrics.swift:37`. |
| Error enums | Parser, probe, storage, monitor, and menu errors describe different failures and scopes. Do not merge them into a global error enum. `Sources/StatusCore/ParserError.swift:3`, `Sources/StatusCore/ProviderProbe.swift:4`, `Sources/StatusCore/PageStore.swift:30`, `Sources/StatusCore/MonitorError.swift:3`, `Sources/greendot/AppDelegate+Config.swift:5`. |
| UI implementation types | The icon cache key, toast window item, toast layout, card view, and keyable window serve local framework behavior. Keep them local. `Sources/greendot/StatusDot.swift:6`, `Sources/greendot/PersistentToastPresenter.swift:53`, `Sources/greendot/PersistentToastPresenter.swift:60`, `Sources/greendot/PersistentToastPresenter.swift:162`, `Sources/greendot/PagePanelController.swift:4`. |

### Naming, inheritance, generics, and enum overlap

The main model names match the documented concepts: watched page, snapshot, severity, status page component, incident, and toast. No renaming is recommended. Sources: `CONTEXT.md:7`, `CONTEXT.md:10`, `CONTEXT.md:13`, `CONTEXT.md:16`, `CONTEXT.md:19`, `CONTEXT.md:22`, `Sources/StatusCore/Models.swift:21`, `Sources/StatusCore/ToastPolicy.swift:3`.

Provider parsers are separate namespaces with different input schemas. They already return `PageSnapshot`. A parser class hierarchy or generic provider interface would add structure without consolidating a duplicated result type. Sources: `Sources/StatusCore/StatuspageParser.swift:4`, `Sources/StatusCore/InstatusParser.swift:4`, `Sources/StatusCore/IcingaParser.swift:4`, `Sources/StatusCore/RssParser.swift:4`.

The inspected UI classes extend native framework classes directly. No application inheritance chain requires consolidation. Sources: `Sources/greendot/AppDelegate.swift:5`, `Sources/greendot/PagePanelController.swift:4`, `Sources/greendot/PagePanelController.swift:10`, `Sources/greendot/MenuClickOpener.swift:6`, `Sources/greendot/PersistentToastPresenter.swift:162`.

The custom generic `WeakReference<Object: AnyObject>` preserves weak-reference typing in a lifetime test. Generic lock and view helpers preserve their callers' result types. Keep them. Sources: `Tests/greendotTests/PanelLifecycleTests.swift:301`, `Tests/greendotTests/PanelLifecycleTests.swift:324`, `Sources/StatusCore/Monitor.swift:77`, `Tests/greendotTests/StatusPageEditorToastTests.swift:226`.

`AttemptResult` represents one probe attempt. `ProbeError` reports discovery failure after attempts. Their reachability cases do not make them duplicate unions. Sources: `Sources/StatusCore/ProviderProbe.swift:4`, `Sources/StatusCore/ProviderProbe.swift:73`, `Sources/StatusCore/ProviderProbe.swift:96`, `Sources/StatusCore/ProviderProbe.swift:108`.

## Complete Type Catalogue

This catalogue includes nominal declarations and type aliases. Nested names are qualified where useful. Test suites remain separate test entry points. Their declaration locations are listed below.

### Status model and evaluation

| Definition | Kind | Source |
|---|---|---|
| `ComponentTree` | enum | `Sources/StatusCore/ComponentTree.swift:1` |
| `GreyPulse` | enum | `Sources/StatusCore/GreyPulse.swift:3` |
| `StatusProvider` | enum | `Sources/StatusCore/Models.swift:3` |
| `ComponentStatus` | struct | `Sources/StatusCore/Models.swift:21` |
| `ComponentStatus.CodingKeys` | enum | `Sources/StatusCore/Models.swift:47` |
| `Incident` | struct | `Sources/StatusCore/Models.swift:62` |
| `PageSnapshot` | struct | `Sources/StatusCore/Models.swift:72` |
| `WatchedPage` | struct | `Sources/StatusCore/Models.swift:100` |
| `WatchedPage.CodingKeys` | enum | `Sources/StatusCore/Models.swift:164` |
| `Severity` | enum | `Sources/StatusCore/Severity.swift:1` |
| `Aggregator` | enum | `Sources/StatusCore/Severity.swift:17` |
| `StatusMapping` | enum | `Sources/StatusCore/StatusMapping.swift:1` |

### Settings and poll lifecycle

| Definition | Kind | Source |
|---|---|---|
| `Monitor` | class | `Sources/StatusCore/Monitor.swift:3` |
| `MonitorError` | enum | `Sources/StatusCore/MonitorError.swift:3` |
| `WatchedPagePollResult` | struct | `Sources/StatusCore/MonitorPollTransaction.swift:3` |
| `WatchedPagePollStart` | struct | `Sources/StatusCore/MonitorPollTransaction.swift:9` |
| `WatchedPagePollMerge` | struct | `Sources/StatusCore/MonitorPollTransaction.swift:18` |
| `AppConfig` | struct | `Sources/StatusCore/PageStore.swift:3` |
| `StoreError` | enum | `Sources/StatusCore/PageStore.swift:30` |
| `PageStore` | class | `Sources/StatusCore/PageStore.swift:44` |
| `PageState` | struct | `Sources/StatusCore/StateFile.swift:4` |
| `StateFile` | struct | `Sources/StatusCore/StateFile.swift:10` |
| `StateFile.CodingKeys` | enum | `Sources/StatusCore/StateFile.swift:11` |
| `AppConfig.CodingKeys` | enum | `Sources/StatusCore/StateFile.swift:39` |

### HTTP, authentication, and paths

| Definition | Kind | Source |
|---|---|---|
| `DirectoryHTTPClient` | struct | `Sources/StatusCore/DirectoryHTTPClient.swift:5` |
| `HTTPAuth` | enum | `Sources/StatusCore/HTTPAuth.swift:3` |
| `TLSTrust` | enum | `Sources/StatusCore/HTTPAuth.swift:22` |
| `HTTPGet` | struct | `Sources/StatusCore/HTTPClient.swift:3` |
| `RedirectPolicy` | enum | `Sources/StatusCore/HTTPClient.swift:15` |
| `RedirectPolicy.Origin` | struct | `Sources/StatusCore/HTTPClient.swift:35` |
| `HTTPClient` | protocol | `Sources/StatusCore/HTTPClient.swift:42` |
| `URLSessionHTTPClient` | struct | `Sources/StatusCore/HTTPClient.swift:54` |
| `SameOriginRedirectDelegate` | class | `Sources/StatusCore/HTTPClient.swift:95` |
| `NetworkReachability` | protocol | `Sources/StatusCore/NetworkReachability.swift:5` |
| `PathNetworkReachability` | class | `Sources/StatusCore/NetworkReachability.swift:16` |
| `PathSafety` | enum | `Sources/StatusCore/PathSafety.swift:3` |
| `URLAuth` | enum | `Sources/StatusCore/URLAuth.swift:3` |

### Provider discovery and parsing

| Definition | Kind | Source |
|---|---|---|
| `AppleParser` | enum | `Sources/StatusCore/AppleParser.swift:3` |
| `AwsParser` | enum | `Sources/StatusCore/AwsParser.swift:3` |
| `FlashdutyParser` | enum | `Sources/StatusCore/FlashdutyParser.swift:3` |
| `GoogleParser` | enum | `Sources/StatusCore/GoogleParser.swift:3` |
| `HerokuParser` | enum | `Sources/StatusCore/HerokuParser.swift:3` |
| `IcingaParser` | enum | `Sources/StatusCore/IcingaParser.swift:3` |
| `IcingaParser.HostGroup` | struct | `Sources/StatusCore/IcingaParser.swift:122` |
| `IcingaParser.ServiceRecord` | struct | `Sources/StatusCore/IcingaParser.swift:130` |
| `IncidentioParser` | enum | `Sources/StatusCore/IncidentioParser.swift:3` |
| `InstatusParser` | enum | `Sources/StatusCore/InstatusParser.swift:3` |
| `OktaParser` | enum | `Sources/StatusCore/OktaParser.swift:3` |
| `ParserError` | enum | `Sources/StatusCore/ParserError.swift:3` |
| `ProviderProbe.IcingaObjectResponse` | struct | `Sources/StatusCore/ProviderProbe+Icinga.swift:66` |
| `RSSHubFeed` | struct | `Sources/StatusCore/ProviderProbe+RSS.swift:127` |
| `ProbeError` | enum | `Sources/StatusCore/ProviderProbe.swift:4` |
| `ProviderProbe` | enum | `Sources/StatusCore/ProviderProbe.swift:23` |
| `ProviderProbe.AttemptResult` | enum | `Sources/StatusCore/ProviderProbe.swift:73` |
| `ProviderProbe.ProbeContext` | struct | `Sources/StatusCore/ProviderProbe.swift:79` |
| `ProviderProbe.ProbeFlags` | struct | `Sources/StatusCore/ProviderProbe.swift:87` |
| `ProbeHit` | struct | `Sources/StatusCore/ProviderProbe.swift:244` |
| `RssParser` | enum | `Sources/StatusCore/RssParser.swift:3` |
| `SalesforceParser` | enum | `Sources/StatusCore/SalesforceParser.swift:3` |
| `SlackParser` | enum | `Sources/StatusCore/SlackParser.swift:3` |
| `StatusioParser` | enum | `Sources/StatusCore/StatusioParser.swift:3` |
| `JSONScalar` | enum | `Sources/StatusCore/StatusioParser.swift:49` |
| `StatuspageParser` | enum | `Sources/StatusCore/StatuspageParser.swift:3` |
| `StatuspageParser.Row` | struct | `Sources/StatusCore/StatuspageParser.swift:32` |
| `StatuspalParser` | enum | `Sources/StatusCore/StatuspalParser.swift:3` |
| `UTF16Sniff` | enum | `Sources/StatusCore/UTF16Sniff.swift:3` |

### Desktop menus and editing

| Definition | Kind | Source |
|---|---|---|
| `ConfigMenuError` | enum | `Sources/greendot/AppDelegate+Config.swift:5` |
| `AppDelegate` | class | `Sources/greendot/AppDelegate.swift:5` |
| `AppEditMenu` | enum | `Sources/greendot/AppEditMenu.swift:5` |
| `BuildInfo` | enum | `Sources/greendot/BuildInfo.swift:4` |
| `AboutPanel` | enum | `Sources/greendot/BuildInfo.swift:22` |
| `ComponentPicker` | class | `Sources/greendot/ComponentPicker.swift:5` |
| `ComponentSelectionSummary` | struct | `Sources/greendot/ComponentSelectionIndex.swift:3` |
| `ComponentSelectionIndex` | struct | `Sources/greendot/ComponentSelectionIndex.swift:8` |
| `LaunchAtLogin` | enum | `Sources/greendot/LaunchAtLogin.swift:4` |
| `StatusMenuState` | struct | `Sources/greendot/MenuBuilder.swift:4` |
| `StatusMenuState.Content` | struct | `Sources/greendot/MenuBuilder.swift:5` |
| `StatusMenuHandlers` | struct | `Sources/greendot/MenuBuilder.swift:20` |
| `MenuBuilder` | class | `Sources/greendot/MenuBuilder.swift:35` |
| `TargetAction` | class | `Sources/greendot/MenuBuilder.swift:205` |
| `MenuClickOpener` | class | `Sources/greendot/MenuClickOpener.swift:6` |
| `MenuCommands` | enum | `Sources/greendot/MenuCommands.swift:3` |
| `KeyablePanel` | class | `Sources/greendot/PagePanelController.swift:4` |
| `PagePanelController` | class | `Sources/greendot/PagePanelController.swift:10` |
| `StatusDot` | enum | `Sources/greendot/StatusDot.swift:5` |
| `StatusDot.Key` | struct | `Sources/greendot/StatusDot.swift:6` |
| `ScheduledMainActorWork` | typealias | `Sources/greendot/StatusMenuController.swift:4` |
| `StatusMenuController` | class | `Sources/greendot/StatusMenuController.swift:7` |
| `StatusPageEditor` | class | `Sources/greendot/StatusPageEditor.swift:5` |
| `UITestDriver` | enum | `Sources/greendot/UITestDriver.swift:4` |
| `URLOpener` | enum | `Sources/greendot/URLOpener.swift:4` |

### Toast model and delivery

| Definition | Kind | Source |
|---|---|---|
| `Toast` | struct | `Sources/StatusCore/ToastPolicy.swift:3` |
| `ToastPolicy` | enum | `Sources/StatusCore/ToastPolicy.swift:26` |
| `NetworkToast` | enum | `Sources/StatusCore/ToastPolicy.swift:54` |
| `PersistentToastPresenter` | protocol | `Sources/greendot/PersistentToastPresenter.swift:5` |
| `PanelPersistentToastPresenter` | class | `Sources/greendot/PersistentToastPresenter.swift:15` |
| `Item` | struct | `Sources/greendot/PersistentToastPresenter.swift:53` |
| `PersistentToastLayout` | enum | `Sources/greendot/PersistentToastPresenter.swift:60` |
| `PersistentToastCard` | class | `Sources/greendot/PersistentToastPresenter.swift:162` |
| `UserNotificationCenterClient` | protocol | `Sources/greendot/SystemToastDelivery.swift:5` |
| `LiveUserNotificationCenterClient` | class | `Sources/greendot/SystemToastDelivery.swift:22` |
| `ToastScheduler` | typealias | `Sources/greendot/SystemToastDelivery.swift:69` |
| `SystemToastDelivery` | class | `Sources/greendot/SystemToastDelivery.swift:74` |
| `ToastDelivery` | protocol | `Sources/greendot/ToastDelivery.swift:4` |

### Shared test support

| Definition | Kind | Source |
|---|---|---|
| `BenchmarkFixtures` | enum | `Tests/TestSupport/BenchmarkFixtures.swift:4` |
| `ControllableHTTPClient` | class | `Tests/TestSupport/ControllableHTTPClient.swift:4` |
| `ControllableLock` | class | `Tests/TestSupport/ControllableLock.swift:3` |
| `FakeNetworkReachability` | class | `Tests/TestSupport/FakeNetworkReachability.swift:5` |
| `MapHTTPClient` | struct | `Tests/TestSupport/HTTPClientDoubles.swift:4` |
| `DelayHTTPClient` | struct | `Tests/TestSupport/HTTPClientDoubles.swift:20` |
| `RecordingHTTPClient` | class | `Tests/TestSupport/HTTPClientDoubles.swift:35` |
| `RecordedURLs` | class | `Tests/TestSupport/HTTPClientDoubles.swift:51` |
| `HostOutageHTTPClient` | class | `Tests/TestSupport/HostOutageHTTPClient.swift:5` |

### Local test helpers and measurements

| Definition | Kind | Source |
|---|---|---|
| `NetworkReachabilityTests.Seed` | struct | `Tests/StatusCoreTests/NetworkReachabilityTests.swift:108` |
| `FailIfCalledHTTPClient` | struct | `Tests/StatusCoreTests/NetworkReachabilityTests.swift:132` |
| `SwitchableHTTPClient` | class | `Tests/StatusCoreTests/NetworkToastTests.swift:268` |
| `ConcurrencyProbeHTTPClient` | class | `Tests/StatusCoreTests/PollPerformanceTests.swift:232` |
| `FailingHTTPClient` | struct | `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:354` |
| `CancellationHTTPClient` | struct | `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:360` |
| `LocatedHTTPClient` | struct | `Tests/StatusCoreTests/RssRedirectTests.swift:225` |
| `StateFileFixtures` | enum | `Tests/StatusCoreTests/StateFileSplitTests.swift:363` |
| `AppDelegateConfigMenuTests.Seeded` | struct | `Tests/greendotTests/AppDelegateConfigMenuTests.swift:9` |
| `AppDelegateNetworkToastTests.Seed` | struct | `Tests/greendotTests/AppDelegateNetworkToastTests.swift:144` |
| `FailIfCalledHTTPClient` | struct | `Tests/greendotTests/AppDelegateNetworkToastTests.swift:187` |
| `SequenceHTTPClient` | class | `Tests/greendotTests/AppDelegateRefreshErrorTests.swift:211` |
| `AppDelegateReloadToastTests.Fixture` | struct | `Tests/greendotTests/AppDelegateReloadTests.swift:219` |
| `AppDelegateToastClearTests.Seed` | struct | `Tests/greendotTests/AppDelegateToastClearTests.swift:78` |
| `InMemoryToastDelivery` | class | `Tests/greendotTests/InMemoryToastDelivery.swift:5` |
| `WeakReference` | class | `Tests/greendotTests/PanelLifecycleTests.swift:324` |
| `CancellationHTTPClient` | struct | `Tests/greendotTests/PanelLifecycleTests.swift:353` |
| `ParseMetrics` | struct | `Tests/greendotTests/PerformanceHarnessMetrics.swift:6` |
| `PollMetrics` | struct | `Tests/greendotTests/PerformanceHarnessMetrics.swift:12` |
| `PollPageMetrics` | struct | `Tests/greendotTests/PerformanceHarnessMetrics.swift:18` |
| `MenuMetrics` | struct | `Tests/greendotTests/PerformanceHarnessMetrics.swift:24` |
| `RemainingMetrics` | struct | `Tests/greendotTests/PerformanceHarnessMetrics.swift:30` |
| `BenchmarkRunMetrics` | struct | `Tests/greendotTests/PerformanceHarnessMetrics.swift:37` |
| `PendingSaveGate` | actor | `Tests/greendotTests/StatusPageEditorTests.swift:328` |
| `StatusPageEditorToastTests.Seed` | struct | `Tests/greendotTests/StatusPageEditorToastTests.swift:185` |
| `RecordingPersistentToastPresenter` | class | `Tests/greendotTests/ToastDeliveryDoubles.swift:5` |
| `RecordingUserNotificationCenter` | class | `Tests/greendotTests/ToastDeliveryDoubles.swift:24` |

### Core test suites

| Definition | Kind | Source |
|---|---|---|
| `AggregatorTests` | class | `Tests/StatusCoreTests/AggregatorTests.swift:4` |
| `AppleParserTests` | class | `Tests/StatusCoreTests/AppleParserTests.swift:4` |
| `AwsParserTests` | class | `Tests/StatusCoreTests/AwsParserTests.swift:4` |
| `AwsProbeTests` | class | `Tests/StatusCoreTests/AwsProbeTests.swift:5` |
| `ChangedOnDiskTests` | class | `Tests/StatusCoreTests/ChangedOnDiskTests.swift:6` |
| `ComponentToggleTests` | class | `Tests/StatusCoreTests/ComponentToggleTests.swift:5` |
| `ComponentTreeSeverityTests` | class | `Tests/StatusCoreTests/ComponentTreeSeverityTests.swift:4` |
| `ConfigEncodingTests` | class | `Tests/StatusCoreTests/ConfigEncodingTests.swift:4` |
| `FlashdutyProbeTests` | class | `Tests/StatusCoreTests/FlashdutyProbeTests.swift:5` |
| `GoogleParserTests` | class | `Tests/StatusCoreTests/GoogleParserTests.swift:4` |
| `GreyPulseTests` | class | `Tests/StatusCoreTests/GreyPulseTests.swift:4` |
| `HTTPAuthTests` | class | `Tests/StatusCoreTests/HTTPAuthTests.swift:4` |
| `HerokuParserTests` | class | `Tests/StatusCoreTests/HerokuParserTests.swift:4` |
| `IcingaParserTests` | class | `Tests/StatusCoreTests/IcingaParserTests.swift:4` |
| `IcingaProbeTests` | class | `Tests/StatusCoreTests/IcingaProbeTests.swift:5` |
| `IncidentioParserTests` | class | `Tests/StatusCoreTests/IncidentioParserTests.swift:4` |
| `LegacyFieldTests` | class | `Tests/StatusCoreTests/LegacyFieldTests.swift:4` |
| `MonitorFirstRunTests` | class | `Tests/StatusCoreTests/MonitorFirstRunTests.swift:6` |
| `MonitorRefreshTransactionTests` | class | `Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift:5` |
| `NetworkReachabilityTests` | class | `Tests/StatusCoreTests/NetworkReachabilityTests.swift:5` |
| `NetworkToastTests` | class | `Tests/StatusCoreTests/NetworkToastTests.swift:5` |
| `OktaParserTests` | class | `Tests/StatusCoreTests/OktaParserTests.swift:4` |
| `OktaProbeTests` | class | `Tests/StatusCoreTests/OktaProbeTests.swift:5` |
| `PageStoreValidationTests` | class | `Tests/StatusCoreTests/PageStoreValidationTests.swift:4` |
| `ParserTests` | class | `Tests/StatusCoreTests/ParserTests.swift:4` |
| `PollConfirmationTests` | class | `Tests/StatusCoreTests/PollConfirmationTests.swift:5` |
| `PollPerformanceTests` | class | `Tests/StatusCoreTests/PollPerformanceTests.swift:5` |
| `PollSecondsTests` | class | `Tests/StatusCoreTests/PollSecondsTests.swift:5` |
| `ProbeAndMonitorTests` | class | `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:5` |
| `RssHtmlDiscoveryTests` | class | `Tests/StatusCoreTests/RssHtmlDiscoveryTests.swift:5` |
| `RssHubProbeTests` | class | `Tests/StatusCoreTests/RssHubProbeTests.swift:5` |
| `RssParserCategoryTests` | class | `Tests/StatusCoreTests/RssParserCategoryTests.swift:4` |
| `RssParserGuardTests` | class | `Tests/StatusCoreTests/RssParserGuardTests.swift:5` |
| `RssParserTests` | class | `Tests/StatusCoreTests/RssParserTests.swift:4` |
| `RssPersistTests` | class | `Tests/StatusCoreTests/RssPersistTests.swift:5` |
| `RssProbeTests` | class | `Tests/StatusCoreTests/RssProbeTests.swift:5` |
| `RssRedirectTests` | class | `Tests/StatusCoreTests/RssRedirectTests.swift:5` |
| `SaaSPlatformProbeTests` | class | `Tests/StatusCoreTests/SaaSPlatformProbeTests.swift:5` |
| `SalesforceParserTests` | class | `Tests/StatusCoreTests/SalesforceParserTests.swift:4` |
| `SalesforceProbeTests` | class | `Tests/StatusCoreTests/SalesforceProbeTests.swift:5` |
| `SlackParserTests` | class | `Tests/StatusCoreTests/SlackParserTests.swift:4` |
| `StateFileSplitTests` | class | `Tests/StatusCoreTests/StateFileSplitTests.swift:4` |
| `StateFileLaunchFlagTests` | class | `Tests/StatusCoreTests/StateFileSplitTests.swift:270` |
| `StatusioParserTests` | class | `Tests/StatusCoreTests/StatusioParserTests.swift:4` |
| `ToastPolicyTests` | class | `Tests/StatusCoreTests/ToastPolicyTests.swift:4` |

### Desktop test suites

| Definition | Kind | Source |
|---|---|---|
| `AboutTests` | class | `Tests/greendotTests/AboutTests.swift:5` |
| `AppDelegateConfigMenuTests` | class | `Tests/greendotTests/AppDelegateConfigMenuTests.swift:8` |
| `AppDelegateNetworkToastTests` | class | `Tests/greendotTests/AppDelegateNetworkToastTests.swift:8` |
| `AppDelegateRefreshErrorTests` | class | `Tests/greendotTests/AppDelegateRefreshErrorTests.swift:8` |
| `AppDelegateReloadFirstRunTests` | class | `Tests/greendotTests/AppDelegateReloadFirstRunTests.swift:8` |
| `AppDelegateReloadRaceTests` | class | `Tests/greendotTests/AppDelegateReloadRaceTests.swift:8` |
| `AppDelegateReloadTests` | class | `Tests/greendotTests/AppDelegateReloadTests.swift:8` |
| `AppDelegateReloadToastTests` | class | `Tests/greendotTests/AppDelegateReloadTests.swift:218` |
| `AppDelegateFailedReloadTests` | class | `Tests/greendotTests/AppDelegateReloadTests.swift:352` |
| `AppDelegateToastClearTests` | class | `Tests/greendotTests/AppDelegateToastClearTests.swift:7` |
| `ComponentPickerStateTests` | class | `Tests/greendotTests/ComponentPickerStateTests.swift:8` |
| `ComponentSelectionIndexTests` | class | `Tests/greendotTests/ComponentSelectionIndexTests.swift:5` |
| `CopyrightTests` | class | `Tests/greendotTests/CopyrightTests.swift:5` |
| `EmptyComponentMenuTests` | class | `Tests/greendotTests/EmptyComponentMenuTests.swift:7` |
| `MenuBuilderTests` | class | `Tests/greendotTests/MenuBuilderTests.swift:8` |
| `PanelLifecycleTests` | class | `Tests/greendotTests/PanelLifecycleTests.swift:8` |
| `PanelReleaseTests` | class | `Tests/greendotTests/PanelLifecycleTests.swift:299` |
| `PerformanceHarnessTests` | class | `Tests/greendotTests/PerformanceHarnessTests.swift:10` |
| `PollIntervalTests` | class | `Tests/greendotTests/PollIntervalTests.swift:4` |
| `SilentToastTests` | class | `Tests/greendotTests/SilentToastTests.swift:8` |
| `StatusMenuControllerTests` | class | `Tests/greendotTests/StatusMenuControllerTests.swift:7` |
| `StatusPageEditorTests` | class | `Tests/greendotTests/StatusPageEditorTests.swift:8` |
| `StatusPageEditorToastTests` | class | `Tests/greendotTests/StatusPageEditorToastTests.swift:8` |
| `SystemToastDeliveryTests` | class | `Tests/greendotTests/SystemToastDeliveryTests.swift:8` |
| `URLOpenerTests` | class | `Tests/greendotTests/URLOpenerTests.swift:4` |

### UI test suite

| Definition | Kind | Source |
|---|---|---|
| `GreenDotUITests` | class | `UITests/GreenDotUITests/GreenDotUITests.swift:7` |

## Out of Scope / Flagged for Review

- **Compiler and runtime verification:** not performed. Tool availability is recorded in the pre-flight observations. The build requires macOS and Xcode. Sources: `README.md:30`, `Makefile:12`.
- **Independent verification:** not performed in this analysis stage. Every machine-readable finding remains `verified: false`. Neither observation authorizes an automatic change.
- **Weak typing and parser correctness:** this report does not propose replacing provider dictionaries with a universal payload type. Provider shape checks differ and must remain. Sources: `Sources/StatusCore/StatuspageParser.swift:6`, `Sources/StatusCore/FlashdutyParser.swift:5`, `Sources/StatusCore/IcingaParser.swift:38`.
- **Security and accessibility audit:** this domain review is not a security or accessibility certification. Keep the safeguards cited in Recommendations. Examples: `Sources/StatusCore/HTTPClient.swift:16`, `Sources/greendot/PersistentToastPresenter.swift:209`.
- **Code duplication outside type definitions:** similar parser functions and scalar helpers require a separate behavior review before reuse. This report makes no removal recommendation. Sources: `Sources/StatusCore/IcingaParser.swift:107`, `Sources/StatusCore/StatusioParser.swift:50`, `Sources/StatusCore/SalesforceParser.swift:67`.

## Machine-Readable Findings

```json
{
  "findings": [
    {
      "id": "type-consolidation-001",
      "file": "Tests/StatusCoreTests/ProbeAndMonitorTests.swift",
      "line": 360,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "KEEP SEPARATE",
      "detail": "The cancellation-client bodies at Tests/StatusCoreTests/ProbeAndMonitorTests.swift:360 and Tests/greendotTests/PanelLifecycleTests.swift:353 are identical. Keep both five-line local definitions because sharing adds a public test API for little reduction.",
      "verified": false
    },
    {
      "id": "type-consolidation-002",
      "file": "Tests/StatusCoreTests/NetworkReachabilityTests.swift",
      "line": 132,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "KEEP SEPARATE",
      "detail": "FailIfCalledHTTPClient is duplicated at Tests/StatusCoreTests/NetworkReachabilityTests.swift:132 and Tests/greendotTests/AppDelegateNetworkToastTests.swift:187. Keep both six-line local definitions and preserve their XCTFail assertions.",
      "verified": false
    }
  ]
}
```
