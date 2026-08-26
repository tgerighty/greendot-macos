# Defensive Programming Assessment

**Date**: 2026-08-25
**Commit**: `310032baadea24dd7ea32a97ddc5af8df9a52845`
**Scope**: Production Swift in `Sources/StatusCore` and `Sources/greendot`. Tests were read to confirm call paths and expected behaviour. `.git`, `.build`, `greendot.app`, `cleanup-reports/archive-*`, and the generated UI-test Xcode project were excluded from findings.
**Method**: Read every production `do/catch`, `try?`, force unwrap, optional fallback, default path, stale-data path, and related call chain. HTTP, file, JSON, AppKit, ServiceManagement, and user-input boundaries were not treated as removable.
**Verification**: `swift test` passed 150 tests, with 1 intentional skip and 0 failures. No production or test code was changed.

## Executive Summary

There are 27 classified records: 1 HIGH, 9 MEDIUM, and 17 LOW. The classification totals are ERROR-HIDING 5, NEEDS-REFACTOR 9, UNNECESSARY 1, and LEGITIMATE 12. The actionable subset is 15 records (1 HIGH, 9 MEDIUM, 5 LOW). The 12 LEGITIMATE records are recorded so that safe boundary handling is not removed by a later cleanup.

The highest impact is `WatchedPage.displaySeverity`. A missing snapshot or an empty enabled component list becomes green. This can hide a red page-level status and suppress a status-change toast. The next risk is a partial persistence outcome: `PageStore.save` can replace the file and then throw while setting its permissions, leaving memory and disk different. A broad per-page poll catch also turns unexpected errors into a successful grey result.

Top three priorities:

1. Fix the empty/no-snapshot severity path while preserving the intentional green result when a person disables every component (`defensive-001`).
2. Make the atomic write and permission update one recoverable persistence operation (`defensive-003`). Do not remove the `0600` permission requirement.
3. Narrow the poll fallback catch to expected probe failures and retain the grey isolation for those failures (`defensive-004`).

Impact if these are not handled: a real outage can be shown as operational, a failed save can appear to succeed or change only after restart, and an internal probe defect can be hidden as a normal unreachable page.

## Critical Findings

### defensive-001 — HIGH — ERROR-HIDING — empty or missing status becomes green

Evidence: `Sources/StatusCore/Models.swift:123-130`; `Sources/StatusCore/Severity.swift:8-15`.

`enabledComponents` uses `snapshot?.components ?? []`, and `displaySeverity` returns the aggregation of that list unless `isUnreachable` is true. `Aggregator.fromSeverities([])` returns `.green`. Therefore a page with no snapshot, no provider components, or an empty raw component list is shown as green even when a present `PageSnapshot.overall` is yellow or red. `MenuBuilder` and `Monitor.pollToast` consume `displaySeverity`, so the menu icon and toast transition can both miss the page-level outage. Existing tests assert that an empty component aggregation is green, but do not test a red page snapshot with no components.

Classification is ERROR-HIDING. Recommendation is REFACTOR. Distinguish these cases explicitly: no snapshot should be unknown/grey, an empty raw component list should use `snapshot.overall`, and a non-empty list with all components disabled may remain green by design. Removing the empty-list fallback without this distinction would break the user feature that disables all components and would remove useful UI state.

## Medium Findings

### defensive-002 — MEDIUM — ERROR-HIDING — missing component status defaults to operational

Evidence: `Sources/StatusCore/StatuspageParser.swift:52-61`; `Sources/StatusCore/InstatusParser.swift:21-31`.

Both parsers convert a missing `status` field to the literal operational value. That is different from an unknown status, which the mappings treat as yellow. A schema change or partial response can therefore mark a component green. If the page indicator is red and the component list is present, the component aggregation can hide the page condition as described in `defensive-001`.

Classification is ERROR-HIDING. Recommendation is REFACTOR. Keep the provider parsing boundary, but preserve missing as unknown/yellow or reject the row. Removing parser tolerance would turn a partial response into a hard provider failure and would be a larger behaviour change.

### defensive-003 — MEDIUM — NEEDS-REFACTOR — save can throw after replacing the file

Evidence: `Sources/StatusCore/PageStore.swift:65-70`; callers commit only after `store.save` at `Sources/StatusCore/Monitor.swift:250-266` and `:291-301`.

`Data.write(..., .atomic)` can replace `config.json` before `setAttributes(..., 0o600)` runs. If the final attribute update fails, `save` throws even though the new content is already on disk. `Monitor` then keeps the old in-memory config. The UI reports a save error, but a restart can load the new config. Poll results can have the same split.

Classification is NEEDS-REFACTOR. Recommendation is REFACTOR. Keep the permission control. Write a temporary file, set and verify its permissions, then replace the destination, or restore the previous file if the final step fails. Removing `setAttributes` would avoid the exception but can expose the configuration with weaker permissions.

### defensive-004 — MEDIUM — NEEDS-REFACTOR — broad poll catch hides unexpected errors

Evidence: `Sources/StatusCore/Monitor.swift:194-225`.

The catch converts every non-cancellation error from `ProviderProbe.probeHit` into a grey, unreachable snapshot and returns it as a successful poll result. This is correct for expected network and unsupported-provider failures, but it also hides an unexpected parser, transport, or future programming error. `AppDelegate.pollAndRefresh` then has no error to present.

Classification is NEEDS-REFACTOR. Recommendation is REFACTOR. Keep the grey isolation for `ProbeError` and rethrow or record unexpected errors. Removing the fallback for all errors would make one transient page failure abort the poll, so a blanket removal is unsafe.

### defensive-006 — MEDIUM — ERROR-HIDING — first-run seed failure is discarded

Evidence: `Sources/greendot/AppDelegate.swift:114-122`; `Monitor.add` throws from probe and store paths at `Sources/StatusCore/Monitor.swift:54-68`.

The documented first-launch OpenAI seed uses `try?`. A network, format, cancellation, or persistence failure leaves an empty menu with no log or user message. The current `loadSucceeded` gate prevents the older corrupt-store overwrite path; this finding is the independent seed failure path.

Classification is ERROR-HIDING. Recommendation is ADD_HANDLING. Keep the seed optional and non-blocking, but log the failure or present a non-fatal message so the person knows why the default page is absent.

### defensive-007 — MEDIUM — ERROR-HIDING — launch-at-login state is committed before registration succeeds

Evidence: `Sources/StatusCore/Monitor.swift:43-51`; `Sources/greendot/LaunchAtLogin.swift:9-15`.

The first-run flag is saved as true before `onLaunchAtLoginEnable` calls `SMAppService.register`. If registration fails, `LaunchAtLogin` only logs the error. The saved flag prevents the first-run path from trying again on the next launch, even though launch at login is still disabled. A save failure is also caught and returned without any caller-visible result.

Classification is ERROR-HIDING. Recommendation is REFACTOR. Track an attempted state separately, or save the flag only after a successful registration and provide a retry or user message. Do not remove the ServiceManagement catch; registration remains an external system boundary.

### defensive-008 — LOW — ERROR-HIDING — optional panel callbacks report false success or silent no-op

Evidence: `Sources/greendot/PagePanelController.swift:22-36` and `:182-188`.

When an editing panel is built without `onToggleComponent` or `onSetAll`, the picker receives closures that return true without changing the monitor. When `onRemove` is absent, the remove button is still built for a page and the action returns false without an explanation. The production editor currently supplies these callbacks, but this initializer permits a future caller to show controls that do not persist.

Classification is ERROR-HIDING. Recommendation is REFACTOR. Require mutation handlers for editing mode, or hide the related controls when a handler is absent. Removing the defaults may expose a wiring error at compile time, but it must be replaced with an explicit UI state rather than a crash.

### defensive-009 — MEDIUM — NEEDS-REFACTOR — notification delivery errors are not exposed

Evidence: `Sources/greendot/SystemToastDelivery.swift:5-13`, `:31-40`, `:93-105`, and `:122-127`.

The notification adapter exposes `add` without a completion, and the live implementation discards the completion-based error from `UNUserNotificationCenter`. Permission `Bool` is also ignored; only a non-nil permission error is logged. A notification can therefore fail because of denial or invalid content while the poll still appears successful and no delivery diagnostic is recorded.

Classification is NEEDS-REFACTOR. Recommendation is ADD_HANDLING. Add an asynchronous completion to the adapter and log or otherwise record delivery errors. Keep notification failure out of the poll transaction; making a toast failure fail status persistence would lose the correct boundary.

### defensive-010 — MEDIUM — NEEDS-REFACTOR — poll interval accepts invalid numeric values

Evidence: `Sources/greendot/AppDelegate.swift:55-60`.

`Double.init` only handles a non-numeric value. Zero, negative, NaN, and infinite values are not rejected before `Timer.scheduledTimer`. A bad environment value can cause a tight poll loop or an invalid timer interval. This is configuration input, not a reason to remove the default.

Classification is NEEDS-REFACTOR. Recommendation is REFACTOR. Accept only finite values greater than zero and use 60 seconds for all other values. Removing the default would make a malformed test or deployment environment prevent polling entirely.

### defensive-011 — MEDIUM — NEEDS-REFACTOR — user URL validation does not enforce HTTP(S)

Evidence: `Sources/greendot/PagePanelController.swift:150-159`; the transport maps a non-HTTP response to status zero at `Sources/StatusCore/HTTPClient.swift:14-17`.

The editor checks that the URL parses and has a host, but it does not restrict the scheme to `http` or `https`. The URL can then reach `URLSessionHTTPClient`. A non-HTTP response is silently represented as status zero and later becomes a provider miss/unsupported result. Depending on the URL scheme and platform handling, this can read an unintended local resource or produce a misleading format error.

Classification is NEEDS-REFACTOR. Recommendation is ADD_HANDLING. Enforce the same HTTP(S) allowlist used by `URLOpener`, and handle a non-HTTP response explicitly. Keep the network boundary and its thrown errors; this is validation and error classification, not removal of I/O handling.

### defensive-015 — MEDIUM — NEEDS-REFACTOR — server errors are classified as unsupported format

Evidence: `Sources/StatusCore/ProviderProbe.swift:142-160`.

Every status other than 200 returns `.miss`. A 5xx or rate-limit response sets `sawHTTP`, so after the provider attempts the add/edit flow throws `ProbeError.unsupported` rather than `ProbeError.unreachable`. The poll flow then greys the page, but the user-facing editor gives the wrong cause and may suggest that the URL is not a supported provider.

Classification is NEEDS-REFACTOR. Recommendation is REFACTOR. Keep 404 and provider-mismatch responses as misses, but classify 5xx, 429, and status zero as network/unreachable outcomes. This preserves, rather than removes, the HTTP boundary.

## Low / Debatable Findings

### defensive-005 — LOW — NEEDS-REFACTOR — unreachable snapshot keeps partial stale data

Evidence: `Sources/StatusCore/Monitor.swift:211-224`; the menu renders components from the snapshot at `Sources/greendot/MenuBuilder.swift:102-126`.

On a probe failure the code sets `isUnreachable` and clears incidents, but copies the previous components. The menu therefore shows an `Unreachable` row and old component statuses without a timestamp or stale marker. This may be useful context, but it is a partial stale snapshot and can be read as current data.

Classification is NEEDS-REFACTOR. Recommendation is REVIEW. Keep the fallback if the product wants component context while offline; add a clear stale indication or clear all provider data consistently. Removing the copied components would lose useful context and could make component editing less usable during an outage.

### defensive-012 — LOW — NEEDS-REFACTOR — launch-at-login toggle failure is only logged

Evidence: `Sources/greendot/LaunchAtLogin.swift:18-30`; the menu ignores the result at `Sources/greendot/AppDelegate.swift:156-159`.

`toggle()` returns false after logging, but the menu action rebuilds without presenting any feedback. The person can click the setting and see no reason why the state did not change.

Classification is NEEDS-REFACTOR. Recommendation is ADD_HANDLING. Keep the catch and log, and add a small user-facing error or an explicit disabled/approval state. Removing the catch would make a ServiceManagement failure escape an AppKit action.

### defensive-013 — LOW — NEEDS-REFACTOR — parser errors collapse into provider misses

Evidence: `Sources/StatusCore/ProviderProbe.swift:151-159`.

A 200 response that fails a parser is silently converted to `.miss`. This is needed to try the other provider formats, but the final result loses whether the server returned malformed data or a valid different provider. On add/edit this can become `unsupported`; on poll it becomes grey through `Monitor`.

Classification is NEEDS-REFACTOR. Recommendation is REVIEW. Preserve the fallback order, but retain the last parse reason for diagnostics or a more precise final error. Removing the parse fallback would stop valid provider detection when an earlier format does not match.

### defensive-014 — LOW — UNNECESSARY — static regex compilation uses try?

Evidence: `Sources/StatusCore/ProviderProbe.swift:222-228`.

The regular expression is a source-code literal. `try?` makes a programmer error disable Statuspal HTML extraction and return nil with no diagnostic. The normal path is covered by `PollPerformanceTests`.

Classification is UNNECESSARY. Recommendation is REVIEW. Use explicit one-time initialization or a checked programmer-error path. Do not replace it with an unconditional force unwrap without considering the startup-crash risk.

### defensive-016 — LOW — LEGITIMATE — missing-file and corrupt-store handling

Evidence: `Sources/StatusCore/PageStore.swift:44-62`.

Missing `config.json` returns an empty first-run configuration. Other read errors are rethrown, and decode/validation errors become `StoreError.corrupt`. `AppDelegate.loadMonitor` presents those errors. This is the correct file and JSON boundary.

Classification is LEGITIMATE. Recommendation is KEEP. Removing the missing-file distinction would make first launch fail; removing the thrown corrupt-store error would hide data loss.

### defensive-017 — LOW — LEGITIMATE — provider probing fallback and network isolation

Evidence: `Sources/StatusCore/ProviderProbe.swift:89-103`, `:177-213`.

Trying providers in order, treating a wrong-format response as a miss, and continuing after a Statuspal HTML fetch failure are intentional provider and network boundaries. Cancellation is rethrown by `throwIfCancelled`.

Classification is LEGITIMATE. Recommendation is KEEP. The HTTP status refinement is tracked separately as `defensive-015`; the fallback itself must not be removed.

### defensive-018 — LOW — LEGITIMATE — user-facing operation catches and poll error gate

Evidence: `Sources/greendot/StatusPageEditor.swift:94-118`; `Sources/greendot/AppDelegate.swift:73-80` and `:252-276`.

Add/edit and synchronous menu mutations present errors. Poll cancellation is ignored by design, other poll errors are presented once until a successful poll, and toasts are delivered only on success. These catches preserve the UI boundary and the current transaction behaviour.

Classification is LEGITIMATE. Recommendation is KEEP. Do not replace these catches with uncaught task errors.

### defensive-019 — LOW — LEGITIMATE — cancellation and stale-poll transaction guards

Evidence: `Sources/StatusCore/Monitor.swift:141-167` and `:269-303`; recent cancellation work is covered by `MonitorRefreshTransactionTests`.

`Task.checkCancellation`, poll identity, input revisions, and the lock boundary prevent an older or cancelled poll from committing. Empty results for a stale poll are an intentional no-op, not an ignored failure.

Classification is LEGITIMATE. Recommendation is KEEP. Removing these guards can reintroduce the lost-update behaviour covered by the current tests.

### defensive-020 — LOW — LEGITIMATE — notification attachment degradation

Evidence: `Sources/greendot/SystemToastDelivery.swift:141-159`.

Attachment conversion or temporary-file creation can fail. The code removes the temporary file when possible and still sends the notification without an icon. The attachment is optional presentation data, so this fallback does not hide status persistence.

Classification is LEGITIMATE. Recommendation is KEEP. Do not make an icon failure fail the notification or poll.

### defensive-021 — LOW — LEGITIMATE — UI-test and URL-log best-effort I/O

Evidence: `Sources/greendot/URLOpener.swift:27-37`; `Sources/greendot/AppDelegate.swift:235-242`.

`GREENDOT_OPEN_URL_LOG` and UI-test dump paths are diagnostic outputs. `try?` cleanup, seek, write, and dump operations must not crash the app. Production URL opening uses `NSWorkspace` when the test log path is absent.

Classification is LEGITIMATE. Recommendation is KEEP. These are test/diagnostic I/O boundaries, not configuration persistence.

### defensive-022 — LOW — LEGITIMATE — parser row filtering

Evidence: `Sources/StatusCore/StatuspageParser.swift:28-31` and `:52-63`; `Sources/StatusCore/InstatusParser.swift:15-24`; `Sources/StatusCore/StatuspalParser.swift:15-18` and `:31-51`.

`compactMap` drops malformed incident or component rows without required names. This is partial provider JSON handling. Required page identity and status fields still throw or reject the provider.

Classification is LEGITIMATE. Recommendation is KEEP. Do not turn a malformed optional row into a crash; the missing component-status case is separately tracked as `defensive-002`.

### defensive-023 — LOW — LEGITIMATE — Codable compatibility defaults

Evidence: `Sources/StatusCore/Models.swift:39-46` and `:159-166`.

Optional persisted keys such as component IDs, children, `isGroup`, notification preference, and disabled names use compatibility defaults. Required fields still throw and `PageStore` maps the failure to corrupt data.

Classification is LEGITIMATE. Recommendation is KEEP. Removing these defaults would break older saved configurations; adding validation must remain fail-closed for required fields.

### defensive-024 — LOW — LEGITIMATE — fail-closed status mappings

Evidence: `Sources/StatusCore/StatusMapping.swift:2-17`, `:31-37`, and `:40-52`.

Unknown provider status strings map to yellow, not green. A nil Statuspal incident type maps to green because the provider uses nil for no active incident. These are deliberate domain defaults and are safer than treating unknown values as operational.

Classification is LEGITIMATE. Recommendation is KEEP. Provider-specific changes should add explicit cases and tests rather than delete the default.

### defensive-025 — LOW — LEGITIMATE — proven force unwrap in group construction

Evidence: `Sources/StatusCore/StatuspageParser.swift:64-66`.

`groupID!` follows a filter that requires `groupID != nil`; the unwrap is logically proven within the expression. It is not an ignored error or an external-data force unwrap.

Classification is LEGITIMATE. Recommendation is KEEP. A later refactor must preserve the filter or replace the unwrap with a safe grouping key.

### defensive-026 — LOW — LEGITIMATE — normal UI and URL fallback paths

Evidence: `Sources/StatusCore/ProviderProbe.swift:116-126`; `Sources/StatusCore/PageStore.swift:36-42`; `Sources/greendot/StatusMenuController.swift:71-103` and `:125-129`; `Sources/greendot/BuildInfo.swift:9-18`.

URL normalization falls back to the original valid URL, the config directory has a documented application-support default, menu actions use an empty menu only if AppKit has unexpectedly cleared the assigned menu, and build metadata uses `unknown` when absent. These paths preserve operation without discarding a user data write.

Classification is LEGITIMATE. Recommendation is KEEP. The configuration and AppKit contracts should be tested if their ownership changes.

### defensive-027 — LOW — LEGITIMATE — fixture file I/O remains throwing

Evidence: `Sources/StatusCore/DirectoryHTTPClient.swift:12-24`.

The UI-test directory client returns 404 for a missing fixture and propagates a read error for a fixture that exists but cannot be read. This preserves the HTTP/file boundary and allows the probe to classify the failure.

Classification is LEGITIMATE. Recommendation is KEEP. Do not replace the throwing reads with empty data.

## Recommendations

1. Separate no snapshot, empty provider components, and all-components-disabled in `WatchedPage.displaySeverity`. Use the page-level severity when component data is absent.
2. Make `PageStore.save` recoverable across the permission step. Preserve atomic replacement and mode `0600`.
3. Narrow `Monitor.pollResult` to expected `ProbeError` values and retain an observable path for unexpected errors. Keep grey isolation for expected fetch failures.
4. Classify HTTP 5xx, 429, and non-HTTP responses as reachability failures, while retaining 404/provider misses for provider probing.
5. Surface or log first-run seed and launch-at-login failures. Do not mark launch-at-login complete before registration succeeds.
6. Remove success-valued callback defaults from editing controls. Require handlers or hide controls when no persistence path exists.
7. Add completion-based notification error handling without making notification delivery part of the poll transaction.
8. Validate `GREENDOT_POLL_SECONDS` as finite and positive, and enforce HTTP(S) for entered status URLs.

## Out of Scope / Flagged for Review

- The current transactional and cancellation changes are intentional. The related tests pass and are classified LEGITIMATE in `defensive-019`.
- File, HTTP, JSON, ServiceManagement, and AppKit boundaries are not candidates for deletion. The report recommends narrower classification or diagnostics only.
- `defensive-005`, `defensive-013`, and `defensive-014` need product-owner or maintainer review because they trade graceful fallback against diagnostic precision.
- Test-only cleanup `try?` sites and test fixture force unwraps were not treated as production findings.
- No formal validation, release approval, or external-service delivery guarantee was inferred from local tests.

## Independent Verification Disposition

The mandatory gate selected 17 of 27 records. Independent verifiers confirmed 16; those records now have `verified: true`. 10 lower-confidence records remain provisional.

The verifier found `defensive-022` only partial. It has been narrowed to `UNCERTAIN` / `REVIEW`, with the counterevidence recorded in the machine-readable detail.

Verification evidence: [verification-batch-1.md](verification-batch-1.md), [verification-batch-2.md](verification-batch-2.md).

Final machine-readable severity counts: HIGH 1, MEDIUM 10, LOW 16. The original prose above records the specialist's pre-verification assessment; this disposition and the JSON block below are authoritative after verification.
 
## Machine-Readable Findings

```json
{"findings":[{"id":"defensive-001","file":"Sources/StatusCore/Models.swift","line":127,"severity":"HIGH","confidence":"CERTAIN","recommendation":"REFACTOR","detail":"Missing snapshot/all-disabled components become green and page-level overall is ignored, which can hide an outage and suppress a toast.","classification":"ERROR-HIDING","verified":true},{"id":"defensive-002","file":"Sources/StatusCore/StatuspageParser.swift","line":59,"severity":"MEDIUM","confidence":"LIKELY","recommendation":"REFACTOR","detail":"Missing component status defaults to operational here and at InstatusParser.swift:24, while unknown status maps to yellow. Partial or changed provider data can make a component green and hide a page-level outage. Keep the parser boundary but preserve missing as unknown or reject the row.","classification":"ERROR-HIDING","verified":false},{"id":"defensive-003","file":"Sources/StatusCore/PageStore.swift","line":70,"severity":"MEDIUM","confidence":"LIKELY","recommendation":"REFACTOR","detail":"Atomic Data.write can replace config.json before setAttributes throws. Monitor then keeps old memory while disk contains new data. Preserve 0600 permissions, but stage and verify the file before replacement or restore the old file on failure.","classification":"NEEDS-REFACTOR","verified":false},{"id":"defensive-004","file":"Sources/StatusCore/Monitor.swift","line":207,"severity":"MEDIUM","confidence":"LIKELY","recommendation":"REFACTOR","detail":"The broad pollResult catch maps every non-cancellation probe error to a successful grey snapshot. Expected ProbeError isolation is correct, but unexpected parser or programming errors are hidden from AppDelegate. Narrow the catch and retain the expected fallback.","classification":"NEEDS-REFACTOR","verified":false},{"id":"defensive-005","file":"Sources/StatusCore/Monitor.swift","line":216,"severity":"LOW","confidence":"UNCERTAIN","recommendation":"REVIEW","detail":"An unreachable snapshot copies old components but clears incidents. Menu code can show stale component status without a stale marker. Keep the context fallback if it is intended, but make stale state explicit or clear provider data consistently.","classification":"NEEDS-REFACTOR","verified":false},{"id":"defensive-006","file":"Sources/greendot/AppDelegate.swift","line":121,"severity":"MEDIUM","confidence":"CERTAIN","recommendation":"ADD_HANDLING","detail":"Seed probe and persistence failures are discarded while startup remains non-blocking.","classification":"ERROR-HIDING","verified":true},{"id":"defensive-007","file":"Sources/StatusCore/Monitor.swift","line":47,"severity":"MEDIUM","confidence":"LIKELY","recommendation":"REFACTOR","detail":"The first-run flag is saved before LaunchAtLogin.enable calls SMAppService.register. A registration failure is only logged, so the saved flag can prevent a later retry; a save failure is also returned with no caller signal. Track success separately or retry and report.","classification":"ERROR-HIDING","verified":false},{"id":"defensive-008","file":"Sources/greendot/PagePanelController.swift","line":34,"severity":"LOW","confidence":"LIKELY","recommendation":"REFACTOR","detail":"Missing component callbacks default to true-valued no-op closures, and a missing remove callback returns false while the edit remove button is still rendered. A caller can show controls that do not persist. Require handlers or hide controls.","classification":"ERROR-HIDING","verified":false},{"id":"defensive-009","file":"Sources/greendot/SystemToastDelivery.swift","line":38,"severity":"MEDIUM","confidence":"LIKELY","recommendation":"ADD_HANDLING","detail":"The notification adapter drops UNUserNotificationCenter.add completion errors and ignores a denied authorization Bool. Incident toasts can fail with no delivery diagnostic. Add asynchronous error logging without making notification delivery fail the poll transaction.","classification":"NEEDS-REFACTOR","verified":false},{"id":"defensive-010","file":"Sources/greendot/AppDelegate.swift","line":57,"severity":"MEDIUM","confidence":"CERTAIN","recommendation":"REFACTOR","detail":"Parsed non-finite and non-positive poll intervals bypass the 60-second fallback.","classification":"NEEDS-REFACTOR","verified":true},{"id":"defensive-011","file":"Sources/greendot/PagePanelController.swift","line":157,"severity":"MEDIUM","confidence":"UNCERTAIN","recommendation":"ADD_HANDLING","detail":"The editor validates URL syntax and host but not HTTP(S), while URLSessionHTTPClient maps non-HTTP responses to status zero. Enforce the HTTP(S) allowlist and classify non-HTTP transport explicitly. Keep the network boundary.","classification":"NEEDS-REFACTOR","verified":false},{"id":"defensive-012","file":"Sources/greendot/LaunchAtLogin.swift","line":27,"severity":"LOW","confidence":"LIKELY","recommendation":"ADD_HANDLING","detail":"LaunchAtLogin.toggle logs and returns false, but AppDelegate ignores the result. A failed user action has no visible explanation. Keep the ServiceManagement catch and add user feedback or an approval state.","classification":"NEEDS-REFACTOR","verified":false},{"id":"defensive-013","file":"Sources/StatusCore/ProviderProbe.swift","line":154,"severity":"LOW","confidence":"LIKELY","recommendation":"REVIEW","detail":"A 200 response that fails a parser becomes a provider miss, losing the malformed-data reason when the final error is unsupported or grey. Preserve provider fallback, but retain the last parse reason for diagnostics.","classification":"NEEDS-REFACTOR","verified":false},{"id":"defensive-014","file":"Sources/StatusCore/ProviderProbe.swift","line":224,"severity":"MEDIUM","confidence":"CERTAIN","recommendation":"REVIEW","detail":"A malformed source regex silently disables HTML Statuspal extraction.","classification":"UNNECESSARY","verified":true},{"id":"defensive-015","file":"Sources/StatusCore/ProviderProbe.swift","line":145,"severity":"MEDIUM","confidence":"CERTAIN","recommendation":"REFACTOR","detail":"5xx/429 are treated like 404/provider misses and can end as unsupported.","classification":"NEEDS-REFACTOR","verified":true},{"id":"defensive-016","file":"Sources/StatusCore/PageStore.swift","line":48,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"The file/JSON boundary is intentional and fail-visible outside first-run missing-file handling.","classification":"LEGITIMATE","verified":true},{"id":"defensive-017","file":"Sources/StatusCore/ProviderProbe.swift","line":177,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Keep provider fallback and cancellation propagation; refine HTTP classification separately.","classification":"LEGITIMATE","verified":true},{"id":"defensive-018","file":"Sources/greendot/StatusPageEditor.swift","line":103,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"These catches define the expected UI error and poll-result boundary; cancellation after successful monitor return is outside the boundary.","classification":"LEGITIMATE","verified":true},{"id":"defensive-019","file":"Sources/StatusCore/Monitor.swift","line":277,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Cooperative cancellation is rejected at the commit boundary; stale identity/revision inputs are no-ops, with synchronous save non-interruptible after the check.","classification":"LEGITIMATE","verified":true},{"id":"defensive-020","file":"Sources/greendot/SystemToastDelivery.swift","line":156,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Icon data is optional presentation data and cannot fail persistence or polling.","classification":"LEGITIMATE","verified":true},{"id":"defensive-021","file":"Sources/greendot/URLOpener.swift","line":31,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Diagnostic output may be lost but must not crash URL opening or the app.","classification":"LEGITIMATE","verified":true},{"id":"defensive-022","file":"Sources/StatusCore/StatuspageParser.swift","line":28,"severity":"LOW","confidence":"UNCERTAIN","recommendation":"REVIEW","detail":"Row names are required; provider marker/status fields are strict, while page identity name/URL fields are optional with source-URL fallback. Independent verifier disposition: PARTIAL. compactMap drops malformed optional rows and provider marker/status guards reject wrong formats, but page names/URLs intentionally fall back to sourceURL.","classification":"LEGITIMATE","verified":false},{"id":"defensive-023","file":"Sources/StatusCore/Models.swift","line":44,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Persisted optional keys are compatibility defaults and required-key failures remain fail-closed.","classification":"LEGITIMATE","verified":true},{"id":"defensive-024","file":"Sources/StatusCore/StatusMapping.swift","line":7,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Unknown values fail closed to yellow, while Statuspal nil is a known no-incident sentinel.","classification":"LEGITIMATE","verified":true},{"id":"defensive-025","file":"Sources/StatusCore/StatuspageParser.swift","line":65,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"The force unwrap is locally proven by the preceding filter.","classification":"LEGITIMATE","verified":true},{"id":"defensive-026","file":"Sources/StatusCore/ProviderProbe.swift","line":117,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"These are operational/default-value fallbacks, not lost persistence writes.","classification":"LEGITIMATE","verified":true},{"id":"defensive-027","file":"Sources/StatusCore/DirectoryHTTPClient.swift","line":18,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Observed read failures remain file errors; only normal absent fixture paths map to 404.","classification":"LEGITIMATE","verified":true}]}
```
