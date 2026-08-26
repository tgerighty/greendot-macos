# Verification batch 3

This is an independent, read-only verification of the 20 supplied findings. I
did not change Sources, Tests, UITests, dependencies, configuration, Git, or
the existing assessment reports. The only written file is this report.
Source baseline: `310032baadea24dd7ea32a97ddc5af8df9a52845`. Later apply
commits consolidated the `types-004` consumers through `Severity.displayName`.

Fresh checks used as supporting evidence:

- `cloc --by-file --include-lang=Swift ...` reports 368, 316, and 306 code
  lines for the three cited large test files.
- SwiftLint reports 51 logical body lines for `measureRemaining`, and a
  301-line class body for `MonitorRefreshTransactionTests`; the editor suite
  has no function/type-length violation.
- `swift test` completed successfully: 150 tests, one intentional benchmark
  skip, zero failures.
- A direct Foundation check of `Array(NSOrderedSet(array: ["a", "a", "b"]))
  as? [String]` returned `Optional(["a", "b"])`; this is relevant to the
  narrow qualification on `typing-002`.

## Findings

### loc-003 — SURVIVES

Evidence: `cloc` reports 368 code lines and 397 physical lines. The class is
under `Tests/greendotTests`, and `testEmitBenchTimings` is gated by
`GREENDOT_BENCH` and prints the benchmark records. Its helpers group parser
timings (lines 60–94), poll timings (96–152), menu/cache timings (160–180),
status-dot rendering (247–259), and store plus provider-cache/pulse metrics
(189–245 and 261–294). The shared fixture builders and one output harness make
the grouping deliberate.

Corrected narrow claim: none required. This is a test-only benchmark harness;
the file threshold alone does not justify splitting it.

Severity: LOW. Confidence: HIGH. Recommendation: EXEMPT; split only if a
future edit creates distinct navigation or ownership boundaries. Safe to mark
the original finding verified: YES.

### loc-004 — SURVIVES

Evidence: SwiftLint reports `measureRemaining` at line 189 as a 51-line body.
The body has four visibly separate measurements: the Statuspal request at
190–204, regex compilation reuse at 205–210, second-poll parse reuse at
212–230, and reachable-pulse counting at 232–237. The helper extraction is
therefore a reasonable next-edit cleanup, not a production defect.

Corrected narrow claim: none required; extraction is optional and can preserve
the current shared fixture setup.

Severity: LOW. Confidence: HIGH. Recommendation: DECOMPOSE on the next
benchmark edit, otherwise leave unchanged. Safe to mark verified: YES.

### loc-005 — SURVIVES

Evidence: `cloc` reports 316 code lines and 359 physical lines. The suite has
persistence/error tests at 17–150, panel replacement and pending-save lifecycle
tests at 152–248 and 291–320, recursive AppKit view helpers at 250–288 and a
`PendingSaveGate` actor at 330–359. SwiftLint reports no violation for this
file, including no function-body-length violation. It is test code and does
not alter shipped production behavior.

Corrected narrow claim: none required; the concerns are related to the editor
and its panel lifecycle.

Severity: LOW. Confidence: HIGH. Recommendation: EXEMPT from the file-size
threshold. Safe to mark verified: YES.

### loc-006 — SURVIVES

Evidence: `cloc` reports 306 code lines and 353 physical lines. SwiftLint
reports a 301-line class body. The test methods cover persistence/error
boundaries (42–68 and 295–312), overlapping and cancelled poll transactions
(70–160 and 251–293), and edit/toggle conflict protection (162–249), with
shared fixtures at 314–352. The suite remains cohesive around monitor refresh
transactions and has no long function warning.

Corrected narrow claim: none required; the size is a low-risk test-suite
threshold exception.

Severity: LOW. Confidence: HIGH. Recommendation: EXEMPT. Safe to mark
verified: YES.

### types-004 — SURVIVES

Evidence: `ToastPolicy.body(for:)` at `Sources/StatusCore/ToastPolicy.swift:37–45`
and `MenuBuilder.overallText` at `Sources/greendot/MenuBuilder.swift:185–192`
both switch over all four `Severity` cases and return exactly
`Operational`, `Degraded`, `Major outage`, and `Unreachable`. `StatusMapping`
also has provider-specific component text such as `Partial outage` and
`Maintenance`, so a shared Severity display name would not replace that
provider-specific mapping.

Corrected narrow claim: none required. Add one Severity display-name API and
retain provider-specific component text in `StatusMapping`.

Severity: LOW. Confidence: HIGH. Recommendation: CONSOLIDATE when touching
status labels. Safe to mark verified: YES.

### types-005 — SURVIVES

Evidence: `AttemptResult.hit` is `hit(PageSnapshot, Data)` at
`ProviderProbe.swift:129–133`. `take` immediately converts those two values to
`ProbeHit(snapshot:body:)` at 45–49. The standard attempt creates the same pair
at 145–153, while the Statuspal path destructures the pair and constructs the
same `ProbeHit` again at 197–205. No field or error distinction is lost by
using `hit(ProbeHit)`.

Corrected narrow claim: none required; use the existing `ProbeHit` as the
private result payload.

Severity: LOW. Confidence: HIGH. Recommendation: CONSOLIDATE. Safe to mark
verified: YES.

### types-006 — SURVIVES

Evidence: production declares
`typealias ScheduledMainActorWork = @MainActor @Sendable () -> Void` at
`StatusMenuController.swift:4`. The test file redeclares the identical
function type as a private alias at line 6 and uses it only for the scheduled
closures at lines 53, 97, and 166. The test imports the production module with
`@testable`, so the internal production alias is available without a second
definition.

Corrected narrow claim: none required; remove the test alias or place one
shared internal alias in a common module location.

Severity: LOW. Confidence: HIGH. Recommendation: CONSOLIDATE. Safe to mark
verified: YES.

### types-007 — SURVIVES

Evidence: `StatusMenuController` is declared `final class ...: NSObject` at
line 7, calls only `super.init()` at line 37, and has no `@objc` methods,
selectors, or delegate conformance in the type. Its AppKit collaborators
(`MenuClickOpener`, `TargetAction`, and `PagePanelController`) are the types
that actually use delegate or selector contracts. Removing this one base class
would require removing only `super.init()`.

Corrected narrow claim: none required; retain NSObject on the selector- or
delegate-backed AppKit types.

Severity: LOW. Confidence: HIGH. Recommendation: REMOVE_INHERITANCE. Safe to
mark verified: YES.

### typing-001 — SURVIVES

Evidence: `StatuspageParser.nest` builds `grouped` with the predicate
`$0.groupID != nil && !$0.isGroup` at line 64, then groups with `$0.groupID!`
at line 65. The array is immutable and the predicate guarantees the optional
is non-nil today, but the force unwrap still couples two expressions. A
`compactMap` that returns `(String, Row)` would make the key non-optional.

Corrected narrow claim: none required; this is a small defensive typing
cleanup, not a current crash demonstrated by the tests.

Severity: LOW. Confidence: HIGH. Recommendation: STRENGTHEN. Safe to mark
verified: YES.

### typing-002 — PARTIAL

Evidence: line 192 does bridge an ordered Foundation collection through
`Array(NSOrderedSet(...))` and a dynamic `as? [String]`, so an ordered
`[String]` plus a native seen set would remove the weak boundary. However,
`subdomains` is declared `[String]` at line 172 and receives only Strings at
lines 174 and 185. Under that invariant, the current Foundation cast succeeds
and NSOrderedSet removes duplicates; a direct Darwin check returned
`Optional(["a", "b"])`. The `?? subdomains` fallback is therefore defensive
but not an observed route to duplicate values in this function.

Corrected narrow claim: remove the untyped Objective-C bridge and preserve
order with a native `Set<String>`/array pass; do not claim that current inputs
can reach duplicate fallback values without a separate bridge failure.

Severity: LOW. Confidence: HIGH. Recommendation: STRENGTHEN optionally; the
cleanup is valid, but the duplicate-runtime-risk wording is overstated. Safe
to mark the original finding verified: NO.

### typing-003 — SURVIVES

Evidence: the test helper casts `representedObject` to `AnyObject`, constructs
`NSSelectorFromString("invoke")`, calls `perform`, and discards its result at
`MenuBuilderTests.swift:186–189`. Production stores a concrete `TargetAction`
at `MenuBuilder.swift:207–222`; `TargetAction.invoke()` is an ordinary typed
method, and `MenuCommands` already uses `as? TargetAction` followed by
`box.invoke()` at lines 40–43.

Corrected narrow claim: none required; cast to `TargetAction` and call
`invoke()` directly in the test helper.

Severity: LOW. Confidence: HIGH. Recommendation: STRENGTHEN. Safe to mark
verified: YES.

### typing-014 — SURVIVES

Evidence: `StatuspageParser`, `InstatusParser`, and `StatuspalParser` use
`JSONSerialization` and `[String: Any]` only while reading provider payloads.
Required top-level shape/discriminator checks throw `ParserError` (for example
`StatuspageParser.swift:17–20`, `InstatusParser.swift:5–11`, and
`StatuspalParser.swift:5–7`); malformed nested rows are skipped or defaulted
rather than force-cast. Each parser returns a typed `PageSnapshot` with typed
`ComponentStatus` and `Incident` values. There is no authoritative schema in
the repository that would justify guessed Codable DTOs.

Corrected narrow claim: keep the untyped representation local to the external
JSON boundary, validate required provider markers, and map to typed domain
values; document any optional-field default if stricter rejection is later
required.

Severity: LOW. Confidence: HIGH. Recommendation: KEEP. Safe to mark verified:
YES.

### typing-015 — SURVIVES

Evidence: `MenuClickOpener` stores the NSEvent monitor token as `Any?` at line
10 and casts `NSMenuItem.representedObject` to `TargetAction` at line 59. The
distributed notification callback receives `note.object as? String` at
`AppDelegate.swift:224–231`. `UITestDriver` must walk arbitrary `NSView`
subclasses and casts to `NSButton`, `NSTextField`, and `NSScrollView`; the edit
menu intentionally uses first-responder `undo:`/`redo:` selectors at
`AppEditMenu.swift:35–41`. These are framework or test-transport boundaries,
not domain models to replace with guessed structs.

Corrected narrow claim: none required; keep the casts/selectors at the edges
and fail closed on a wrong runtime object.

Severity: LOW. Confidence: HIGH. Recommendation: KEEP. Safe to mark verified:
YES.

### typing-016 — SURVIVES

Evidence: `URLSessionHTTPClient` must cast `URLResponse` to
`HTTPURLResponse` to read `statusCode` at `HTTPClient.swift:14–17`.
`PageStore` uses `as NSError` only to inspect Cocoa missing-file domain/codes at
`PageStore.swift:49–53`. `BuildInfo` reads the Foundation
`Bundle.infoDictionary` and maps the hash to a String at `BuildInfo.swift:5–17`;
`AboutPanel.options` creates the AppKit-required
`[NSApplication.AboutPanelOptionKey: Any]` at lines 21–28. These bridges are
already mapped to status, error policy, hash, or AppKit API inputs at their
edges.

Corrected narrow claim: none required; retain the framework bridge types and
map to domain values immediately after each edge where applicable.

Severity: LOW. Confidence: HIGH. Recommendation: KEEP. Safe to mark verified:
YES.

### typing-017 — SURVIVES

Evidence: the static Statuspal regex increments its compile counter and uses
`try? NSRegularExpression(...)` at `ProviderProbe.swift:222–228`.
`extractStatuspalSubdomain` guards the optional regex at line 231 and returns
nil on no match. `PollPerformanceTests.testStatuspalRegexCompilesOnce` checks
successful extraction and one-time compilation at lines 133–139. A forced
startup failure would turn a recoverable extraction miss into an application
failure.

Corrected narrow claim: none required; retain the optional fail-closed policy
and the focused extraction test.

Severity: LOW. Confidence: HIGH. Recommendation: KEEP. Safe to mark verified:
YES.

### typing-018 — SURVIVES

Evidence: `RecordingHTTPClient` delegates its state to lock-backed
`RecordedURLs` (`HTTPClient.swift:52–82`), and `CountBox` uses an `NSLock` for
all reads/writes (`ProviderProbe.swift:246–267`).
`LiveUserNotificationCenterClient` protects lazy center initialization with an
`NSLock` (`SystemToastDelivery.swift:18–29`). Test doubles
`ControllableHTTPClient`, `ControllableLock`, `ConcurrencyProbeHTTPClient`,
and `SequenceHTTPClient` use locks; `RecordingUserNotificationCenter` is used
only by the `@MainActor` test class and completes callbacks synchronously.
Replacing these controls with actors would make the synchronous counters,
completion controls, or lock protocol asynchronous.

Corrected narrow claim: none required; the unchecked conformances are
intentional synchronization/test adapters and should remain documented.

Severity: LOW. Confidence: HIGH. Recommendation: KEEP. Safe to mark verified:
YES.

### typing-019 — SURVIVES

Evidence: the cited UI test declares six XCTest lifecycle IUOs at lines 8–13
and assigns every one in `setUpWithError` before the tests use it (17–44).
`tearDownWithError` also guards the optional application before waiting (48–54).
The cited file itself has no URL force unwrap; other unit-test fixture URLs are
literal HTTPS values (for example `MenuBuilderTests.swift:158` and
`PerformanceHarnessTests.swift:80–82`) and are test-only. A repository search
found no implicitly-unwrapped property in `Sources`; production URL creation
uses guards or optional fallback instead.

Corrected narrow claim: keep assigned XCTest lifecycle IUOs and known test
fixture URL unwraps, while using `XCTUnwrap` for runtime-built test values;
there is no production IUO finding.

Severity: LOW. Confidence: HIGH. Recommendation: KEEP. Safe to mark verified:
YES.

### typing-020 — SURVIVES

Evidence: `StatusPageEditor` stores and accepts `(Error) -> Void` at lines 9 and
16, passes `MonitorError.pageNotFound` at line 32, and forwards caught errors
from asynchronous add/edit and synchronous mutation paths at 103–117.
Callers in `AppDelegate` pass the same generic callback to `NSAlert` and to
editor errors. The underlying operations can produce `MonitorError`,
`ProbeError`, `StoreError`, `URLError`, or Foundation errors, so a lossy enum
would discard useful source information. `any Error` is an optional spelling
clarification, not a required redesign.

Corrected narrow claim: none required; retain the heterogeneous error
existential at the UI presentation boundary.

Severity: LOW. Confidence: HIGH. Recommendation: KEEP. Safe to mark verified:
YES.

### typing-021 — SURVIVES

Evidence: `URLOpener.append` treats file-open, seek, write, and close failures
as non-fatal at lines 27–37; normal URL validation and the workspace/log choice
remain explicit at lines 12–25. UI-test dump writes, notification attachment
cleanup, test teardown removal, and test-only file reads likewise use `try?`
for diagnostics or cleanup. The ignored `NSAlert.runModal()` response is only
used to present an error, and the ignored seek offset does not determine the
URL operation. `URLOpenerTests` explicitly verifies that log mode records the
URL and intentionally skips workspace opening.

Corrected narrow claim: keep ignored errors for optional diagnostics, cleanup,
and presentation plumbing; if diagnostic delivery becomes a requirement,
report it through a separate channel rather than changing the main result.

Severity: LOW. Confidence: HIGH. Recommendation: KEEP. Safe to mark verified:
YES.

### typing-022 — SURVIVES

Evidence: `WatchedPage.snapshot` is optional at `Models.swift:99–120` and is
absent before the first poll; `ComponentStatus.init` accepts an optional ID
and defaults to the name at 17–30, while provider parsers accept missing or
numeric provider IDs. `WatchedPage` decoding supplies backward-compatible
defaults for notifications, disabled components, and snapshot at 159–167.
`Toast.autoDismissSeconds` returns nil for non-green persistent toasts, and
`PagePanelController.onRemove` is optional and returns false in add mode
(`PagePanelController.swift:13–27` and 182–189). These are real lifecycle
states, not weak substitutes for required values.

Corrected narrow claim: none required; preserve the optionals/defaults and
cover any future persistence migration with explicit tests.

Severity: LOW. Confidence: HIGH. Recommendation: KEEP. Safe to mark verified:
YES.

```json
[
  {"id":"loc-003","disposition":"SURVIVES","evidence":"cloc=368; test-only GREENDOT_BENCH harness with five shared metric domains.","corrected_claim":"Benchmark harness is intentionally grouped; do not split solely for the file threshold.","severity":"LOW","confidence":"HIGH","recommendation":"EXEMPT","verified":true},
  {"id":"loc-004","disposition":"SURVIVES","evidence":"SwiftLint reports measureRemaining body length 51; source has four independent measurements at 190-204, 205-210, 212-230, and 232-237.","corrected_claim":"Optional helper extraction is suitable on the next benchmark edit.","severity":"LOW","confidence":"HIGH","recommendation":"DECOMPOSE","verified":true},
  {"id":"loc-005","disposition":"SURVIVES","evidence":"cloc=316; source groups editor persistence, panel lifecycle, and support; SwiftLint reports no violation.","corrected_claim":"Related editor integration tests may remain together below a future navigation threshold.","severity":"LOW","confidence":"HIGH","recommendation":"EXEMPT","verified":true},
  {"id":"loc-006","disposition":"SURVIVES","evidence":"cloc=306 and SwiftLint class body=301; source covers cohesive refresh persistence, concurrency, mutation, and fixtures.","corrected_claim":"Cohesive monitor transaction tests may remain together as a low-risk exception.","severity":"LOW","confidence":"HIGH","recommendation":"EXEMPT","verified":true},
  {"id":"types-004","disposition":"SURVIVES","evidence":"ToastPolicy.body and MenuBuilder.overallText contain identical four Severity labels; StatusMapping has provider-specific labels.","corrected_claim":"Centralize Severity display names but retain provider-specific component text.","severity":"LOW","confidence":"HIGH","recommendation":"CONSOLIDATE","verified":true},
  {"id":"types-005","disposition":"SURVIVES","evidence":"AttemptResult.hit carries the same PageSnapshot/Data pair that is immediately wrapped and later unwrapped into ProbeHit.","corrected_claim":"Use ProbeHit as the private AttemptResult payload.","severity":"LOW","confidence":"HIGH","recommendation":"CONSOLIDATE","verified":true},
  {"id":"types-006","disposition":"SURVIVES","evidence":"Production and test ScheduledMainActorWork aliases are byte-for-byte identical; test uses are only closure storage.","corrected_claim":"Use one internal production/shared alias.","severity":"LOW","confidence":"HIGH","recommendation":"CONSOLIDATE","verified":true},
  {"id":"types-007","disposition":"SURVIVES","evidence":"StatusMenuController only calls NSObject super.init; no selector, ObjC method, or delegate contract is present on the type.","corrected_claim":"Remove only StatusMenuController NSObject inheritance and super.init.","severity":"LOW","confidence":"HIGH","recommendation":"REMOVE_INHERITANCE","verified":true},
  {"id":"typing-001","disposition":"SURVIVES","evidence":"grouped is filtered by groupID != nil immediately before Dictionary(grouping:) uses groupID!.","corrected_claim":"Use a compactMap pair to make the grouping key non-optional.","severity":"LOW","confidence":"HIGH","recommendation":"STRENGTHEN","verified":true},
  {"id":"typing-002","disposition":"PARTIAL","evidence":"NSOrderedSet/Array/as? is an untyped bridge, but subdomains is [String] with only String insertions and a direct Darwin check deduplicated successfully; duplicate fallback is not observed under the invariant.","corrected_claim":"Remove the bridge with an ordered native Set pass; the duplicate-runtime-risk wording is overstated.","severity":"LOW","confidence":"HIGH","recommendation":"STRENGTHEN","verified":false},
  {"id":"typing-003","disposition":"SURVIVES","evidence":"Menu test uses AnyObject plus NSSelectorFromString and discards perform result; TargetAction exposes typed invoke and production already calls it directly.","corrected_claim":"Cast representedObject to TargetAction and call invoke().","severity":"LOW","confidence":"HIGH","recommendation":"STRENGTHEN","verified":true},
  {"id":"typing-014","disposition":"SURVIVES","evidence":"All three parsers keep Any dictionaries at JSON boundaries, validate required markers, skip/default malformed optional rows, and return typed PageSnapshot values.","corrected_claim":"Keep Any local to provider JSON boundaries and do not guess Codable DTOs.","severity":"LOW","confidence":"HIGH","recommendation":"KEEP","verified":true},
  {"id":"typing-015","disposition":"SURVIVES","evidence":"NSEvent token, representedObject, DistributedNotificationCenter object, NSView casts, and first-responder undo/redo selectors are all framework/test transport edges.","corrected_claim":"Keep these dynamic edges and fail closed after them.","severity":"LOW","confidence":"HIGH","recommendation":"KEEP","verified":true},
  {"id":"typing-016","disposition":"SURVIVES","evidence":"HTTPURLResponse, NSError, Bundle.infoDictionary, and AboutPanel option dictionary are required Foundation/AppKit bridges and are mapped or passed at their edges.","corrected_claim":"Retain the framework bridge types and map to domain values after each edge where applicable.","severity":"LOW","confidence":"HIGH","recommendation":"KEEP","verified":true},
  {"id":"typing-017","disposition":"SURVIVES","evidence":"Fixed Statuspal regex is optional via try? and extraction guards nil; focused test checks extraction and one-time compilation.","corrected_claim":"Keep fail-closed optional regex compilation and extraction test.","severity":"LOW","confidence":"HIGH","recommendation":"KEEP","verified":true},
  {"id":"typing-018","disposition":"SURVIVES","evidence":"Production adapters use NSLock; test doubles use locks or a @MainActor synchronous notification fake, so actors would alter synchronous controls.","corrected_claim":"Keep and document intentional unchecked synchronization adapters.","severity":"LOW","confidence":"HIGH","recommendation":"KEEP","verified":true},
  {"id":"typing-019","disposition":"SURVIVES","evidence":"Six UI-test IUOs are assigned in setUp before use; URL force unwraps are test-only known fixtures; repository production Sources contain no IUO.","corrected_claim":"Keep assigned XCTest lifecycle IUOs and known test fixtures; use XCTUnwrap for runtime-built values.","severity":"LOW","confidence":"HIGH","recommendation":"KEEP","verified":true},
  {"id":"typing-020","disposition":"SURVIVES","evidence":"StatusPageEditor forwards MonitorError and caught heterogeneous Monitor/Probe/Store/URL/Foundation errors through one UI callback.","corrected_claim":"Retain the generic error existential; any Error is only spelling clarification.","severity":"LOW","confidence":"HIGH","recommendation":"KEEP","verified":true},
  {"id":"typing-021","disposition":"SURVIVES","evidence":"URL-log writes, diagnostics, cleanup, teardown removal, ignored seek offset, and modal response are non-essential paths; URL tests verify the intentional log-mode route.","corrected_claim":"Keep non-fatal try? for optional diagnostics/cleanup/presentation plumbing.","severity":"LOW","confidence":"HIGH","recommendation":"KEEP","verified":true},
  {"id":"typing-022","disposition":"SURVIVES","evidence":"Optional snapshot, provider ID fallback, Codable defaults, nil persistent-toast duration, and add-mode optional removal are explicit lifecycle paths.","corrected_claim":"Preserve these optionals/defaults and test future migrations explicitly.","severity":"LOW","confidence":"HIGH","recommendation":"KEEP","verified":true}
]
```
