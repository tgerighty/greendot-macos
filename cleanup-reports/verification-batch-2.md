# Independent verification: batch 2

Scope: the 19 supplied claims at the current `main` commit (`310032b`). This
was a read-only source and history audit. I did not change production code,
tests, dependencies, configuration, or Git state. `swift test --disable-sandbox`
also passed: 150 tests, 1 intentional skip, 0 failures.

## Findings

### circular-002 — SURVIVES

Evidence: `AppDelegate.statusMenu` is the owning property
(`Sources/greendot/AppDelegate.swift:5`), while the application callbacks that
can return to it use `[weak self]` (`:142-160`). The controller's tracking-ended
callback also uses `[weak self]` (`Sources/greendot/StatusMenuController.swift:39-41`),
and the local event monitor uses a weak capture (`Sources/greendot/MenuClickOpener.swift:30-35`).
`MenuClickOpener.deinit` removes the monitor (`:13-15`, `:50-54`). The menu
tests exercise deferred tracking/reload behavior (`Tests/greendotTests/StatusMenuControllerTests.swift:48-198`).
No strong callback back-edge to `AppDelegate` or `StatusMenuController` was
found.

Corrected narrow claim: the menu and tracking paths form intentional semantic
callback loops, but the current self-referencing captures are weak and do not
form a strong retain cycle.

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: KEEP; preserve the weak captures and monitor cleanup.
- Safe to mark the original finding verified: YES.

### circular-003 — SURVIVES

Evidence: `StatusPageEditor` retains its panel (`Sources/greendot/StatusPageEditor.swift:10,
:41-57`), but save, component-toggle, set-all, and remove closures all capture
the editor weakly (`:43-53`, `:73-91`). `PagePanelController` cancels pending
work and increments its generation on close (`Sources/greendot/PagePanelController.swift:64-78,
:192-196`); completion accepts a result only when the generation still matches
(`:161-175`). The editor replacement, pending-save/cancel, and late-success
tests pass (`Tests/greendotTests/StatusPageEditorTests.swift:152-248`), as does
the controller/window deallocation test (`Tests/greendotTests/PanelLifecycleTests.swift:269-290`).

Corrected narrow claim: the UI callback graph is cyclic as event flow, but its
back-captures are weak and its asynchronous completion is generation-gated;
the current lifecycle tests cover the relevant replacement and close paths.

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: KEEP; preserve weak captures, cancellation, and generation checks.
- Safe to mark the original finding verified: YES.

### dead-001 — SURVIVES

Evidence: the computed `BuildInfo.gitHash` property only calls the local
`gitHash(from:)` helper (`Sources/greendot/BuildInfo.swift:5-7`). A repository-wide
search found no `BuildInfo.gitHash` property call, selector, reflection use, or
configuration reference. The live About path calls `shortHash(from:)`
(`Sources/greendot/BuildInfo.swift:14-17, :26`), while `gitHash(from:)` and
`shortHash(from:)` have direct tests (`Tests/greendotTests/AboutTests.swift:6-30`).
The Makefile supplies `GitCommitHash` to the bundle (`Makefile:27`); that does
not use the unused computed property.

Corrected narrow claim: only the internal computed property `BuildInfo.gitHash`
is unused; the helper function, short-hash path, bundle metadata, and tests are
live.

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: REMOVE the unused computed property only; retain the helper APIs.
- Safe to mark the original finding verified: YES.

### dedup-008 — SURVIVES

Evidence: `breakPersistence(at:)` is byte-for-byte the same helper in
`Tests/greendotTests/AppDelegateRefreshErrorTests.swift:163-166` and
`Tests/greendotTests/StatusPageEditorTests.swift:285-288`. Both remove
`config.json` and replace it with a directory to force a persistence error.
There is also a semantically equivalent helper with a directory argument in
`Tests/greendotTests/PanelLifecycleTests.swift:317-320`. The first two helpers
are used by multiple tests (`AppDelegateRefreshErrorTests.swift:65,85,111` and
`StatusPageEditorTests.swift:30,87`).

Corrected narrow claim: the exact two-method duplication is confirmed; the
repository also has one third, differently shaped test-local version. Moving a
small public helper into the existing `TestSupport` target is optional test
maintenance, not a production concern.

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: CONSOLIDATE when test support is next changed; otherwise KEEP the readable local helpers.
- Safe to mark the original finding verified: YES.

### defensive-016 — SURVIVES

Evidence: `PageStore.load()` returns `AppConfig()` only for the two Cocoa
no-such-file codes (`Sources/StatusCore/PageStore.swift:44-55`). Other file-read
errors are rethrown. JSON decoding and `validate` failures are converted to
`StoreError.corrupt` (`:56-62`). Tests cover missing-file/no-write behavior,
corrupt JSON, unsupported versions, and duplicate IDs
(`Tests/StatusCoreTests/ProbeAndMonitorTests.swift:218-248`,
`Tests/StatusCoreTests/PageStoreValidationTests.swift:5-56`).

Corrected narrow claim: the missing-file distinction is limited to the explicit
no-such-file Cocoa errors; all other read errors remain visible, while decode or
validation failures are normalized to `StoreError.corrupt`.

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: KEEP this file/JSON boundary handling.
- Safe to mark the original finding verified: YES.

### defensive-017 — SURVIVES

Evidence: `probeHit` tries providers in `probeOrder` and continues after
non-200 or parser misses (`Sources/StatusCore/ProviderProbe.swift:89-103,
:135-161`). Statuspal first derives a subdomain from a named host, otherwise
fetches the page HTML and extracts a Statuspal API subdomain (`:163-190`), then
tries both API prefixes (`:192-213`). `throwIfCancelled` rethrows cancellation
instead of converting it to a network miss (`:216-219`). Direct tests cover
preferred-provider fallback and cancellation (`Tests/StatusCoreTests/PollPerformanceTests.swift:142-154`,
`Tests/StatusCoreTests/ProbeAndMonitorTests.swift:129-167`); the Statuspal
regex path is also exercised (`PollPerformanceTests.swift:133-140`).

Corrected narrow claim: provider and parser misses are intentionally isolated
inside the probe boundary, while cancellation remains throwable; the Statuspal
HTML/API fallback is an active path and should not be deleted. HTTP status
classification can be refined separately.

- Severity: LOW
- Confidence: HIGH
- Recommendation: KEEP the fallback and cancellation boundary; add a full HTML-to-API regression test if coverage is expanded.
- Safe to mark the original finding verified: YES.

### defensive-018 — SURVIVES

Evidence: editor saves present non-cancellation errors and return failure
without closing (`Sources/greendot/StatusPageEditor.swift:94-107`); synchronous
editor changes also present errors (`:110-118`). The app shell ignores a
`CancellationError`, reports a non-cancellation poll error once per gate, and
delivers toasts only on the latest successful outcome
(`Sources/greendot/AppDelegate.swift:252-277`). Invocation identity rejects
stale results before touching the gate (`:253-267`). Tests cover persistence
error gating, stale completion, cancellation, successful toast delivery, and
failed editor add/edit (`Tests/greendotTests/AppDelegateRefreshErrorTests.swift:26-149`,
`Tests/greendotTests/StatusPageEditorTests.swift:17-127`).

Corrected narrow claim: this is a UI boundary for expected operation errors;
`CancellationError` outcomes are suppressed, stale outcomes are ignored, and
toast delivery occurs only for the accepted successful poll. Cancellation after
the monitor has already returned a successful result is outside this boundary.

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: KEEP the catches and invocation/error gate.
- Safe to mark the original finding verified: YES.

### defensive-019 — SURVIVES

Evidence: `pollAll` checks cancellation before applying results
(`Sources/StatusCore/Monitor.swift:141-167`). `startPoll` assigns a monotonically
new poll identity under `transitionLock` (`:228-240`). `applyPollResults` holds
the same lock, checks cancellation, rejects an old identity, and merges only
pages whose input revision still matches (`:269-321`); mutations advance the
per-page revision while holding the lock (`:243-265`). Transaction tests cover
newest-poll-wins, cancelled polls (including waiting for the commit lock),
notification edits during a poll, and completed edits surviving older polls
(`Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift:70-221`).

Corrected narrow claim: under Swift's cooperative cancellation model, the
commit-boundary check rejects cancellation observed before the synchronous
merge/save and the identity/revision guards reject stale inputs. Cancellation
that occurs after `Task.checkCancellation()` has passed cannot interrupt the
already synchronous `store.save`; this is the normal boundary limitation, not
evidence that the guards are dead or removable.

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: KEEP the lock, identity, revision, and cancellation guards.
- Safe to mark the original finding verified: YES.

### defensive-020 — SURVIVES

Evidence: attachment conversion returns `nil` when image/TIFF/PNG conversion
fails (`Sources/greendot/SystemToastDelivery.swift:141-146`). If temporary-file
writing or `UNNotificationAttachment` creation fails, the catch removes the
temporary path when possible and returns `nil` (`:147-159`). `content(for:)`
still returns notification content without an attachment (`:108-119`), and
`deliver` submits that content without throwing (`:93-105`). Toast attachment
behavior is exercised for all severities (`Tests/greendotTests/SystemToastDeliveryTests.swift:63-80`).

Corrected narrow claim: icon generation is optional presentation data; its
failure degrades the notification to text and does not become a monitor/store
failure.

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: KEEP the optional attachment fallback.
- Safe to mark the original finding verified: YES.

### defensive-021 — SURVIVES

Evidence: URL log append opens an existing file with `try?`, and seek/write/
close operations are best effort (`Sources/greendot/URLOpener.swift:27-37`).
The UI-test dump writer is similarly guarded and contained under the test config
directory (`Sources/greendot/AppDelegate.swift:235-242`). These paths are
diagnostic output, not `PageStore` configuration writes. URL logging and the
workspace fallback are covered by `Tests/greendotTests/URLOpenerTests.swift:5-50`.

Corrected narrow claim: diagnostic URL-log and UI-test dump failures are allowed
to drop output; they must not turn opening a URL or running the app into a
crash.

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: KEEP the best-effort diagnostic I/O.
- Safe to mark the original finding verified: YES.

### defensive-022 — PARTIAL

Evidence: all three parsers use `compactMap` to drop incident/component/service
rows without required names (`Sources/StatusCore/StatuspageParser.swift:28-31,
:52-63`; `InstatusParser.swift:15-32`; `StatuspalParser.swift:14-18,
:31-52`). Provider discriminator/status guards remain strict for Statuspage
`status.indicator` (`StatuspageParser.swift:18-20`), Instatus `page.status`
(`InstatusParser.swift:5-11`), and Statuspal `status_page`
(`StatuspalParser.swift:5-8`). However, page names and page URLs are not
required identity fields: each parser falls back to `sourceURL.host`/`sourceURL`
(`StatuspageParser.swift:22-24`, `InstatusParser.swift:13-14`,
`StatuspalParser.swift:9-12`).

Corrected narrow claim: malformed optional incident/component rows are dropped;
provider marker/status fields reject a response that is not that provider, but
missing page name or URL is intentionally tolerated with a source-URL fallback.

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: KEEP the row filtering; if desired, add tests that distinguish optional page identity fallback from provider rejection.
- Safe to mark the original finding verified: NO (wording was too broad).

### defensive-023 — SURVIVES

Evidence: `ComponentStatus` requires `name`, `severity`, and `statusText`, but
defaults missing `id`, `children`, and `isGroup` (`Sources/StatusCore/Models.swift:34-47`).
`WatchedPage` requires `id`, `url`, and `name`, but defaults missing
`notificationsEnabled` and `disabledComponentNames` and accepts an optional
snapshot (`:154-167`). `PageStore.load()` maps decoding failures to
`StoreError.corrupt` (`Sources/StatusCore/PageStore.swift:56-62`). The old
disabled-name config fixture loads successfully (`Tests/StatusCoreTests/ComponentToggleTests.swift:190-201`).

Corrected narrow claim: optional persisted keys use compatibility defaults, and
missing or malformed required keys fail through `PageStore` as corrupt data.

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: KEEP the defaults; remove them only with an explicit migration and old-file fixture.
- Safe to mark the original finding verified: YES.

### defensive-024 — SURVIVES

Evidence: unknown Statuspage indicator/component values return yellow
(`Sources/StatusCore/StatusMapping.swift:2-17`), and unknown Statuspal incident
types also return yellow (`:31-37`). A `nil` Statuspal incident type returns
green (`:31-35`), matching the documented no-active-incident sentinel
(`docs/superpowers/specs/2026-08-21-status-menu-design.md:78`). Instatus also
defaults unknown page states to yellow (`StatusMapping.swift:40-52`).

Corrected narrow claim: unknown provider values are non-operational yellow;
Statuspal `nil` is a provider-defined known no-incident state, not an unknown
value.

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: KEEP the fail-closed defaults and add explicit cases/tests for future provider values.
- Safe to mark the original finding verified: YES.

### defensive-025 — SURVIVES

Evidence: `grouped` is first filtered to rows where `groupID != nil` and
`!isGroup`, then the dictionary grouping closure force-unwraps that same
optional (`Sources/StatusCore/StatuspageParser.swift:64-66`). The array is not
mutated between the filter and grouping. Nested-group parsing tests pass
(`Tests/StatusCoreTests/ParserTests.swift:26-47`). This is not a force unwrap of
unvalidated external input.

Corrected narrow claim: the unwrap is locally proven by the immediately
preceding filter; a future refactor must preserve that invariant.

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: KEEP; review the invariant if the grouping code is rewritten.
- Safe to mark the original finding verified: YES.

### defensive-026 — SURVIVES

Evidence: URL normalization returns `parts.url` or the original URL
(`Sources/StatusCore/ProviderProbe.swift:116-126`). `PageStore.defaultDirectory`
uses `GREENDOT_CONFIG_DIR` only as an override and otherwise resolves the
documented Application Support path (`Sources/StatusCore/PageStore.swift:36-42`,
`docs/superpowers/specs/2026-08-21-status-menu-design.md:82-86`). The status-menu
fallback `NSMenu()` is used only when AppKit has cleared the assigned menu;
normal setup assigns one at `StatusMenuController.swift:80-85`, and the same
fallback is used for safe path/dump reads (`:71-78`). Missing build metadata
maps to `unknown` (`Sources/greendot/BuildInfo.swift:9-17`).

Corrected narrow claim: these fallbacks preserve an operational/default UI or
metadata value; none silently replaces a user configuration write.

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: KEEP the operational fallbacks.
- Safe to mark the original finding verified: YES.

### defensive-027 — SURVIVES

Evidence: `DirectoryHTTPClient.get` returns 404 only after host-specific and
hostless resolution find no existing path (`Sources/StatusCore/DirectoryHTTPClient.swift:12-25`).
For an existing fixture it directly returns `try Data(contentsOf:)`, so read
errors (including an existing directory or an unreadable file) propagate rather
than becoming empty data (`:16-23`). Path containment and host-component checks
remain enforced (`:27-37`). Tests cover host preference, summary reads, and
path escape (`Tests/StatusCoreTests/ProbeAndMonitorTests.swift:68-126`).

Corrected narrow claim: in the normal non-racy path, absent fixtures map to an
empty 404 response while an observed existing fixture whose read fails throws;
empty data is not used to hide file I/O errors.

- Severity: LOW
- Confidence: CERTAIN
- Recommendation: KEEP the throwing fixture read boundary.
- Safe to mark the original finding verified: YES.

### legacy-002 — SURVIVES

Evidence: `WatchedPage.init(from:)` requires the stable `id`, `url`, and `name`
keys, but uses `decodeIfPresent` defaults for notification state and component
toggle names and accepts an optional snapshot (`Sources/StatusCore/Models.swift:154-167`).
History confirms `disabledComponentNames` was introduced by `0931789`, while
`notificationsEnabled` was already present in the initial `b18e16f` schema;
the decoder still safely handles files omitting either key. The old missing
disabled-name fixture passes (`Tests/StatusCoreTests/ComponentToggleTests.swift:190-201`).

Corrected narrow claim: the decoder preserves earlier files missing the later
component-toggle key (and is tolerant of a missing notification key); in this
repository, notifications were not a later-added field, so that historical
part of the wording should not be overstated.

- Severity: MEDIUM
- Confidence: CERTAIN
- Recommendation: KEEP until an explicit persisted-config migration policy and old-file inventory exist.
- Safe to mark the original finding verified: YES.

### legacy-003 — SURVIVES

Evidence: before nested component groups, `ComponentStatus` had only
`name`, `severity`, and `statusText` (commit `0588846^`). The current custom
decoder still requires those fields and defaults newly added `id`, `children`,
and `isGroup` (`Sources/StatusCore/Models.swift:39-47`). This allows old nested-
group-era snapshots to decode without inventing children or group identity;
`PageStore.load` then applies the corrupt-store boundary for required-key
failures (`Sources/StatusCore/PageStore.swift:56-62`).

Corrected narrow claim: the custom `ComponentStatus` decoder is an active
backward-compatibility shim for pre-`0588846` snapshots; deleting it would make
those persisted snapshots fail to decode.

- Severity: MEDIUM
- Confidence: CERTAIN
- Recommendation: KEEP; add a populated pre-nesting snapshot fixture before any migration replaces it.
- Safe to mark the original finding verified: YES.

### legacy-004 — SURVIVES

Evidence: `AppConfig.currentVersion` and the persisted `version` field have
existed since the initial `b18e16f` format (`Sources/StatusCore/PageStore.swift:3-13`).
`validate` rejects versions newer than the current version on both load and save
(`:65-76`), and the test for version 99 expects `StoreError.corrupt`
(`Tests/StatusCoreTests/ProbeAndMonitorTests.swift:233-237`). No migration
implementation or removal marker exists in the repository history.

Corrected narrow claim: this is an active forward-compatibility boundary, not a
completed migration shim; retain the version field and reject unsupported future
versions until an explicit migration is implemented.

- Severity: MEDIUM
- Confidence: CERTAIN
- Recommendation: KEEP the field and guard; add a migration before accepting a new version.
- Safe to mark the original finding verified: YES.

## Machine-readable result

```json
[
  {"id":"circular-002","disposition":"SURVIVES","evidence":"AppDelegate menu handlers and MenuClickOpener callbacks capture self weakly; event-monitor cleanup is in deinit; menu tracking tests pass.","corrected_claim":"Intentional menu callback loops have no strong self-retaining back-edge in the current code.","severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","verified":true},
  {"id":"circular-003","disposition":"SURVIVES","evidence":"Editor panel/component callbacks capture self weakly; panel generation invalidation and close/deallocation tests pass.","corrected_claim":"The UI callback graph is cyclic as event flow but weak-backed and generation-gated.","severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","verified":true},
  {"id":"dead-001","disposition":"SURVIVES","evidence":"No in-repo use of the internal BuildInfo.gitHash property was found; helper functions and shortHash are used/tested and Makefile injects GitCommitHash.","corrected_claim":"Only the computed property is dead; retain gitHash(from:) and shortHash(from:).","severity":"LOW","confidence":"CERTAIN","recommendation":"REMOVE_PROPERTY","verified":true},
  {"id":"dedup-008","disposition":"SURVIVES","evidence":"The two supplied breakPersistence helpers are exact copies; PanelLifecycleTests has a third semantic variant.","corrected_claim":"Exact two-method duplication is confirmed; consolidation is optional test maintenance.","severity":"LOW","confidence":"CERTAIN","recommendation":"CONSOLIDATE_IF_TOUCHING_TEST_SUPPORT","verified":true},
  {"id":"defensive-016","disposition":"SURVIVES","evidence":"PageStore distinguishes explicit no-such-file errors, rethrows other reads, and maps decode/validation errors to StoreError.corrupt; tests cover the branches.","corrected_claim":"The file/JSON boundary is intentional and fail-visible outside first-run missing-file handling.","severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","verified":true},
  {"id":"defensive-017","disposition":"SURVIVES","evidence":"Provider order, parser misses, Statuspal HTML/API fallback, and cancellation rethrow are implemented and fallback/cancellation paths are tested.","corrected_claim":"Keep provider fallback and cancellation propagation; refine HTTP classification separately.","severity":"LOW","confidence":"HIGH","recommendation":"KEEP","verified":true},
  {"id":"defensive-018","disposition":"SURVIVES","evidence":"Editor/app-shell catches present expected errors, suppress CancellationError outcomes, gate stale/repeated poll errors, and deliver toasts only on accepted success; tests pass.","corrected_claim":"These catches define the expected UI error and poll-result boundary; cancellation after successful monitor return is outside the boundary.","severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","verified":true},
  {"id":"defensive-019","disposition":"SURVIVES","evidence":"Cancellation, poll identity, input revisions, and transition-lock checks guard merge/save; transaction tests cover stale and cancelled polls.","corrected_claim":"Cooperative cancellation is rejected at the commit boundary; stale identity/revision inputs are no-ops, with synchronous save non-interruptible after the check.","severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","verified":true},
  {"id":"defensive-020","disposition":"SURVIVES","evidence":"Attachment conversion/write/creation failures return nil, clean the temporary path when possible, and content delivery continues without an icon.","corrected_claim":"Icon data is optional presentation data and cannot fail persistence or polling.","severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","verified":true},
  {"id":"defensive-021","disposition":"SURVIVES","evidence":"URL-log and UI-test dump writes are guarded try? diagnostic outputs; URL opener tests pass.","corrected_claim":"Diagnostic output may be lost but must not crash URL opening or the app.","severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","verified":true},
  {"id":"defensive-022","disposition":"PARTIAL","evidence":"compactMap drops malformed optional rows and provider marker/status guards reject wrong formats, but page names/URLs intentionally fall back to sourceURL.","corrected_claim":"Row names are required; provider marker/status fields are strict, while page identity name/URL fields are optional with source-URL fallback.","severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP_AND_CLARIFY","verified":false},
  {"id":"defensive-023","disposition":"SURVIVES","evidence":"Optional component and WatchedPage keys use decodeIfPresent defaults; required keys fail through PageStore as StoreError.corrupt; old-config test passes.","corrected_claim":"Persisted optional keys are compatibility defaults and required-key failures remain fail-closed.","severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","verified":true},
  {"id":"defensive-024","disposition":"SURVIVES","evidence":"Unknown status values return yellow; Statuspal nil returns documented green no-incident state; Instatus unknown also returns yellow.","corrected_claim":"Unknown values fail closed to yellow, while Statuspal nil is a known no-incident sentinel.","severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","verified":true},
  {"id":"defensive-025","disposition":"SURVIVES","evidence":"groupID! is applied only after filtering groupID != nil; nested parser tests pass.","corrected_claim":"The force unwrap is locally proven by the preceding filter.","severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","verified":true},
  {"id":"defensive-026","disposition":"SURVIVES","evidence":"URL/config/menu/build metadata fallbacks are explicit, documented, and do not write or replace user config.","corrected_claim":"These are operational/default-value fallbacks, not lost persistence writes.","severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","verified":true},
  {"id":"defensive-027","disposition":"SURVIVES","evidence":"Existing fixture paths use throwing Data(contentsOf:); absent paths return empty 404; path-safety and directory-client tests pass.","corrected_claim":"Observed read failures remain file errors; only normal absent fixture paths map to 404.","severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","verified":true},
  {"id":"legacy-002","disposition":"SURVIVES","evidence":"WatchedPage defaults missing notificationsEnabled/disabledComponentNames and optional snapshot; history confirms disabled names was added later and old fixture passes.","corrected_claim":"The decoder preserves missing later component-toggle keys; notifications were already present in the initial repository schema.","severity":"MEDIUM","confidence":"CERTAIN","recommendation":"KEEP","verified":true},
  {"id":"legacy-003","disposition":"SURVIVES","evidence":"Pre-0588846 ComponentStatus had three fields; current decoding defaults newly added id/children/isGroup and PageStore retains corrupt boundary.","corrected_claim":"The custom decoder is active compatibility for pre-nesting snapshots.","severity":"MEDIUM","confidence":"CERTAIN","recommendation":"KEEP","verified":true},
  {"id":"legacy-004","disposition":"SURVIVES","evidence":"Version field/constant are original format members; validate rejects future versions on load/save and version-99 test passes; no migration exists.","corrected_claim":"The version guard is an active forward-compatibility boundary until explicit migration exists.","severity":"MEDIUM","confidence":"CERTAIN","recommendation":"KEEP","verified":true}
]
```
