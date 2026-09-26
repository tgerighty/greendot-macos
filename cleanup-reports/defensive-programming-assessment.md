Ponytail: full intensity — climb the YAGNI ladder; prefer reuse, stdlib, and native features; use minimal diffs; preserve trust-boundary validation, security, and accessibility.

# Defensive Programming Assessment

## Executive Summary

- Total issues found: **9**. Severity: **HIGH=1, MEDIUM=6, LOW=2**. These counts refer to the numbered findings below.
- Priority 1: Review the automatic TLS trust exception for Icinga URLs. It selects custom trust handling through a URL heuristic. `Sources/StatusCore/HTTPClient.swift:116`, `Sources/StatusCore/HTTPAuth.swift:23`, `Sources/StatusCore/ProviderProbe+Icinga.swift:4`.
- Priority 2: Stop malformed provider data from becoming an operational result. Keep valid empty results and optional descriptive fields. `Sources/StatusCore/OktaParser.swift:71`, `Sources/StatusCore/StatuspageParser.swift:47`, `Sources/StatusCore/InstatusParser.swift:24`, `Sources/StatusCore/IncidentioParser.swift:14`.
- Priority 3: Expose failures to restore settings or restrict file permissions. Keep the existing recovery attempts. `Sources/StatusCore/PageStore.swift:206`, `Sources/StatusCore/PageStore.swift:110`, `Sources/StatusCore/PageStore.swift:238`.
- Estimated implementation scope: roughly **80–160 production lines across 14 files**, plus focused checks. This is an estimate, not a proposed patch. The affected sites appear in findings defensive-001 through defensive-009.
- Most boundary handling should stay. Provider detection, cancellation, damaged-cache recovery, and stale-operation guards serve explicit behavior. `Sources/StatusCore/ProviderProbe.swift:147`, `Sources/StatusCore/PageStore.swift:126`, `Sources/StatusCore/Monitor+Polling.swift:122`, `Sources/greendot/PagePanelController.swift:169`.

### Scope, pre-flight, and method

This is the Agent 6 analysis at the supplied tip `9320756`. It is report-only. No source, dependency, or configuration changes are proposed as completed work.

The package uses Swift and targets macOS 13. It separates `StatusCore`, the AppKit executable, and test targets. `Package.swift:1`, `Package.swift:6`, `Package.swift:8`, `Package.swift:14`, `Sources/greendot/main.swift:1`.

The repository supplies `swift test` and `swiftlint lint --strict`. SwiftLint includes Sources and Tests. `Makefile:12`, `Makefile:18`, `.swiftlint.yml:1`.

Read-only pre-flight command results: `rg` and `python3` were available. `swift`, `swiftlint`, `swiftformat`, `cloc`, `shellcheck`, `ruff`, and `pylint` were absent from PATH. No tools were installed. No build or test command ran.

The analysis read the production Swift files and inspected relevant tests. Searches covered `catch`, `try?`, `try!`, defaults, optional values, early returns, and unchecked results. Findings below follow the input, fallback, and displayed or persisted result. The examples are source traces, **not executed Swift reproductions**. Every JSON finding has `verified: false`. Independent verification remains a later stage.

## Critical Findings

### defensive-001 — HIGH — NEEDS-REFACTOR: automatic bypass of server trust validation

**Evidence.** The authentication delegate uses `.useCredential` for a server-trust challenge when `TLSTrust` accepts the request URL. It uses default handling only otherwise. `Sources/StatusCore/HTTPClient.swift:116`, `Sources/StatusCore/HTTPClient.swift:120`, `Sources/StatusCore/HTTPClient.swift:123`.

The trust decision delegates directly to `isIcingaAPI`. That matcher accepts a `/v1` path with port 5665, or a host containing `icinga`. It does not inspect the certificate. `Sources/StatusCore/HTTPAuth.swift:23`, `Sources/StatusCore/ProviderProbe+Icinga.swift:4`.

**Lost protection and consequence.** A URL classification substitutes for normal server trust validation. Requests can carry Basic authorization generated from URL credentials. This creates a credential-exposure risk if the server is impersonated. No network attack was attempted. `Sources/StatusCore/HTTPClient.swift:81`, `Sources/StatusCore/HTTPClient.swift:116`, `Sources/StatusCore/HTTPAuth.swift:10`.

**Counter-evidence and risk.** The exception is deliberate: a test explicitly expects insecure TLS for an Icinga URL. A change can break installations that depend on that exception. `Tests/StatusCoreTests/HTTPAuthTests.swift:23`.

**Minimum recommendation.** Reuse the existing `.performDefaultHandling` branch for server trust. Do not treat the provider matcher as a trust decision. Check deployment compatibility before replacing this deliberate behavior. Keep authentication and redirect restrictions. `Sources/StatusCore/HTTPClient.swift:123`, `Sources/StatusCore/HTTPClient.swift:103`, `Sources/StatusCore/HTTPAuth.swift:8`.

## Medium Findings

### defensive-002 — MEDIUM — ERROR-HIDING: malformed Okta JSON becomes an empty healthy result

**Evidence.** `array` discards JSON decoding errors and failed array casts through `try?` and `?? []`. Both incident and planned-outage data use this function. `Sources/StatusCore/OktaParser.swift:9`, `Sources/StatusCore/OktaParser.swift:10`, `Sources/StatusCore/OktaParser.swift:70`.

**Source trace.** An incidents span containing `[` passes the prefix check, then fails JSON decoding and becomes an empty array. With no planned outages, the parser returns a reachable snapshot with no components. The empty component aggregate is green. `Sources/StatusCore/OktaParser.swift:74`, `Sources/StatusCore/OktaParser.swift:80`, `Sources/StatusCore/OktaParser.swift:71`, `Sources/StatusCore/OktaParser.swift:18`, `Sources/StatusCore/ComponentTree.swift:28`.

**Lost error and consequence.** Invalid JSON, an object instead of an array, or a failed array-element cast can hide incident data. The successful snapshot can also enter the body cache. `Sources/StatusCore/OktaParser.swift:71`, `Sources/StatusCore/ProviderProbe+Okta.swift:32`, `Sources/StatusCore/ProviderProbe+Okta.swift:40`.

**Minimum recommendation.** Make the existing array helper throw for present, invalid data. Let the existing probe failure path handle it. Preserve valid empty arrays, resolved incidents, and the optional absence of planned outages. `Sources/StatusCore/ProviderProbe+Okta.swift:42`, `Sources/StatusCore/ProviderProbe+Okta.swift:19`, `Sources/StatusCore/OktaParser.swift:27`, `Tests/StatusCoreTests/OktaParserTests.swift:33`.

**Check and change risk.** Check malformed JSON, object JSON, and mixed array elements against valid empty and resolved-only inputs. Removing error suppression must not remove parsing validation or change resolved-incident filtering. `Sources/StatusCore/OktaParser.swift:26`, `Sources/StatusCore/OktaParser.swift:71`, `Tests/StatusCoreTests/OktaParserTests.swift:33`.

### defensive-003 — MEDIUM — ERROR-HIDING: missing component status becomes operational

**Evidence.** Statuspage defaults a missing or wrongly typed component status to `operational`. Instatus does the same with `OPERATIONAL`. Both values map to green. `Sources/StatusCore/StatuspageParser.swift:47`, `Sources/StatusCore/StatusMapping.swift:13`, `Sources/StatusCore/InstatusParser.swift:24`, `Sources/StatusCore/InstatusParser.swift:27`.

**Source trace.** A Statuspage payload with `status.indicator = critical` and one component containing only `name = API` produces a green component. Once components exist, `displaySeverity` uses their aggregate instead of `snapshot.overall`. An Instatus `HASISSUES` page has the equivalent path. `Sources/StatusCore/StatuspageParser.swift:25`, `Sources/StatusCore/StatuspageParser.swift:42`, `Sources/StatusCore/Models.swift:131`, `Sources/StatusCore/InstatusParser.swift:38`.

**Lost error and consequence.** Missing or wrongly typed status data becomes an operational assertion. The page can display green despite a non-green page summary. `Sources/StatusCore/Models.swift:128`, `Sources/StatusCore/ComponentTree.swift:47`, `Sources/greendot/MenuBuilder.swift:88`.

**Minimum recommendation.** Replace only the operational defaults with a conservative unknown value that reaches the existing yellow mapping. Alternatively, reject malformed component records through the existing parser error path. Keep component selection behavior. `Sources/StatusCore/StatusMapping.swift:16`, `Sources/StatusCore/InstatusParser.swift:30`, `Sources/StatusCore/Models.swift:132`.

**Check and change risk.** Check missing, null, and wrongly typed status values through both the parser and `WatchedPage.displaySeverity`. Keep normal operational values green. `Tests/StatusCoreTests/ParserTests.swift:5`, `Sources/StatusCore/Models.swift:128`.

### defensive-004 — MEDIUM — ERROR-HIDING: malformed incident collections become “no incidents”

**Evidence and source traces.** Each example below supplies valid JSON with a wrongly typed collection. The cited casts replace that collection with `[]`.

| Parser | Example input | Result path |
|---|---|---|
| incident.io | `{"summary":{"ongoing_incidents":{}}}` | Empty components, green aggregate, reachable snapshot. `Sources/StatusCore/IncidentioParser.swift:14`, `Sources/StatusCore/IncidentioParser.swift:19`. |
| Apple | `{"services":[{"serviceName":"Example","events":{}}]}` | Empty events remove the service group, then the empty page aggregate is green. `Sources/StatusCore/AppleParser.swift:23`, `Sources/StatusCore/AppleParser.swift:39`, `Sources/StatusCore/AppleParser.swift:14`. |
| Heroku | `{"status":[{"system":"Example","status":"green"}],"incidents":{}}` | The incident collection disappears, leaving the green system leaf. `Sources/StatusCore/HerokuParser.swift:19`, `Sources/StatusCore/HerokuParser.swift:42`, `Sources/StatusCore/StatusMapping.swift:113`. |

**Lost error and consequence.** These parsers cannot distinguish a failed collection cast from a valid empty incident list. They return successful snapshots. `Sources/StatusCore/IncidentioParser.swift:22`, `Sources/StatusCore/AppleParser.swift:17`, `Sources/StatusCore/HerokuParser.swift:50`.

**Minimum recommendation.** At each existing parser boundary, reject a present collection with the wrong type. Keep valid empty arrays. Retain supported missing-field behavior until its contract is checked. Do not introduce a general validation framework. `Sources/StatusCore/IncidentioParser.swift:5`, `Sources/StatusCore/AppleParser.swift:5`, `Sources/StatusCore/HerokuParser.swift:5`.

**Counter-evidence and check.** Valid empty arrays and resolved events intentionally produce green results. Check malformed collections separately from those cases. `Tests/StatusCoreTests/IncidentioParserTests.swift:7`, `Tests/StatusCoreTests/AppleParserTests.swift:7`, `Tests/StatusCoreTests/AppleParserTests.swift:38`.

### defensive-005 — MEDIUM — ERROR-HIDING: rollback failure is discarded

**Evidence.** After a state-file write fails, `save` calls `restoreConfig` and rethrows the original error. `restoreConfig` ignores failures to remove, rewrite, or restrict the config file. `Sources/StatusCore/PageStore.swift:206`, `Sources/StatusCore/PageStore.swift:238`, `Sources/StatusCore/PageStore.swift:240`, `Sources/StatusCore/PageStore.swift:243`, `Sources/StatusCore/PageStore.swift:244`.

**Lost error and consequence.** If restoration also fails, the caller receives no indication that config recovery failed. The monitor keeps its previous in-memory config because it assigns the new config only after `store.save` returns successfully. Disk and memory can therefore disagree. This is a conditional failure path, not a reproduced disk fault. `Sources/StatusCore/Monitor+Mutations.swift:144`, `Sources/StatusCore/Monitor+Mutations.swift:146`, `Sources/StatusCore/Monitor+Mutations.swift:149`.

**Minimum recommendation.** Keep restoration. Report a restoration error together with the initial save failure. Make the existing UI error path state that recovery failed and a reload is needed. Avoid a new transaction subsystem. `Sources/StatusCore/PageStore.swift:206`, `Sources/greendot/AppDelegate.swift:328`, `Sources/greendot/StatusPageEditor.swift:146`.

**Counter-evidence and check.** Existing tests cover failed state writes with successful config restoration or removal. They assert that the original config survives. Add a separate check where restoration itself fails before claiming that recovery always succeeds. `Tests/StatusCoreTests/StateFileSplitTests.swift:153`, `Tests/StatusCoreTests/StateFileSplitTests.swift:174`.

**Change risk.** Simply removing the catch or rollback would weaken protection against data loss. Preserve both the initial error and the recovery attempt. `Sources/StatusCore/PageStore.swift:199`, `Sources/StatusCore/PageStore.swift:205`, `Sources/StatusCore/PageStore.swift:207`.

### defensive-006 — MEDIUM — ERROR-HIDING: permission-hardening failures are silent

**Evidence.** `tightenPermissions` ignores both `setAttributes` errors. Its regular-file check also converts attribute-read failure to false. Loading continues without reporting either failure. `Sources/StatusCore/PageStore.swift:90`, `Sources/StatusCore/PageStore.swift:112`, `Sources/StatusCore/PageStore.swift:115`, `Sources/StatusCore/PageStore.swift:122`.

**Lost error and consequence.** If a readable file has wider permissions and the app cannot restrict them, loading can succeed while those permissions remain. The settings documentation promises immediate restriction. URLs can contain authentication data. `Sources/StatusCore/PageStore.swift:108`, `Sources/StatusCore/PageStore.swift:109`, `docs/settings-files.md:10`, `README.md:59`.

**Minimum recommendation.** Preserve best-effort loading, but report failure to enforce mode `0600`. Identify the affected file and error category without logging file contents or credential-bearing URLs. Reuse native error reporting. `Sources/StatusCore/PageStore.swift:109`, `Sources/greendot/AppDelegate.swift:16`.

**Counter-evidence and check.** Tests prove successful permission restriction, including unchanged bytes. They do not exercise the failure path within those tests. Check a readable file whose mode cannot be changed. Preserve the regular-file guard so directory execute bits remain intact. `Tests/StatusCoreTests/StateFileSplitTests.swift:213`, `Tests/StatusCoreTests/StateFileSplitTests.swift:232`, `Sources/StatusCore/PageStore.swift:119`.

### defensive-007 — MEDIUM — NEEDS-REFACTOR: notification submission has no error channel

**Evidence.** The notification adapter declares `add` with no result or completion. Its live implementation calls `center.add(request)` without a completion handler. `Sources/greendot/SystemToastDelivery.swift:10`, `Sources/greendot/SystemToastDelivery.swift:42`.

**Consequence.** `deliver` records an identifier and schedules removal without observing submission success. A failed submission has no route to a diagnostic in this code. This affects the system-delivered recovery toast. Persistent issue panels use a separate path. `Sources/greendot/SystemToastDelivery.swift:116`, `Sources/greendot/SystemToastDelivery.swift:126`, `Sources/greendot/SystemToastDelivery.swift:132`, `Sources/StatusCore/ToastPolicy.swift:22`.

**Minimum recommendation.** Observe the native submission completion in the live adapter and log an error category. Follow the nearby authorization-error pattern. Add a completion to the protocol only if callers need recovery behavior. Do not add retries or a delivery queue. `Sources/greendot/SystemToastDelivery.swift:42`, `Sources/greendot/SystemToastDelivery.swift:179`.

**Check and limitation.** The current double records submitted requests and cannot report submission failure. Existing assertions verify requests and scheduling. They do not prove OS delivery. Confirm the native failure callback on macOS before implementation. `Tests/greendotTests/ToastDeliveryDoubles.swift:42`, `Tests/greendotTests/SystemToastDeliveryTests.swift:64`.

## Low / Debatable Findings

### defensive-008 — LOW — ERROR-HIDING: first-run save failure has no diagnostic

**Evidence.** First-run setup catches every persistence error and returns false. It then skips the launch-at-login callback. The method returns no error to either caller. `Sources/StatusCore/Monitor+Mutations.swift:27`, `Sources/StatusCore/Monitor+Mutations.swift:35`, `Sources/StatusCore/Monitor+Mutations.swift:39`, `Sources/greendot/AppDelegate.swift:52`, `Sources/greendot/AppDelegate+Config.swift:52`.

**Consequence and counter-evidence.** The feature can remain disabled without a setup-specific diagnostic. However, the method correctly avoids enabling it after a failed save, and a later call can retry. The test explicitly preserves that behavior. `Tests/StatusCoreTests/MonitorFirstRunTests.swift:52`, `Tests/StatusCoreTests/MonitorFirstRunTests.swift:76`.

**Minimum recommendation.** Keep the nonfatal return. Add a native diagnostic for the save failure. Do not enable the login item when persistence fails. The app already uses native logging for optional startup failures. `Sources/StatusCore/Monitor+Mutations.swift:35`, `Sources/greendot/AppDelegate.swift:22`, `Sources/greendot/LaunchAtLogin.swift:13`.

### defensive-009 — LOW — UNNECESSARY: fallback branches cover fixed internal invariants

| Site | Evidence | Minimum recommendation and risk |
|---|---|---|
| Positive pulse interval | `interval` is a static constant set to 30, but the display path tests `interval > 0`. `Sources/StatusCore/GreyPulse.swift:4`, `Sources/StatusCore/GreyPulse.swift:15`. | Remove only the constant comparison if this function changes. Keep `hasUnreachable`. Validate again if the interval becomes configurable. |
| RSS hub status bounds | Each completed feed iteration appends one body and one status in both success and catch branches. The consumer still substitutes status 0 for a missing index. `Sources/StatusCore/ProviderProbe+RSS.swift:165`, `Sources/StatusCore/ProviderProbe+RSS.swift:170`, `Sources/StatusCore/ProviderProbe+RSS.swift:175`, `Sources/StatusCore/ProviderProbe+RSS.swift:189`. | Direct indexing expresses the current invariant. A later unequal-array bug would trap instead of becoming a synthetic network failure. |
| RSS hub cache status bounds | The private cache helper receives the same arrays from that loop and repeats the fallback. `Sources/StatusCore/ProviderProbe+RSS.swift:179`, `Sources/StatusCore/ProviderProbe+RSS.swift:260`, `Sources/StatusCore/ProviderProbe+RSS.swift:264`. | Remove the fallback only while this remains the sole call path. No new collection abstraction is needed. |

These are optional local simplifications. They do not justify an independent refactor. The HTTP-status, cancellation, and failed-feed handling must remain. `Sources/StatusCore/ProviderProbe+RSS.swift:168`, `Sources/StatusCore/ProviderProbe+RSS.swift:173`, `Sources/StatusCore/ProviderProbe+RSS.swift:215`.

## Recommendations

1. Review defensive-001 before deleting any transport guards. Reuse system trust handling and retain origin restrictions. `Sources/StatusCore/HTTPClient.swift:103`, `Sources/StatusCore/HTTPClient.swift:116`.
2. Correct defensive-002 through defensive-004 at the existing parser boundaries. Reuse current errors and severity mappings. Keep valid empty feeds and optional metadata. `Sources/StatusCore/ParserError.swift:3`, `Sources/StatusCore/StatusMapping.swift:11`, `Tests/StatusCoreTests/AppleParserTests.swift:7`.
3. Correct defensive-005 and defensive-006 in `PageStore`. Keep recovery and private-file handling, but expose failures. `Sources/StatusCore/PageStore.swift:110`, `Sources/StatusCore/PageStore.swift:206`, `Sources/StatusCore/PageStore.swift:238`.
4. Add narrow diagnostics for defensive-007 and defensive-008. Existing native logging is sufficient. `Sources/greendot/SystemToastDelivery.swift:179`, `Sources/greendot/LaunchAtLogin.swift:13`.
5. Consider defensive-009 only during related maintenance. Its small reductions do not address the higher-impact failures. `Sources/StatusCore/GreyPulse.swift:15`, `Sources/StatusCore/ProviderProbe+RSS.swift:189`.
6. On macOS, run the relevant parser, persistence, notification, and first-run checks before applying a recommendation. The repository test entry point is `make test`. `Makefile:12`, `Tests/StatusCoreTests/OktaParserTests.swift:7`, `Tests/StatusCoreTests/StateFileSplitTests.swift:153`, `Tests/greendotTests/SystemToastDeliveryTests.swift:44`, `Tests/StatusCoreTests/MonitorFirstRunTests.swift:52`.

### Defensive-pattern inventory: keep or review

This inventory groups repeated patterns by purpose. Numbered findings above cover the actionable exceptions. “LEGITIMATE” means keep the boundary or recovery behavior, not remove its guard.

| Pattern and sites | Classification | Reason and removal risk |
|---|---|---|
| Missing config versus other read errors. `Sources/StatusCore/PageStore.swift:76`. | LEGITIMATE | Only missing-file errors create an empty config. Other I/O errors propagate. Removing this distinction risks treating unreadable settings as a new installation. |
| Config decoding and version validation. `Sources/StatusCore/PageStore.swift:94`, `Sources/StatusCore/PageStore.swift:97`, `Sources/StatusCore/PageStore.swift:264`. | LEGITIMATE | Invalid settings become a visible store error. Keep the checks even though the low-level decoder detail is replaced. |
| ID-repair save, cache read, and cache decode fallbacks. `Sources/StatusCore/PageStore.swift:103`, `Sources/StatusCore/PageStore.swift:129`, `Sources/StatusCore/PageStore.swift:134`. | LEGITIMATE | Failed repair still leaves unique in-memory IDs. Bad cache data does not destroy settings. Tests preserve both policies. `Tests/StatusCoreTests/PageStoreValidationTests.swift:121`, `Tests/StatusCoreTests/StateFileSplitTests.swift:47`. |
| ID-normalization inspection and parsed UUID checks. `Sources/StatusCore/PageStore.swift:175`, `Sources/StatusCore/PageStore.swift:179`, `Sources/StatusCore/PageStore.swift:180`. | LEGITIMATE | This controls whether a repair write is needed after typed decoding. Duplicate IDs must not reach the dictionary initializer. `Sources/StatusCore/Monitor+Mutations.swift:12`. |
| Save pre-read and changed-file refusal. `Sources/StatusCore/PageStore.swift:190`, `Sources/StatusCore/PageStore.swift:215`. | LEGITIMATE | Refuse to overwrite unreadable or externally changed settings. The contract has a direct test. `Tests/StatusCoreTests/ChangedOnDiskTests.swift:18`. |
| Best-effort removal of a directory at the cache path. `Sources/StatusCore/PageStore.swift:231`, `Sources/StatusCore/PageStore.swift:233`. | LEGITIMATE | A failed removal reaches the subsequent throwing write. The comment states this recovery path. `Sources/StatusCore/PageStore.swift:229`, `Sources/StatusCore/PageStore.swift:205`. |
| Compare-before-write fallback. `Sources/StatusCore/PageStore.swift:257`. | LEGITIMATE | A failed comparison read does not return saved success. The write and permission update can still throw. `Sources/StatusCore/PageStore.swift:258`, `Sources/StatusCore/PageStore.swift:261`. |
| Poll interval, legacy snapshot, and legacy launch flag defaults. `Sources/StatusCore/StateFile.swift:49`, `Sources/StatusCore/StateFile.swift:53`, `Sources/StatusCore/Models.swift:177`. | LEGITIMATE | These are documented compatibility rules. Settings fields still reject wrong types. `docs/settings-files.md:63`, `docs/settings-files.md:210`, `Tests/StatusCoreTests/LegacyFieldTests.swift:85`. |
| Missing IDs, component children, notification preference, and disabled-name defaults. `Sources/StatusCore/Models.swift:56`, `Sources/StatusCore/Models.swift:170`, `Sources/StatusCore/Models.swift:174`, `Sources/StatusCore/StateFile.swift:31`. | LEGITIMATE | These decode absent fields from persisted input. Removing defaults would reject accepted partial or older files. `docs/settings-files.md:65`, `docs/settings-files.md:202`. |
| Provider parse miss and transport failure conversion. `Sources/StatusCore/ProviderProbe.swift:168`, `Sources/StatusCore/ProviderProbe.swift:171`, `Sources/StatusCore/ProviderProbe.swift:197`, `Sources/StatusCore/ProviderProbe+JSONLandings.swift:205`, `Sources/StatusCore/ProviderProbe+JSONLandings.swift:208`, `Sources/StatusCore/ProviderProbe+Statusio.swift:16`. | LEGITIMATE | Discovery tries more than one format. Network failures affect the final error. Cancellation propagates. `Sources/StatusCore/ProviderProbe+Hit.swift:37`, `Sources/StatusCore/ProviderProbe.swift:108`, `Sources/StatusCore/ProviderProbe.swift:219`. |
| Known-provider parse and transport catches. `Sources/StatusCore/ProviderProbe+AWS.swift:48`, `Sources/StatusCore/ProviderProbe+AWS.swift:51`, `Sources/StatusCore/ProviderProbe+Okta.swift:42`, `Sources/StatusCore/ProviderProbe+Okta.swift:45`, `Sources/StatusCore/ProviderProbe+Salesforce.swift:45`, `Sources/StatusCore/ProviderProbe+Salesforce.swift:48`, `Sources/StatusCore/ProviderProbe+Icinga.swift:52`, `Sources/StatusCore/ProviderProbe+Icinga.swift:55`, `Sources/StatusCore/ProviderProbe+Icinga.swift:57`. | LEGITIMATE | Failed known-provider probes lead to errors, not fabricated green snapshots. Icinga authentication failures remain distinct. `Sources/StatusCore/ProviderProbe+AWS.swift:25`, `Sources/StatusCore/ProviderProbe+Okta.swift:19`, `Sources/StatusCore/ProviderProbe+Salesforce.swift:19`, `Sources/StatusCore/ProviderProbe+Icinga.swift:87`. |
| RSS fetch, hub, and parse catches. `Sources/StatusCore/ProviderProbe+RSS.swift:31`, `Sources/StatusCore/ProviderProbe+RSS.swift:151`, `Sources/StatusCore/ProviderProbe+RSS.swift:172`, `Sources/StatusCore/ProviderProbe+RSS.swift:230`, `Sources/StatusCore/ProviderProbe+RSS.swift:283`, `Sources/StatusCore/RssParser.swift:15`. | LEGITIMATE | Failed feeds become probe misses or visibly grey groups. A hub with no parsed feed returns no hit. `Sources/StatusCore/ProviderProbe+RSS.swift:194`, `Sources/StatusCore/ProviderProbe+RSS.swift:235`. |
| Poll error to grey snapshot. `Sources/StatusCore/Monitor+Polling.swift:83`. | LEGITIMATE | Failure remains visible through `isUnreachable`, rather than preserving a healthy status. Cancellation still throws. `Sources/StatusCore/Monitor+Polling.swift:58`, `Sources/StatusCore/Monitor+Polling.swift:84`. |
| Confirmation timeout, empty stream, and non-network errors. `Sources/StatusCore/Monitor+PollConfirmation.swift:66`, `Sources/StatusCore/Monitor+PollConfirmation.swift:74`, `Sources/StatusCore/Monitor+PollConfirmation.swift:78`, `Sources/StatusCore/Monitor+PollConfirmation.swift:97`. | LEGITIMATE | Inconclusive confirmation keeps the mixed poll result. It must not invent a total outage. The timeout and cancellation tests cover that contract. `Tests/StatusCoreTests/PollConfirmationTests.swift:80`, `Tests/StatusCoreTests/PollConfirmationTests.swift:104`. |
| Page-existence checks before and after an asynchronous probe. `Sources/StatusCore/Monitor+Mutations.swift:60`, `Sources/StatusCore/Monitor+Mutations.swift:66`. | LEGITIMATE | The page can disappear while the probe awaits. These checks protect different moments. |
| Poll identity, input revision, and panel generation guards. `Sources/StatusCore/Monitor+Polling.swift:122`, `Sources/StatusCore/Monitor+Polling.swift:157`, `Sources/greendot/PagePanelController.swift:169`. | LEGITIMATE | These discard stale asynchronous results. Removing them can commit an obsolete operation. |
| Load, mutation, and editor catches. `Sources/greendot/AppDelegate.swift:88`, `Sources/greendot/AppDelegate.swift:328`, `Sources/greendot/StatusPageEditor.swift:117`, `Sources/greendot/StatusPageEditor.swift:146`. | LEGITIMATE | Errors reach `presentError`. Cancelled editor tasks return without an alert. |
| Startup seed and refresh catches. `Sources/greendot/AppDelegate.swift:114`, `Sources/greendot/AppDelegate.swift:116`, `Sources/greendot/AppDelegate.swift:360`, `Sources/greendot/AppDelegate.swift:362`. | LEGITIMATE | Seed failures are logged. Refresh failures reach the UI with suppression of repeated alerts. `Sources/greendot/AppDelegate.swift:22`, `Sources/greendot/AppDelegate.swift:367`. |
| Login-item registration and toggle catches. `Sources/greendot/LaunchAtLogin.swift:13`, `Sources/greendot/LaunchAtLogin.swift:27`. | LEGITIMATE | The optional feature logs errors. The menu reads actual service status. Do not remove these catches. `Sources/greendot/LaunchAtLogin.swift:5`, `Sources/greendot/AppDelegate.swift:132`. |
| Notification permission and optional image recovery. `Sources/greendot/SystemToastDelivery.swift:180`, `Sources/greendot/SystemToastDelivery.swift:209`, `Sources/greendot/SystemToastDelivery.swift:222`, `Sources/greendot/SystemToastDelivery.swift:223`. | LEGITIMATE recovery | Permission errors are logged. Image failure retains text content and removes the temporary file when possible. Image diagnostics are absent but have no demonstrated delivery defect here. `Sources/greendot/SystemToastDelivery.swift:167`, `Sources/greendot/SystemToastDelivery.swift:173`. |
| Test-hook dump and URL-log I/O suppression. `Sources/greendot/AppDelegate.swift:257`, `Sources/greendot/URLOpener.swift:33`, `Sources/greendot/URLOpener.swift:34`, `Sources/greendot/URLOpener.swift:35`, `Sources/greendot/URLOpener.swift:36`, `Sources/greendot/URLOpener.swift:38`. | REVIEW, test support only | Errors can hide test-harness failures. The log test asserts the expected bytes. No product cleanup is justified from these hooks alone. `Sources/greendot/AppDelegate.swift:208`, `Tests/greendotTests/URLOpenerTests.swift:13`. |
| Fixed regular expressions compiled with `try?`. `Sources/StatusCore/ProviderProbe.swift:227`, `Sources/StatusCore/ProviderProbe+Statusio.swift:56`, `Sources/StatusCore/ProviderProbe+RSS.swift:301`, `Sources/StatusCore/ProviderProbe+RSSHTML.swift:42`, `Sources/StatusCore/ProviderProbe+RSSHTML.swift:54`. | REVIEW, no current failure established | Compile failure would disable discovery or markup filtering. Do not replace these with unchecked crashes or remove HTML filtering from an analysis-only result. `Sources/StatusCore/ProviderProbe.swift:234`, `Sources/StatusCore/ProviderProbe+RSS.swift:307`, `Sources/StatusCore/ProviderProbe+RSSHTML.swift:66`. |
| Optional snapshots, weak UI references, absent screens, and unnamed metadata. `Sources/StatusCore/Models.swift:129`, `Sources/greendot/AppDelegate.swift:76`, `Sources/greendot/PersistentToastPresenter.swift:141`, `Sources/greendot/BuildInfo.swift:6`, `Sources/StatusCore/StatuspageParser.swift:11`. | LEGITIMATE | These values are optional at their boundary or lifetime. No non-null invariant was established that permits removing their guards. |
| Conservative unknown statuses and provider-specific RSS defaults. `Sources/StatusCore/StatusMapping.swift:54`, `Sources/StatusCore/StatusMapping.swift:74`, `Sources/StatusCore/StatusMapping.swift:85`, `Sources/StatusCore/StatusMapping.swift:176`, `Sources/StatusCore/RssParser.swift:107`. | LEGITIMATE | Unknown mapped statuses remain yellow. Generic RSS and AWS RSS have different tested missing-status rules. `Tests/StatusCoreTests/RssParserGuardTests.swift:78`, `Tests/StatusCoreTests/RssParserGuardTests.swift:90`. |
| Redirect, XML, file-path, and URL-opening guards. `Sources/StatusCore/HTTPClient.swift:17`, `Sources/StatusCore/RssParser.swift:13`, `Sources/StatusCore/PathSafety.swift:4`, `Sources/StatusCore/DirectoryHTTPClient.swift:36`, `Sources/greendot/URLOpener.swift:15`. | LEGITIMATE, security boundary | Keep origin checks, external-entity suppression, path containment, credential stripping, and the HTTP(S) allowlist. `Sources/StatusCore/HTTPAuth.swift:4`, `Sources/greendot/URLOpener.swift:24`. |
| Accessibility and text alternatives. `Sources/greendot/StatusDot.swift:22`, `Sources/greendot/PersistentToastPresenter.swift:193`, `Sources/greendot/PersistentToastPresenter.swift:209`, `Sources/greendot/AppEditMenu.swift:39`. | LEGITIMATE, preserve | Keep descriptions, the accessible press action, and native editing commands during any cleanup. |

## Out of Scope / Flagged for Review

- **Provider record-skipping policy.** AWS explicitly tests dropping an event without an ARN. Do not broadly replace `compactMap` with strict decoding from this report. The same review question applies to malformed record entries in Salesforce, Google, and Icinga. `Tests/StatusCoreTests/AwsParserTests.swift:134`, `Sources/StatusCore/SalesforceParser.swift:8`, `Sources/StatusCore/GoogleParser.swift:8`, `Sources/StatusCore/IcingaParser.swift:43`.
- **Optional metadata versus status evidence.** Fallback display names, links, and child lists can preserve useful parent status. They are not equivalent to the false operational defaults in defensive-003. `Sources/StatusCore/SalesforceParser.swift:55`, `Tests/StatusCoreTests/SalesforceParserTests.swift:86`, `Sources/StatusCore/FlashdutyParser.swift:12`.
- **Diagnostic detail lost during provider discovery.** The pipeline reports unsupported or unreachable rather than the original parser error. This is not evidence that the catch should be removed. More precise diagnostics would be a separate product decision. `Sources/StatusCore/ProviderProbe.swift:108`, `Sources/StatusCore/ProviderProbe.swift:168`, `Sources/StatusCore/Monitor+Polling.swift:83`.
- **Broader save atomicity.** The config write occurs before the state-write recovery block. A config permission error after its data write is not covered by that recovery block. This deserves a focused persistence investigation, rather than an untested transaction redesign here. `Sources/StatusCore/PageStore.swift:199`, `Sources/StatusCore/PageStore.swift:204`, `Sources/StatusCore/PageStore.swift:258`, `Sources/StatusCore/PageStore.swift:261`.
- **Process interruption between writes.** The repository already documents this limit. This assessment does not propose a journal or a database. `docs/settings-files.md:219`.
- **Runtime verification.** Swift tests, AppKit behavior, native notification failures, and file-permission faults were not executed on this host. The project requires macOS and Xcode. `README.md:30`. The cited permission-failure tests also skip when run as root. `Tests/StatusCoreTests/StateFileSplitTests.swift:154`.
- **Other cleanup domains.** Type consolidation, duplication, dead code, architecture, performance, and full accessibility testing are outside this assessment. The checks and handlers cited above must remain during later changes. `Sources/StatusCore/PathSafety.swift:4`, `Sources/greendot/PersistentToastPresenter.swift:209`.

## Machine-Readable Findings

```json
{"findings": [
  {"id": "defensive-001", "file": "Sources/StatusCore/HTTPClient.swift", "line": 116, "severity": "HIGH", "confidence": "CERTAIN", "recommendation": "NEEDS-REFACTOR", "detail": "Server-trust handling uses a credential exception selected by an Icinga URL heuristic instead of default validation; reuse default handling after checking the deliberate compatibility policy (Sources/StatusCore/HTTPAuth.swift:23; Sources/StatusCore/ProviderProbe+Icinga.swift:4; Tests/StatusCoreTests/HTTPAuthTests.swift:23).", "verified": false},
  {"id": "defensive-002", "file": "Sources/StatusCore/OktaParser.swift", "line": 71, "severity": "MEDIUM", "confidence": "CERTAIN", "recommendation": "NEEDS-REFACTOR", "detail": "Invalid embedded JSON or a failed incident-array cast becomes an empty array and can produce a reachable green snapshot; propagate malformed-present-data errors while preserving valid empty results (Sources/StatusCore/OktaParser.swift:18; Sources/StatusCore/ComponentTree.swift:28).", "verified": false},
  {"id": "defensive-003", "file": "Sources/StatusCore/StatuspageParser.swift", "line": 47, "severity": "MEDIUM", "confidence": "CERTAIN", "recommendation": "NEEDS-REFACTOR", "detail": "Missing or wrongly typed component status defaults to operational in Statuspage and Instatus, and component aggregation can override a non-green page summary; use conservative existing mappings or reject malformed records (Sources/StatusCore/InstatusParser.swift:24; Sources/StatusCore/Models.swift:131).", "verified": false},
  {"id": "defensive-004", "file": "Sources/StatusCore/IncidentioParser.swift", "line": 14, "severity": "MEDIUM", "confidence": "CERTAIN", "recommendation": "NEEDS-REFACTOR", "detail": "Wrongly typed incident collections become empty in incident.io, Apple, and Heroku parsers and can yield green results; reject present invalid collection types while preserving valid empty arrays (Sources/StatusCore/AppleParser.swift:23; Sources/StatusCore/HerokuParser.swift:19).", "verified": false},
  {"id": "defensive-005", "file": "Sources/StatusCore/PageStore.swift", "line": 238, "severity": "MEDIUM", "confidence": "CERTAIN", "recommendation": "NEEDS-REFACTOR", "detail": "Config restoration suppresses remove, write, and permission errors, so a failed rollback is not reported alongside the original state-write failure; retain recovery and expose both failures (Sources/StatusCore/PageStore.swift:206; Sources/StatusCore/Monitor+Mutations.swift:146).", "verified": false},
  {"id": "defensive-006", "file": "Sources/StatusCore/PageStore.swift", "line": 112, "severity": "MEDIUM", "confidence": "CERTAIN", "recommendation": "NEEDS-REFACTOR", "detail": "Permission hardening silently ignores attribute-read and chmod failures while loading continues; preserve best-effort loading and report inability to enforce private file mode without logging contents (Sources/StatusCore/PageStore.swift:115; Sources/StatusCore/PageStore.swift:122; docs/settings-files.md:10).", "verified": false},
  {"id": "defensive-007", "file": "Sources/greendot/SystemToastDelivery.swift", "line": 42, "severity": "MEDIUM", "confidence": "LIKELY", "recommendation": "NEEDS-REFACTOR", "detail": "The live notification adapter submits requests without observing completion and the wrapper exposes no error channel; add a narrow native submission diagnostic and confirm failure behavior on macOS (Sources/greendot/SystemToastDelivery.swift:10; Sources/greendot/SystemToastDelivery.swift:132).", "verified": false},
  {"id": "defensive-008", "file": "Sources/StatusCore/Monitor+Mutations.swift", "line": 35, "severity": "LOW", "confidence": "CERTAIN", "recommendation": "NEEDS-REFACTOR", "detail": "First-run setup silently discards persistence failures; retain the nonfatal return and the rule against enabling login after a failed save, but add a diagnostic (Tests/StatusCoreTests/MonitorFirstRunTests.swift:52).", "verified": false},
  {"id": "defensive-009", "file": "Sources/StatusCore/GreyPulse.swift", "line": 15, "severity": "LOW", "confidence": "CERTAIN", "recommendation": "REVIEW", "detail": "A positive static pulse constant and RSS hub arrays populated together have redundant fallback checks; consider local simplification only during related work, preserving boundary checks (Sources/StatusCore/GreyPulse.swift:4; Sources/StatusCore/ProviderProbe+RSS.swift:165; Sources/StatusCore/ProviderProbe+RSS.swift:189; Sources/StatusCore/ProviderProbe+RSS.swift:264).", "verified": false}
]}
```
