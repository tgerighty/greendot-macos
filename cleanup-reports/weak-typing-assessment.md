# Weak Typing Assessment — greendot

Scope: commit 310032b in Sources/StatusCore, Sources/greendot, Tests, and
UITests. The generated Xcode UI-test project, .build, greendot.app, and other
cleanup reports were excluded. This was a read-only review. The requested
checks were run on 2026-08-25.

## Executive Summary

There are 22 findings: 0 HIGH, 6 MEDIUM, and 16 LOW. Confidence is
16 CERTAIN, 5 LIKELY, and 1 UNCERTAIN. Recommendation counts are
6 STRENGTHEN, 4 ISOLATE, 3 REVIEW, and 9 KEEP. All machine findings remain
verified false.

The top three items are:

1. Add a clear MainActor boundary to AppDelegate, PagePanelController, and the
   AppKit helper types. The requested concurrency build passes today, but a
   supplemental Swift 6 language-mode build reports source-owned actor
   diagnostics and sendability risks.
2. Isolate StatusDot.cache. It is mutable shared UI state protected by a lock,
   but Swift 6 reports it as an unsafe global variable.
3. Remove success defaults from PagePanelController component callbacks. A
   missing callback can report success without changing the page.

The three direct low-risk type cleanups are the groupID force unwrap, the
NSOrderedSet bridge, and the test selector dispatch. The JSON parser dictionaries,
AppKit tokens, and notification payloads are real runtime boundaries. They map
to typed domain values at the boundary and should not be replaced by guessed
models.

Evidence:

- swift build -Xswiftc -warn-concurrency: passed, with no concurrency
  diagnostics.
- swift test: passed 150 tests, with 1 skipped and 0 failures.
- swiftlint lint --strict: failed with 11 existing violations. They are
  function/type length, large tuple, line length, identifier, and for-where
  rules; none adds a weak-typing finding here.
- A supplemental swift build -Xswiftc -swift-version -Xswiftc 6 probe failed
  because of source-owned AppKit isolation and sendability diagnostics. The
  SDK-origin text in those diagnostics is recorded below as forward-looking
  evidence, not as a failure of the requested baseline command.
- No as!, try!, @preconcurrency, unsafe, or unowned use was found. Production
  code has no implicitly unwrapped properties. UI-test lifecycle properties
  and literal test URLs are recorded as deliberate test patterns.

## Critical Findings

None. The requested build and the unit test suite pass. No current
type-escape finding is a release-blocking runtime failure.

## Medium Findings

### typing-004 — PageStore uses an unnecessary unchecked Sendable escape

- File: Sources/StatusCore/PageStore.swift:27
- PageStore is a final class with immutable URL properties and no mutable
  instance state. Its load, save, and validation operations use local values.
  The unchecked Sendable declaration therefore hides a contract that can be
  expressed by the type itself. Repository call sites do not use object
  identity.
- Proposed concrete type: make PageStore a value type, struct PageStore:
  Sendable, or prove a final class: Sendable conformance after the Foundation
  URL check.
- Severity: MEDIUM. Confidence: LIKELY. Recommendation: STRENGTHEN.

### typing-005 — StatusDot has mutable global UI state without actor isolation

- File: Sources/greendot/StatusDot.swift:11
- The static NSImage cache is mutable shared state. An NSLock protects the
  accesses, but the Swift 6 probe reports a concurrency-safety error for the
  global cache.
- Proposed concrete type: mark StatusDot and its image/color methods
  MainActor-isolated. All production callers are UI or main-actor toast paths.
  Do not use nonisolated unsafe access as the first fix.
- Severity: MEDIUM. Confidence: CERTAIN. Recommendation: ISOLATE.

### typing-006 — AppDelegate has no explicit MainActor contract

- File: Sources/greendot/AppDelegate.swift:4
- AppDelegate owns NSMenu, timers, panels, alerts, and the poll state. The
  Swift 6 probe reports a main-actor default-value error for the NSAlert
  callback at line 12 and non-Sendable AppDelegate captures in timer Tasks at
  lines 60 and 65.
- Proposed concrete type: annotate AppDelegate MainActor, make presentError a
  MainActor callback over any Error, and make timer tasks enter that actor
  explicitly. Keep network work in Monitor and return typed results to the
  actor.
- Severity: MEDIUM. Confidence: CERTAIN. Recommendation: ISOLATE.

### typing-007 — PagePanelController is an unisolated AppKit controller

- File: Sources/greendot/PagePanelController.swift:9
- The controller creates and mutates NSWindow and NSTextField state. The
  Swift 6 probe reports errors for the field default initialisers at lines 11
  and 12 and further AppKit actor warnings in the initializer and actions.
- Proposed concrete type: mark PagePanelController MainActor-isolated, including
  its NSWindowDelegate methods and save-task completion hop.
- Severity: MEDIUM. Confidence: CERTAIN. Recommendation: ISOLATE.

### typing-008 — Several AppKit helper surfaces lack a global-actor boundary

- File: Sources/greendot/ComponentPicker.swift:4
- The same pattern occurs in UITestDriver.swift:3, AppEditMenu.swift:5,
  BuildInfo.swift:26 for AboutPanel.show, and MenuClickOpener.swift:5.
  These types walk or mutate AppKit view, menu, event, and application state
  from methods that are not explicitly MainActor-isolated. The Swift 6 probe
  reports AppKit actor warnings and ComponentPicker sendability errors.
- Proposed concrete type: mark ComponentPicker, UITestDriver, AppEditMenu,
  AboutPanel.show, and MenuClickOpener MainActor-isolated. Keep pure hash
  parsing in BuildInfo nonisolated if desired.
- Severity: MEDIUM. Confidence: CERTAIN. Recommendation: ISOLATE.

### typing-009 — Monitor relies on unchecked Sendable and an untyped callback

- File: Sources/StatusCore/Monitor.swift:3
- Monitor has mutable configuration and poll revisions. It protects them with
  stateLock and transitionLock, so the current implementation has a deliberate
  synchronization design. However, @unchecked Sendable also covers the
  unannotated onLaunchAtLoginEnable closure at line 13. The compiler cannot
  check that callback's execution context or sendability.
- Proposed concrete type: make Monitor an actor or MainActor-isolated type, or
  retain the locks and change the callback to an explicit MainActor Sendable
  callback invoked through an actor hop. Add tests for the lock invariant
  before choosing the smaller change.
- Severity: MEDIUM. Confidence: LIKELY. Recommendation: REVIEW.

## Low / Debatable Findings

### typing-001 — StatuspageParser force-unwraps a filtered optional

- File: Sources/StatusCore/StatuspageParser.swift:65
- Dictionary grouping uses groupID! after filtering groupID != nil. The filter
  currently guarantees the value, but a later edit can make the filter and
  unwrap diverge.
- Proposed concrete type: compactMap rows to (groupID: String, row: Row), then
  group by the non-optional String key.
- Severity: LOW. Confidence: CERTAIN. Recommendation: STRENGTHEN.

### typing-002 — Statuspal host uniqueness uses an Objective-C bridge

- File: Sources/StatusCore/ProviderProbe.swift:192
- Array(NSOrderedSet(...)) is [Any]. The as? [String] ?? subdomains fallback
  silently keeps duplicates if the bridge fails.
- Proposed concrete type: preserve order with a Set<String> of seen names and a
  [String] result. This removes the untyped bridge and the weak fallback.
- Severity: LOW. Confidence: CERTAIN. Recommendation: STRENGTHEN.

### typing-003 — A menu test uses string selector dispatch

- File: Tests/greendotTests/MenuBuilderTests.swift:187
- The helper casts representedObject to AnyObject, calls
  NSSelectorFromString for invoke, and discards the result. Production stores a
  TargetAction and exposes invoke.
- Proposed concrete type: cast representedObject as? TargetAction and call
  TargetAction.invoke() directly. This is test-only.
- Severity: LOW. Confidence: CERTAIN. Recommendation: STRENGTHEN.

### typing-010 — Component callback optionals default to success

- File: Sources/greendot/PagePanelController.swift:25
- When a page is present, nil onToggleComponent or onSetAll is replaced by a
  closure that returns true. A directly constructed editing panel can therefore
  display a successful toggle without a mutation callback.
- Proposed concrete type: use an editing initializer that requires both
  callbacks, or return false and disable the picker when a callback is absent.
  Keep onRemove optional for add mode.
- Severity: LOW. Confidence: LIKELY. Recommendation: STRENGTHEN.

### typing-011 — Poll outcome uses an optional Error in a tuple

- File: Sources/greendot/AppDelegate.swift:257
- The tuple can represent both toasts and an error, or neither, even though the
  code intends a mutually exclusive success or failure state.
- Proposed concrete type: Result<[Toast], any Error>, or a PollOutcome enum with
  success and failure cases. This also makes the generic error boundary
  explicit.
- Severity: LOW. Confidence: LIKELY. Recommendation: STRENGTHEN.

### typing-012 — Automatic seed failure is discarded

- File: Sources/greendot/AppDelegate.swift:121
- try? await monitor.add hides a probe or persistence error while adding the
  first OpenAI page. The app can finish launch with no page and no explanation.
- Proposed concrete type: handle a typed seed result with do/catch, then log or
  present the error according to the first-run product policy. Do not silently
  convert all failures to success.
- Severity: LOW. Confidence: LIKELY. Recommendation: REVIEW.

### typing-013 — HTTPClient exposes a weak tuple response contract

- File: Sources/StatusCore/HTTPClient.swift:4
- Every client returns (Data, Int). The positional status value is easy to swap
  and does not state whether it is an HTTP status, a transport result, or a
  sentinel.
- Proposed concrete type: introduce a Sendable HTTPResponse with named data and
  statusCode properties, then update the production and test clients together.
  This is a larger API change and is not required by current tests.
- Severity: LOW. Confidence: UNCERTAIN. Recommendation: REVIEW.

### typing-014 — Provider JSON parsers use Any at a real external boundary

- File: Sources/StatusCore/StatuspageParser.swift:92
- StatuspageParser, InstatusParser, and StatuspalParser decode foreign JSON
  with [String: Any] and narrow fields with as?. Statuspal accepts service IDs
  as either Int or String. The parsers fail closed and immediately return
  PageSnapshot, ComponentStatus, and Incident values.
- Proposed concrete type: none without an authoritative provider schema.
  Replacing these dictionaries with guessed Codable DTOs would lose valid
  provider variants. Keep the untyped input local to each parser.
- Severity: LOW. Confidence: CERTAIN. Recommendation: KEEP.

### typing-015 — AppKit dynamic objects and selectors are framework contracts

- File: Sources/greendot/MenuClickOpener.swift:10
- NSEvent monitor tokens are returned as Any and removed through an Any API.
  NSMenuItem.representedObject is Any? and is cast to TargetAction at
  MenuCommands.swift:41 and MenuClickOpener.swift:59. Notification.object is
  Any? at AppDelegate.swift:230. UITestDriver uses as? while walking NSView
  subviews. AppEditMenu uses undo: and redo: selectors for the first
  responder. These are AppKit or distributed-test boundaries, not internal
  domain values.
- Proposed concrete type: keep the AppKit token and representedObject casts;
  keep typed TargetAction after the boundary, fail closed on a wrong object,
  and keep the first-responder selectors.
- Severity: LOW. Confidence: CERTAIN. Recommendation: KEEP.

### typing-016 — Cocoa and bundle bridges cannot be strengthened locally

- File: Sources/StatusCore/HTTPClient.swift:16
- URLSession returns URLResponse, so the HTTPURLResponse cast is required to
  read statusCode. PageStore uses as NSError to inspect Cocoa error domain and
  file codes. BuildInfo reads Bundle.infoDictionary as [String: Any] and
  AboutPanel passes [NSApplication.AboutPanelOptionKey: Any] to AppKit.
- Proposed concrete type: keep HTTPURLResponse, NSError, Bundle's dictionary,
  and AppKit's Any option dictionary at those API edges. Map to domain types
  after the bridge.
- Severity: LOW. Confidence: CERTAIN. Recommendation: KEEP.

### typing-017 — Static regex compilation uses try? as fail-closed policy

- File: Sources/StatusCore/ProviderProbe.swift:224
- The regular expression is a fixed source literal. try? makes a compile
  failure disable Statuspal subdomain extraction rather than crash the app, and
  the optional is checked before use.
- Proposed concrete type: keep the optional boundary and add a focused parser
  test for the literal. A forced compile would trade a recoverable miss for a
  startup crash.
- Severity: LOW. Confidence: CERTAIN. Recommendation: KEEP.

### typing-018 — Lock-backed unchecked Sendable adapters are intentional

- File: Sources/StatusCore/HTTPClient.swift:52
- RecordingHTTPClient and RecordedURLs use locks. CountBox at
  ProviderProbe.swift:246, LiveUserNotificationCenterClient at
  Sources/greendot/SystemToastDelivery.swift:18, and the ControllableHTTPClient,
  ControllableLock, ConcurrencyProbeHTTPClient, SequenceHTTPClient, and
  RecordingUserNotificationCenter test doubles use the same explicit
  synchronization or main-actor-only test usage.
- Proposed concrete type: keep the current adapters. Replacing them with
  actors would make synchronous counters and test controls asynchronous. If
  the adapters remain public, document their synchronization contract.
- Severity: LOW. Confidence: CERTAIN. Recommendation: KEEP.

### typing-019 — UI-test IUOs and literal fixture URL force unwraps are lifecycle patterns

- File: UITests/GreenDotUITests/GreenDotUITests.swift:8
- XCUIApplication and temporary URL properties are assigned in
  setUpWithError before test use. Unit tests also use force unwraps for
  compile-time fixture URLs. Production has no implicitly unwrapped property.
- Proposed concrete type: keep the XCTest lifecycle pattern. Use
  XCTUnwrap only where a test is checking a runtime-built URL.
- Severity: LOW. Confidence: CERTAIN. Recommendation: KEEP.

### typing-020 — Generic Error values preserve heterogeneous failure sources

- File: Sources/greendot/StatusPageEditor.swift:9
- UI error callbacks accept Error because callers can return MonitorError,
  ProbeError, StoreError, URLError, or Foundation file errors. The same
  boundary appears in AppDelegate and the UserNotifications completion API.
  ProviderProbe also needs an arbitrary Error to test cancellation.
- Proposed concrete type: use any Error for explicit existential syntax if the
  project adopts that style, but do not invent one enum that drops source
  error details.
- Severity: LOW. Confidence: CERTAIN. Recommendation: KEEP.

### typing-021 — Cleanup and diagnostic try? calls intentionally do not block work

- File: Sources/greendot/URLOpener.swift:31
- Optional URL-log writes, UI-test dump writes, attachment cleanup, and test
  teardown removal use try? because logging, cleanup, and diagnostics must not
  change the user operation. The ignored seek result and modal return value
  have the same deliberate policy.
- Proposed concrete type: keep these calls. If diagnostic reliability becomes
  a requirement, add a separate logging channel instead of changing the
  application result type.
- Severity: LOW. Confidence: CERTAIN. Recommendation: KEEP.

### typing-022 — Domain optionals and defaults encode real state

- File: Sources/StatusCore/Models.swift:105
- snapshot is optional before the first poll, component IDs can be absent at a
  provider boundary, and Codable defaults preserve older local config files.
  Toast.autoDismissSeconds uses nil for a persistent notification. Page-panel
  onRemove is optional because add mode has no page to remove.
- Proposed concrete type: keep these optionals and defaults. Do not replace
  missing first-run state with sentinel values or force unwraps.
- Severity: LOW. Confidence: CERTAIN. Recommendation: KEEP.

## Recommendations

1. Plan one UI isolation change that covers typing-005 through typing-008.
   Mark AppKit-owned types MainActor-isolated and keep network/domain work in
   StatusCore. Re-run the requested build and the full test suite after the
   change.
2. Convert PageStore to a checked Sendable value or class, and decide the
   Monitor actor-versus-lock contract before adding more concurrent entry
   points.
3. Remove the three direct weak operations in typing-001 through typing-003.
   They have concrete replacements and small downstream surfaces.
4. Make editing callbacks required and represent poll success/failure with a
   Result or enum. Review the first-run seed error policy before changing
   try?.
5. Keep external JSON, AppKit, Foundation, notification, and test-lifecycle
   boundaries weakly typed. Add boundary tests instead of guessed types.

## Out of Scope / Flagged for Review

- The requested swift build -Xswiftc -warn-concurrency is the current
  baseline and passes without warnings. The Swift 6 language-mode probe is a
  forward-compatibility signal only. Its AppKit diagnostic wording comes from
  SDK actor annotations, while the unannotated repository methods are the
  actionable source shape.
- PageStore.defaultDirectory indexes the application-support URL list at
  Sources/StatusCore/PageStore.swift:40. Foundation documents a result for
  this search, but a guarded first-element policy can be reviewed separately.
- PageStore's as NSError at line 49 is needed for NSCocoaErrorDomain and
  missing-file codes. It is not an unsafe cast.
- Typed #selector calls for AppKit actions are not string dispatch. The only
  string selectors are undo: and redo:, which are first-responder actions.
- Weak captures are used for UI lifetime management. No unowned capture was
  found. No production IUO, as!, try!, @preconcurrency, or unsafe declaration
  was found.
- The 11 SwiftLint violations and the generated UI-test project are outside
  this weak-typing disposition. No formal release or validation conclusion is
  made by this development audit.

## Independent Verification Disposition

The mandatory gate selected 16 of 22 records. Independent verifiers confirmed 15; those records now have `verified: true`. 6 lower-confidence records remain provisional.

The verifier found `typing-002` only partial. It has been narrowed to `UNCERTAIN` / `REVIEW`, with the counterevidence recorded in the machine-readable detail.

Verification evidence: [verification-batch-1.md](verification-batch-1.md), [verification-batch-3.md](verification-batch-3.md).

Final machine-readable severity counts: HIGH 4, MEDIUM 2, LOW 16. The original prose above records the specialist's pre-verification assessment; this disposition and the JSON block below are authoritative after verification.

## Machine-Readable Findings

All findings below are unverified. The final object is intentionally the only
fenced object in this report.

```json
{"findings":[{"id":"typing-001","file":"Sources/StatusCore/StatuspageParser.swift","line":65,"severity":"LOW","confidence":"CERTAIN","recommendation":"STRENGTHEN","detail":"Use a compactMap pair to make the grouping key non-optional.","verified":true},{"id":"typing-002","file":"Sources/StatusCore/ProviderProbe.swift","line":192,"severity":"LOW","confidence":"UNCERTAIN","recommendation":"REVIEW","detail":"Remove the bridge with an ordered native Set pass; the duplicate-runtime-risk wording is overstated. Independent verifier disposition: PARTIAL. NSOrderedSet/Array/as? is an untyped bridge, but subdomains is [String] with only String insertions and a direct Darwin check deduplicated successfully; duplicate fallback is not observed under the invariant.","verified":false},{"id":"typing-003","file":"Tests/greendotTests/MenuBuilderTests.swift","line":187,"severity":"LOW","confidence":"CERTAIN","recommendation":"STRENGTHEN","detail":"Cast representedObject to TargetAction and call invoke().","verified":true},{"id":"typing-004","file":"Sources/StatusCore/PageStore.swift","line":27,"severity":"MEDIUM","confidence":"LIKELY","recommendation":"STRENGTHEN","detail":"PageStore has immutable URL state and stateless I/O but uses @unchecked Sendable; convert it to a checked Sendable struct or class after the URL check.","verified":false},{"id":"typing-005","file":"Sources/greendot/StatusDot.swift","line":11,"severity":"HIGH","confidence":"CERTAIN","recommendation":"ISOLATE","detail":"The lock-backed AppKit cache is still rejected by strict Swift 6 concurrency checking.","verified":true},{"id":"typing-006","file":"Sources/greendot/AppDelegate.swift","line":4,"severity":"HIGH","confidence":"CERTAIN","recommendation":"ISOLATE","detail":"AppDelegate needs explicit actor isolation and an actor-aware callback type.","verified":true},{"id":"typing-007","file":"Sources/greendot/PagePanelController.swift","line":9,"severity":"HIGH","confidence":"CERTAIN","recommendation":"ISOLATE","detail":"The panel controller lacks required MainActor isolation under strict Swift 6.","verified":true},{"id":"typing-008","file":"Sources/greendot/ComponentPicker.swift","line":4,"severity":"HIGH","confidence":"CERTAIN","recommendation":"ISOLATE","detail":"All listed AppKit helpers lack explicit boundaries; some are hard errors and the rest produce actor warnings.","verified":true},{"id":"typing-009","file":"Sources/StatusCore/Monitor.swift","line":3,"severity":"MEDIUM","confidence":"LIKELY","recommendation":"REVIEW","detail":"Monitor uses @unchecked Sendable for mutable state and an unannotated callback. Locks make this deliberate, but an actor or explicit MainActor Sendable callback would make the contract checkable.","verified":false},{"id":"typing-010","file":"Sources/greendot/PagePanelController.swift","line":25,"severity":"LOW","confidence":"LIKELY","recommendation":"STRENGTHEN","detail":"Editing component callbacks default to closures that return true, so a missing callback can report success without mutation; require callbacks or return false.","verified":false},{"id":"typing-011","file":"Sources/greendot/AppDelegate.swift","line":257,"severity":"LOW","confidence":"LIKELY","recommendation":"STRENGTHEN","detail":"The optional Error field in the poll tuple permits invalid success and failure combinations; use Result<[Toast], any Error> or a PollOutcome enum.","verified":false},{"id":"typing-012","file":"Sources/greendot/AppDelegate.swift","line":121,"severity":"LOW","confidence":"LIKELY","recommendation":"REVIEW","detail":"try? hides automatic OpenAI seed probe and save errors; use a typed result and an explicit first-run logging or presentation policy.","verified":false},{"id":"typing-013","file":"Sources/StatusCore/HTTPClient.swift","line":4,"severity":"LOW","confidence":"UNCERTAIN","recommendation":"REVIEW","detail":"The HTTPClient tuple (Data, Int) has positional and sentinel semantics; a Sendable HTTPResponse with named data and statusCode fields would be clearer.","verified":false},{"id":"typing-014","file":"Sources/StatusCore/StatuspageParser.swift","line":92,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Keep Any local to provider JSON boundaries and do not guess Codable DTOs.","verified":true},{"id":"typing-015","file":"Sources/greendot/MenuClickOpener.swift","line":10,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Keep these dynamic edges and fail closed after them.","verified":true},{"id":"typing-016","file":"Sources/StatusCore/HTTPClient.swift","line":16,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Retain the framework bridge types and map to domain values after each edge where applicable.","verified":true},{"id":"typing-017","file":"Sources/StatusCore/ProviderProbe.swift","line":224,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Keep fail-closed optional regex compilation and extraction test.","verified":true},{"id":"typing-018","file":"Sources/StatusCore/HTTPClient.swift","line":52,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Keep and document intentional unchecked synchronization adapters.","verified":true},{"id":"typing-019","file":"UITests/GreenDotUITests/GreenDotUITests.swift","line":8,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Keep assigned XCTest lifecycle IUOs and known test fixtures; use XCTUnwrap for runtime-built values.","verified":true},{"id":"typing-020","file":"Sources/greendot/StatusPageEditor.swift","line":9,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Retain the generic error existential; any Error is only spelling clarification.","verified":true},{"id":"typing-021","file":"Sources/greendot/URLOpener.swift","line":31,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Keep non-fatal try? for optional diagnostics/cleanup/presentation plumbing.","verified":true},{"id":"typing-022","file":"Sources/StatusCore/Models.swift","line":105,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Preserve these optionals/defaults and test future migrations explicitly.","verified":true}]}
```
