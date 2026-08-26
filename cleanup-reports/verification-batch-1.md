# Independent verification batch 1

Read-only adversarial verification of the 18 supplied findings. I inspected the current source and tests, used targeted `rg`, `cloc`, and `git` history, and ran the existing test suite. `swift test --skip-build` passed 150 tests with 1 skipped and 0 failures. A Swift 6 language-mode build was also run; it fails on the current concurrency diagnostics, which is direct evidence for the typing findings and is not treated as a product-test failure.

## Findings

### dedup-001 — SURVIVES

Evidence: `Sources/greendot/MenuBuilder.swift:185-191` has the four-case `Severity` to display-text switch. `Sources/StatusCore/ToastPolicy.swift:37-44` has the same four cases, preceded by the separate `isUnreachable` guard. `Sources/StatusCore/StatuspalParser.swift:45-50` repeats the mapping and changes only yellow scheduled status to `Maintenance`. No `Severity.displayText` exists elsewhere. The duplicate mapping and the provider exception are direct.

Corrected narrow claim: The baseline four-case text mapping is duplicated; `ToastPolicy` also has an unreachable-snapshot override, and Statuspal needs its scheduled-maintenance override preserved.

Severity: LOW. Confidence: HIGH. Recommendation: Extract the baseline mapping to `Severity` or a shared formatter, while retaining both the unreachable guard and Statuspal's scheduled exception. Safe to mark the original finding verified: yes.

### dedup-002 — SURVIVES

Evidence: `Tests/StatusCoreTests/PollPerformanceTests.swift:228-242` and `Tests/greendotTests/PerformanceHarnessTests.swift:333-348` contain the same `page(host:name:provider:)` fixture body. Both files define `private static let delayNs: UInt64 = 80_000_000` at lines 5 and 10. `rg` finds these helpers and doubles only in the two test files; the production target does not use them.

Corrected narrow claim: The page fixture and the 80 ms nanosecond delay constant are duplicated between two test targets and can be moved to shared test support.

Severity: LOW. Confidence: HIGH. Recommendation: Move the fixture and shared delay constant to `Tests/TestSupport`, then import that support from both test targets. Safe to mark the original finding verified: yes.

### dedup-003 — SURVIVES

Evidence: `Tests/StatusCoreTests/PollPerformanceTests.swift:282-287` and `Tests/greendotTests/PerformanceHarnessTests.swift:392-397` are identical `private extension Duration` implementations, including the seconds/attoseconds conversion. `rg` finds no third definition.

Corrected narrow claim: The same private `Duration.milliseconds` extension is defined once in each test target.

Severity: LOW. Confidence: HIGH. Recommendation: Put one public/internal shared test-support extension in `Tests/TestSupport`. Safe to mark the original finding verified: yes.

### dedup-005 — SURVIVES

Evidence: `Tests/greendotTests/StatusPageEditorTests.swift:250-269` defines separate `field` and `button` helpers. Each checks an accessibility identifier, recursively walks `view.subviews`, and returns the typed match. Their only substantive difference is the target cast (`NSTextField` versus `NSButton`).

Corrected narrow claim: The two test helpers duplicate the same recursive identifier traversal and differ only in result type.

Severity: LOW. Confidence: HIGH. Recommendation: Add one generic `findView` traversal and keep typed wrappers only if call-site readability requires them. Safe to mark the original finding verified: yes.

### defensive-001 — SURVIVES

Evidence: `Sources/StatusCore/Models.swift:123-130` filters `snapshot?.components`, computes leaves, and never reads `snapshot.overall` except for the unreachable flag. `Aggregator.fromSeverities` returns green for an empty array at `Sources/StatusCore/Severity.swift:8-15`. `Monitor.barSeverity` and `Monitor.pollToast` consume `WatchedPage.displaySeverity` at `Sources/StatusCore/Monitor.swift:170-183` and `325-361`. Existing tests explicitly assert that disabling a red component or all components changes display severity to green (`Tests/StatusCoreTests/ComponentToggleTests.swift:5-14,49-61`). Therefore a non-unreachable red page snapshot with no enabled red leaves can display green and fail the display-severity transition used for a toast.

Corrected narrow claim: `displaySeverity` intentionally represents enabled component leaves, but it conflates missing snapshot and all-disabled components with green and ignores page-level `snapshot.overall`; that policy can hide a page-level outage and suppress a toast.

Severity: HIGH. Confidence: HIGH. Recommendation: Define separate absent-data/all-disabled/page-overall states or an explicit policy, and add tests for a red page-level snapshot with empty and disabled component selections. Safe to mark the original finding verified: yes.

### defensive-006 — SURVIVES

Evidence: `Sources/greendot/AppDelegate.swift:114-122` performs first-run OpenAI seeding and ends with `try? await monitor.add(url:name:)`. `Monitor.add` probes and then persists through `commitWatchedPageMutation` (`Sources/StatusCore/Monitor.swift:54-68`), so probe and save errors are throwable. The seed task proceeds to polling, but no error from the seed call is reported; an empty store can therefore remain empty without an explanation.

Corrected narrow claim: Optional first-run seeding intentionally does not block launch, but its probe and persistence errors are completely discarded.

Severity: MEDIUM. Confidence: HIGH. Recommendation: Log a non-fatal diagnostic or expose a dismissible seed failure while preserving non-blocking startup. Safe to mark the original finding verified: yes.

### defensive-010 — SURVIVES

Evidence: `Sources/greendot/AppDelegate.swift:55-61` converts `GREENDOT_POLL_SECONDS` with `Double.init` and passes the result directly to `Timer.scheduledTimer`; only a failed parse falls back to 60. A direct Swift check on this toolchain produced `0.0`, `-1.0`, `nan`, and `inf` for the corresponding strings, with `isFinite` false for NaN/infinity and positivity false for zero/negative values. No finite-positive validation exists.

Corrected narrow claim: The environment value accepts parsed zero, negative, NaN, and infinity values instead of treating them as invalid and using the 60-second fallback.

Severity: MEDIUM. Confidence: HIGH. Recommendation: Accept only finite values greater than zero; otherwise use 60 seconds. Safe to mark the original finding verified: yes.

### defensive-014 — SURVIVES

Evidence: `Sources/StatusCore/ProviderProbe.swift:222-231` initializes `statuspalRegex` as an optional with `try? NSRegularExpression(...)`, then returns nil from `extractStatuspalSubdomain` when the regex is nil. A future invalid source-code pattern therefore fails closed without an error or log and disables HTML-based Statuspal discovery. The existing test only covers the currently valid pattern (`Tests/StatusCoreTests/PollPerformanceTests.swift:133-140`).

Corrected narrow claim: A programmer error in the static Statuspal regex literal is silently converted to a nil extractor; the current valid literal compiles and tests successfully.

Severity: MEDIUM. Confidence: HIGH. Recommendation: Use explicit one-time checked initialization with a diagnostic/fallback policy, avoiding an unreviewed force unwrap. Safe to mark the original finding verified: yes.

### defensive-015 — SURVIVES

Evidence: `Sources/StatusCore/ProviderProbe.swift:135-160` maps every response whose status is not exactly 200 to `.miss` at line 145. `probeHit` records `.miss` as `sawHTTP` and returns `.unsupported` whenever any HTTP response was observed (`:45-55,89-103`). Thus a 5xx or 429 response can produce `ProbeError.unsupported`, including during `Monitor.add`/`edit`, rather than `ProbeError.unreachable`; 404/provider misses use the same path.

Corrected narrow claim: The probe needs to distinguish provider misses such as 404 from server/rate-limit responses such as 5xx/429; all currently become HTTP misses and can end as unsupported.

Severity: MEDIUM. Confidence: HIGH. Recommendation: Preserve 404 and format misses, but classify 5xx/429 (and define the treatment of other non-2xx statuses) as network/unreachable failures with tests. Safe to mark the original finding verified: yes.

### loc-001 — SURVIVES

Evidence: `cloc Sources/StatusCore/Monitor.swift` reports 352 code lines. The class uses state and transition locks (`Sources/StatusCore/Monitor.swift:5-12,373-377`), persistent mutations via `commitWatchedPageMutation` (`:243-267`), asynchronous task-group polling and result reconciliation (`:141-168,269-336`), and display/toast logic (`:170-183,339-361`). These concerns are all in one production type.

Corrected narrow claim: The 352-code-line `Monitor` combines synchronization, store mutation, asynchronous polling/merge, and status/toast policy/presentation-facing calculations.

Severity: MEDIUM. Confidence: HIGH. Recommendation: Consider extracting store/state transitions, polling orchestration, and status/toast policy behind focused types, with characterization tests before moving behavior. Safe to mark the original finding verified: yes.

### loc-002 — SURVIVES

Evidence: `Sources/StatusCore/ProviderProbe.swift:34-103` is `probeHit`; `cloc` on its body (`:41-102`) reports 57 code lines. It owns the `sawHTTP`/`sawNetworkError` flags, nested standard-provider attempts (`:58-87`), provider-order loop (`:89-98`), Statuspal delegation (`:78-86`), and final unreachable/unsupported choice (`:99-102`).

Corrected narrow claim: The 57-code-line `probeHit` orchestrator combines provider ordering, standard attempts, Statuspal discovery delegation, shared network flags, and final error selection.

Severity: MEDIUM. Confidence: HIGH. Recommendation: Separate attempt orchestration and error classification from provider discovery, preserving the existing fallback order with tests. Safe to mark the original finding verified: yes.

### types-001 — SURVIVES

Evidence: `ParserError` is declared in `Sources/StatusCore/StatuspageParser.swift:3-13`, while `Sources/StatusCore/InstatusParser.swift:3-8` and `Sources/StatusCore/StatuspalParser.swift:3-8` both throw `ParserError.notThisProvider`. `rg` finds no separate shared error file. The enum and its cases can be moved unchanged within the target.

Corrected narrow claim: The shared internal parser error is physically owned by the Statuspage parser file even though all three provider parsers use it.

Severity: LOW. Confidence: HIGH. Recommendation: Move the unchanged enum to `ParserError.swift` or a shared provider-parsing file and run parser tests. Safe to mark the original finding verified: yes.

### types-002 — SURVIVES

Evidence: `Sources/StatusCore/HTTPClient.swift:21-83` defines public `MapHTTPClient`, `DelayHTTPClient`, `RecordingHTTPClient`, and private `RecordedURLs`. `rg` shows their call sites only under `Tests`; the `Sources` call sites use only the `HTTPClient` protocol, `URLSessionHTTPClient`, and `DirectoryHTTPClient` (`Sources/greendot/AppDelegate.swift:25-29` and `Sources/StatusCore/DirectoryHTTPClient.swift`).

Corrected narrow claim: Three public in-memory HTTP test doubles and their recording helper are shipped in the production StatusCore target even though all observed consumers are tests.

Severity: LOW. Confidence: HIGH. Recommendation: Move the doubles and `RecordedURLs` into `Tests/TestSupport`, add the required imports, and retain the production protocol and real/fixture-backed clients. Safe to mark the original finding verified: yes.

### typing-005 — SURVIVES

Evidence: `Sources/greendot/StatusDot.swift:10-25` has a static lock plus mutable static `[Key: NSImage]` cache. A fresh `swift build -Xswiftc -swift-version -Xswiftc 6` reports an error at line 11: “static property 'cache' is not concurrency-safe because it is nonisolated global shared mutable state,” and the compiler specifically suggests `@MainActor` as one remedy.

Corrected narrow claim: Under Swift 6 concurrency checking, the lock-backed AppKit cache remains a rejected nonisolated mutable global; the external lock does not satisfy the compiler diagnostic.

Severity: HIGH. Confidence: HIGH. Recommendation: Isolate the cache and its access on `MainActor` (or use a reviewed concurrency-safe design) and re-run the strict build. Safe to mark the original finding verified: yes.

### typing-006 — SURVIVES

Evidence: `Sources/greendot/AppDelegate.swift:4-18` has no global-actor annotation, initializes an AppKit `NSAlert` closure as a stored callback, and owns timer callbacks at `:55-69`. Swift 6 build diagnostics report a main-actor-isolated default-value error at line 12 plus non-Sendable `self` captures in the timer `Task`/closures at lines 60 and 65.

Corrected narrow claim: `AppDelegate` has unannotated AppKit state and timer closures that produce the reported Swift 6 default-value and sendability diagnostics; the error callback also needs an explicit actor-aware function type or isolation boundary.

Severity: HIGH. Confidence: HIGH. Recommendation: Mark the class and callback boundary consistently `@MainActor`, then resolve timer task captures without weakening checking. Safe to mark the original finding verified: yes.

### typing-007 — SURVIVES

Evidence: `Sources/greendot/PagePanelController.swift:9-20` has no `@MainActor` annotation while default-initializing `NSTextField` instances. Swift 6 build diagnostics report main-actor-isolated default-value errors at lines 11 and 12 and actor-isolation warnings throughout the window, view, field, and button operations.

Corrected narrow claim: The AppKit panel controller is not explicitly main-actor isolated and currently fails strict Swift 6 initialization checking before its many AppKit accesses are considered safe.

Severity: HIGH. Confidence: HIGH. Recommendation: Mark the controller and its AppKit helper types/main-thread callbacks `@MainActor`, then rebuild in Swift 6 mode. Safe to mark the original finding verified: yes.

### typing-008 — SURVIVES

Evidence: At baseline `310032b`, `ComponentPicker.swift` and
`UITestDriver.swift` contained AppKit state and methods with no explicit
`@MainActor` boundary. A fresh strict build reported actor-isolated AppKit
warnings and `ComponentPicker` sendability errors at lines 36/84. At
`UITestDriver` lines 51/63, results from the main-actor-isolated
`accessibilityIdentifier()` call crossed into a nonisolated context. The same
build reported AppKit actor warnings in `AppEditMenu.swift:6`,
`BuildInfo.swift:27-28` (`AboutPanel.show`), and `MenuClickOpener.swift:69`.

Corrected narrow claim: All listed helpers lack an explicit boundary; `ComponentPicker` and `UITestDriver` produce hard Swift 6 diagnostics, while `AppEditMenu`, `AboutPanel.show`, and `MenuClickOpener` at minimum produce actor-isolation warnings that should be resolved rather than suppressed.

Severity: HIGH. Confidence: HIGH. Recommendation: Establish one consistent `@MainActor` boundary for these AppKit helpers and make notification/event callback types actor-aware, then require a clean Swift 6 build. Safe to mark the original finding verified: yes.

### legacy-001 — PARTIAL

Evidence: Current `Sources/greendot/AppDelegate.swift:169-188` retains `previous`, closes it, defers `editor.show()` to `DispatchQueue.main.async`, and keeps `previous` alive through the deferred closure. Commit `889a31d` is explicit: “Crash when opening Edit for a second status page”; its message says destroying the previous window in the status-item menu action over-released AppKit view arrays, and the diff introduces the close/deferred-show workaround. The current lifecycle tests exercise replacement behavior (`Tests/greendotTests/PanelLifecycleTests.swift:8-44` and `Tests/greendotTests/StatusPageEditorTests.swift:152-190`), but they instantiate panels/editors directly and do not invoke the private `AppDelegate.openEditor` path or its identity guard.

Corrected narrow claim: Git history directly supports the SIGSEGV rationale and current tests cover analogous replacement/deferred-lifetime behavior, but no current test directly covers the complete AppDelegate workaround and its `self.editor === editor` guard.

Severity: MEDIUM. Confidence: HIGH. Recommendation: Keep the workaround documented; add an AppDelegate-level lifecycle test or otherwise cover the exact status-menu replacement path before calling it fully verified. Safe to mark the original finding verified: no.

```json
[
  {"id":"dedup-001","disposition":"SURVIVES","evidence":"MenuBuilder.swift:185-191 and ToastPolicy.swift:37-44 duplicate the four Severity display strings; StatuspalParser.swift:45-50 preserves a scheduled-maintenance exception.","corrected_claim":"Baseline mapping is duplicated, with ToastPolicy unreachable handling and Statuspal scheduled handling kept separate.","severity":"LOW","confidence":"HIGH","recommendation":"Extract shared baseline text mapping and retain provider exceptions.","verified":true},
  {"id":"dedup-002","disposition":"SURVIVES","evidence":"PollPerformanceTests.swift:228-242 and PerformanceHarnessTests.swift:333-348 have the same page fixture; both define delayNs as 80_000_000.","corrected_claim":"The page fixture and delay constant are duplicated across two test targets.","severity":"LOW","confidence":"HIGH","recommendation":"Move them to Tests/TestSupport and import it from both targets.","verified":true},
  {"id":"dedup-003","disposition":"SURVIVES","evidence":"Both test files contain the identical Duration.milliseconds extension at PollPerformanceTests.swift:282-287 and PerformanceHarnessTests.swift:392-397.","corrected_claim":"The milliseconds extension is duplicated once per test target.","severity":"LOW","confidence":"HIGH","recommendation":"Keep one shared test-support extension.","verified":true},
  {"id":"dedup-005","disposition":"SURVIVES","evidence":"StatusPageEditorTests.swift:250-269 has two recursive accessibility-id traversals differing only by NSTextField versus NSButton cast.","corrected_claim":"Field and button helpers duplicate traversal logic and can share a generic finder.","severity":"LOW","confidence":"HIGH","recommendation":"Add a generic findView traversal with typed wrappers as needed.","verified":true},
  {"id":"defensive-001","disposition":"SURVIVES","evidence":"Models.swift:127-130 derives displaySeverity only from enabled component leaves; Aggregator returns green for []; Monitor uses that value for bar and toast transitions. Existing tests assert disabled red becomes green.","corrected_claim":"Missing snapshot/all-disabled components become green and page-level overall is ignored, which can hide an outage and suppress a toast.","severity":"HIGH","confidence":"HIGH","recommendation":"Define absent-data/all-disabled/page-overall policy and add red-outage regression tests.","verified":true},
  {"id":"defensive-006","disposition":"SURVIVES","evidence":"AppDelegate.swift:114-122 calls monitor.add with try? during optional first-run seed; Monitor.add probes and saves through throwable operations.","corrected_claim":"Seed probe and persistence failures are discarded while startup remains non-blocking.","severity":"MEDIUM","confidence":"HIGH","recommendation":"Log or surface a non-fatal seed failure.","verified":true},
  {"id":"defensive-010","disposition":"SURVIVES","evidence":"AppDelegate.swift:55-61 validates only Double parsing before scheduling a Timer; direct Swift parsing accepts 0, negative, NaN, and infinity.","corrected_claim":"Parsed non-finite and non-positive poll intervals bypass the 60-second fallback.","severity":"MEDIUM","confidence":"HIGH","recommendation":"Require finite positive values, else use 60.","verified":true},
  {"id":"defensive-014","disposition":"SURVIVES","evidence":"ProviderProbe.swift:222-231 uses try? for an optional static regex and returns nil when initialization fails.","corrected_claim":"A malformed source regex silently disables HTML Statuspal extraction.","severity":"MEDIUM","confidence":"HIGH","recommendation":"Use explicit checked initialization with diagnostics/fallback, not an unreviewed force unwrap.","verified":true},
  {"id":"defensive-015","disposition":"SURVIVES","evidence":"ProviderProbe.swift:143-159 maps every status other than 200 to miss; sawHTTP then drives final unsupported at :99-103.","corrected_claim":"5xx/429 are treated like 404/provider misses and can end as unsupported.","severity":"MEDIUM","confidence":"HIGH","recommendation":"Classify server/rate-limit responses separately from provider misses.","verified":true},
  {"id":"loc-001","disposition":"SURVIVES","evidence":"cloc reports 352 code lines in Monitor.swift; the file contains locks, store commits, task-group polling/merge, and display/toast logic.","corrected_claim":"Monitor combines four stated production concerns in 352 code lines.","severity":"MEDIUM","confidence":"HIGH","recommendation":"Consider extracting state/store, poll/merge, and presentation policy types.","verified":true},
  {"id":"loc-002","disposition":"SURVIVES","evidence":"cloc reports 57 code lines for ProviderProbe.swift:41-102; that body contains flags, nested attempts, provider order, Statuspal delegation, and final errors.","corrected_claim":"probeHit is a 57-code-line orchestration/error-selection function with the stated responsibilities.","severity":"MEDIUM","confidence":"HIGH","recommendation":"Separate provider attempts/discovery from orchestration and error classification.","verified":true},
  {"id":"types-001","disposition":"SURVIVES","evidence":"ParserError is declared in StatuspageParser.swift:3-13 and thrown by InstatusParser.swift:8 and StatuspalParser.swift:7.","corrected_claim":"A shared parser error is located in the Statuspage parser file despite use by all providers.","severity":"LOW","confidence":"HIGH","recommendation":"Move the unchanged enum to shared parser support.","verified":true},
  {"id":"types-002","disposition":"SURVIVES","evidence":"HTTPClient.swift:21-83 defines three public test doubles and RecordedURLs; rg finds consumers only under Tests, while production uses protocol/real/fixture clients.","corrected_claim":"In-memory test doubles are shipped in production despite test-only consumers.","severity":"LOW","confidence":"HIGH","recommendation":"Move doubles and recorder to Tests/TestSupport.","verified":true},
  {"id":"typing-005","disposition":"SURVIVES","evidence":"StatusDot.swift:11 has mutable static cache; Swift 6 build reports nonisolated global shared mutable state at that line.","corrected_claim":"The lock-backed AppKit cache is still rejected by strict Swift 6 concurrency checking.","severity":"HIGH","confidence":"HIGH","recommendation":"Isolate cache access on MainActor or use a reviewed safe design.","verified":true},
  {"id":"typing-006","disposition":"SURVIVES","evidence":"AppDelegate.swift:12 and timer closures at :60/:65 produce Swift 6 main-actor default-value and non-Sendable self-capture diagnostics.","corrected_claim":"AppDelegate needs explicit actor isolation and an actor-aware callback type.","severity":"HIGH","confidence":"HIGH","recommendation":"Mark class/callback boundary MainActor and resolve timer captures.","verified":true},
  {"id":"typing-007","disposition":"SURVIVES","evidence":"PagePanelController.swift:11-12 default-initializes AppKit controls without MainActor; Swift 6 reports errors there and warnings throughout AppKit access.","corrected_claim":"The panel controller lacks required MainActor isolation under strict Swift 6.","severity":"HIGH","confidence":"HIGH","recommendation":"Mark controller and AppKit helpers MainActor and rebuild strictly.","verified":true},
  {"id":"typing-008","disposition":"SURVIVES","evidence":"At baseline 310032b, strict build reports ComponentPicker sendability/actor diagnostics, UITestDriver accessibilityIdentifier results crossing a main-actor boundary, and AppEditMenu, BuildInfo.AboutPanel.show, and MenuClickOpener actor warnings.","corrected_claim":"All listed AppKit helpers lack explicit boundaries; some are hard errors and the rest produce actor warnings.","severity":"HIGH","confidence":"HIGH","recommendation":"Apply a consistent MainActor boundary and require a clean strict build.","verified":true},
  {"id":"legacy-001","disposition":"PARTIAL","evidence":"AppDelegate.swift:169-188 retains previous and defers show; git commit 889a31d records the SIGSEGV rationale. Current tests cover analogous replacements but not private AppDelegate.openEditor and its identity guard.","corrected_claim":"History and analogous lifecycle tests support the workaround, but exact AppDelegate wiring is not directly tested.","severity":"MEDIUM","confidence":"HIGH","recommendation":"Add an AppDelegate-level replacement test before marking fully verified.","verified":false}
]
```
