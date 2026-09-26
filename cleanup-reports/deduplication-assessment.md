Ponytail full intensity: remove useful duplication with existing code first; keep small, clear copies when a shared helper adds more complexity.

# Deduplication Assessment

## Executive Summary

- Total patterns found: **12**. Severity: **HIGH=1, MEDIUM=3, LOW=8**. The main repeated work is the single-response probe flow and the cache-hit check (`Sources/StatusCore/ProviderProbe+AWS.swift:28`, `Sources/StatusCore/ProviderProbe+Salesforce.swift:22`, `Sources/StatusCore/ProviderProbe+Okta.swift:22`, `Sources/StatusCore/ProviderProbe+RSS.swift:179`).
- Priorities: (1) use the existing `probeJSON` flow for AWS, Salesforce, and Okta; (2) share the cache-hit check that remains; (3) use the existing `JSONScalar.nonempty` in Salesforce (`Sources/StatusCore/ProviderProbe+JSONLandings.swift:182`, `Sources/StatusCore/ProviderProbe+Icinga.swift:38`, `Sources/StatusCore/StatusioParser.swift:62`, `Sources/StatusCore/SalesforceParser.swift:74`).
- Estimated impact: the first two changes would touch about seven source files and could remove roughly 60–80 lines. This is an estimate from the current probe bodies and cache checks, not a measured patch (`Sources/StatusCore/ProviderProbe+AWS.swift:28`, `Sources/StatusCore/ProviderProbe+Salesforce.swift:22`, `Sources/StatusCore/ProviderProbe+Okta.swift:22`, `Sources/StatusCore/ProviderProbe+JSONLandings.swift:182`, `Sources/StatusCore/ProviderProbe+Icinga.swift:38`, `Sources/StatusCore/ProviderProbe+RSS.swift:179`, `Sources/StatusCore/ProviderProbe.swift:79`).
- Method: read-only line-block matching with Python's standard library and direct source review. This is a Swift package, and its existing test targets separate `StatusCoreTests` from `greendotTests` (`Package.swift:1`, `Package.swift:15`, `Package.swift:19`).

## Critical Findings

### dedup-001 — HIGH — CONSOLIDATE — repeated single-response probe flow

`probeAWS`, `probeSalesforce`, and `probeOkta` each fetch one URL, check cancellation, record HTTP status, build the same status-prefixed cache body, reuse a reachable prior snapshot, parse the body, and record a network error on failure (`Sources/StatusCore/ProviderProbe+AWS.swift:28`, `Sources/StatusCore/ProviderProbe+Salesforce.swift:22`, `Sources/StatusCore/ProviderProbe+Okta.swift:22`). The existing `probeJSON(_:sourceURL:context:flags:parse:)` already performs that sequence (`Sources/StatusCore/ProviderProbe+JSONLandings.swift:182`).

Replace only the three inner probe bodies with calls to that helper. Pass `awsCurrentEventsURL` and `awsClickURL(context.base)` for AWS, `salesforceActiveIncidentsURL` and `context.base` for Salesforce, and `context.base` for both Okta URL arguments; keep each parser callback (`Sources/StatusCore/ProviderProbe+AWS.swift:33`, `Sources/StatusCore/ProviderProbe+AWS.swift:46`, `Sources/StatusCore/ProviderProbe+Salesforce.swift:27`, `Sources/StatusCore/ProviderProbe+Salesforce.swift:40`, `Sources/StatusCore/ProviderProbe+Okta.swift:27`, `Sources/StatusCore/ProviderProbe+Okta.swift:40`). `probeJSON` normalizes the source URL before parsing, so check AWS's click URL and Okta's page URL while applying the change (`Sources/StatusCore/ProviderProbe+JSONLandings.swift:203`, `Sources/StatusCore/ProviderProbe+AWS.swift:63`, `Sources/StatusCore/ProviderProbe+Okta.swift:27`). Keep the landing guards and final-error handling at their present call sites (`Sources/StatusCore/ProviderProbe+AWS.swift:17`, `Sources/StatusCore/ProviderProbe+Salesforce.swift:11`, `Sources/StatusCore/ProviderProbe+Okta.swift:11`). Existing tests cover cache reuse and HTTP failure paths (`Tests/StatusCoreTests/AwsProbeTests.swift:123`, `Tests/StatusCoreTests/SalesforceProbeTests.swift:95`, `Tests/StatusCoreTests/OktaProbeTests.swift:67`).

## Medium Findings

### dedup-002 — MEDIUM — CONSOLIDATE — repeated reachable-cache check

The same prior-body and reachable-snapshot check appears in `probeJSON`, Icinga, the Microsoft RSS hub, and the RSS feed hit path (`Sources/StatusCore/ProviderProbe+JSONLandings.swift:195`, `Sources/StatusCore/ProviderProbe+Icinga.swift:38`, `Sources/StatusCore/ProviderProbe+RSS.swift:180`, `Sources/StatusCore/ProviderProbe+RSS.swift:273`). The three probes in dedup-001 also have this copy today (`Sources/StatusCore/ProviderProbe+AWS.swift:38`, `Sources/StatusCore/ProviderProbe+Salesforce.swift:32`, `Sources/StatusCore/ProviderProbe+Okta.swift:32`).

After dedup-001, put a small `cachedHit(for body: Data) -> ProbeHit?` method on `ProbeContext`, which already stores both prior values (`Sources/StatusCore/ProviderProbe.swift:79`). Replace the four remaining repeated checks with a call to it. Pass each path's existing cache body: RSS feeds include the source URL, the Microsoft hub includes feed separators, and Icinga joins two responses (`Sources/StatusCore/ProviderProbe+RSS.swift:288`, `Sources/StatusCore/ProviderProbe+RSS.swift:260`, `Sources/StatusCore/ProviderProbe+Icinga.swift:34`). Keep the separate `attempt` check: it uses raw response bytes, returns `AttemptResult`, and has no `ProbeContext` argument (`Sources/StatusCore/ProviderProbe.swift:147`, `Sources/StatusCore/ProviderProbe.swift:160`).

### dedup-010 — MEDIUM — CONSOLIDATE — repeated Statuspage test payloads

Four test classes contain the same green Statuspage JSON; two also contain the same red JSON (`Tests/StatusCoreTests/ProbeAndMonitorTests.swift:6`, `Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift:6`, `Tests/greendotTests/AppDelegateRefreshErrorTests.swift:9`, `Tests/greendotTests/StatusPageEditorTests.swift:9`, `Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift:24`, `Tests/greendotTests/AppDelegateRefreshErrorTests.swift:18`). Both test targets already depend on `TestSupport` (`Package.swift:15`, `Package.swift:19`). Put only these exact payloads in `TestSupport` as named `String` constants when these suites next change; current callers convert the strings to bytes (`Tests/StatusCoreTests/ProbeAndMonitorTests.swift:17`). Keep the yellow, edited-page, and empty-component payloads local because they test different cases (`Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift:15`, `Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift:33`, `Tests/greendotTests/AppDelegateRefreshErrorTests.swift:27`).

### dedup-011 — MEDIUM — CONSOLIDATE — duplicate green-page test fixture

`MenuBuilderTests.greenPage` builds the same green `WatchedPage` shape as the existing `BenchmarkFixtures.greenPage`; the local helper takes a full URL string and the shared helper takes a host (`Tests/greendotTests/MenuBuilderTests.swift:219`, `Tests/TestSupport/BenchmarkFixtures.swift:7`). Its three call sites use plain HTTPS host URLs, so they can call the existing fixture with host names and remove the local builder (`Tests/greendotTests/MenuBuilderTests.swift:236`). `MenuBuilderTests` already imports `TestSupport` (`Tests/greendotTests/MenuBuilderTests.swift:5`). This requires no new abstraction.

## Low / Debatable Findings

### dedup-003 — LOW — CONSOLIDATE — duplicate nonempty-string helper

`SalesforceParser.nonempty` and `JSONScalar.nonempty` both trim whitespace and return `nil` for an empty result (`Sources/StatusCore/SalesforceParser.swift:74`, `Sources/StatusCore/StatusioParser.swift:62`). Use the existing `JSONScalar.nonempty` at the two Salesforce call sites and remove the local method (`Sources/StatusCore/SalesforceParser.swift:44`, `Sources/StatusCore/SalesforceParser.swift:45`). Keep Salesforce's `intID` separate: it accepts only digit strings, while `JSONScalar.stringID` accepts any nonempty string (`Sources/StatusCore/SalesforceParser.swift:67`, `Sources/StatusCore/StatusioParser.swift:56`).

### dedup-004 — LOW — KEEP SEPARATE — page name and URL defaults

Statuspage, Instatus, and Flashduty use the same two short expressions for a page name and URL; Statuspal has the same pattern with a different object name (`Sources/StatusCore/StatuspageParser.swift:11`, `Sources/StatusCore/InstatusParser.swift:13`, `Sources/StatusCore/FlashdutyParser.swift:12`, `Sources/StatusCore/StatuspalParser.swift:9`). Each parser first validates a different provider shape (`Sources/StatusCore/StatuspageParser.swift:5`, `Sources/StatusCore/InstatusParser.swift:5`, `Sources/StatusCore/FlashdutyParser.swift:5`, `Sources/StatusCore/StatuspalParser.swift:5`). A helper for two expressions would add parameters and move code away from that validation. Keep these local copies.

### dedup-005 — LOW — REVIEW — recursive view lookup in three test files

Three `greendotTests` classes have near-identical recursive `findView<T: NSView>` helpers (`Tests/greendotTests/StatusPageEditorTests.swift:251`, `Tests/greendotTests/StatusPageEditorToastTests.swift:226`, `Tests/greendotTests/AppDelegateReloadTests.swift:197`). A shared helper in the same test target could remove two copies if these tests need further changes. Do not replace them with the app's `UITestDriver.find`: that method is private and also handles scroll document views (`Sources/greendot/UITestDriver.swift:50`). Preserve lookup by accessibility identifier (`Tests/greendotTests/StatusPageEditorTests.swift:257`).

### dedup-006 — LOW — KEEP SEPARATE — provider landing wrappers

The AWS, Salesforce, and Okta landing wrappers have the same guard, optional hit, and final-error outline (`Sources/StatusCore/ProviderProbe+AWS.swift:17`, `Sources/StatusCore/ProviderProbe+Salesforce.swift:11`, `Sources/StatusCore/ProviderProbe+Okta.swift:11`). The JSON landing wrappers repeat that outline with provider-specific endpoints and parser callbacks (`Sources/StatusCore/ProviderProbe+JSONLandings.swift:35`, `Sources/StatusCore/ProviderProbe+JSONLandings.swift:52`, `Sources/StatusCore/ProviderProbe+JSONLandings.swift:69`). A generic wrapper would need function or closure parameters for a few clear lines. Keep these wrappers local.

### dedup-007 — LOW — KEEP SEPARATE — RSS test setup

The same `MapHTTPClient` setup for a valid feed and an ignored old feed appears in nine RSS tests: five discovery tests, two redirect tests, and two persistence tests (`Tests/StatusCoreTests/RssHtmlDiscoveryTests.swift:46`, `Tests/StatusCoreTests/RssHtmlDiscoveryTests.swift:93`, `Tests/StatusCoreTests/RssHtmlDiscoveryTests.swift:132`, `Tests/StatusCoreTests/RssHtmlDiscoveryTests.swift:154`, `Tests/StatusCoreTests/RssHtmlDiscoveryTests.swift:177`, `Tests/StatusCoreTests/RssRedirectTests.swift:163`, `Tests/StatusCoreTests/RssRedirectTests.swift:185`, `Tests/StatusCoreTests/RssPersistTests.swift:65`, `Tests/StatusCoreTests/RssPersistTests.swift:114`). The HTML inputs and rejected-link conditions differ (`Tests/StatusCoreTests/RssHtmlDiscoveryTests.swift:38`, `Tests/StatusCoreTests/RssRedirectTests.swift:156`, `Tests/StatusCoreTests/RssPersistTests.swift:58`). Keep the setup visible beside each assertion unless these tests need a larger edit.

### dedup-008 — LOW — KEEP SEPARATE — incident component construction

Google, Slack, incident.io, and Okta build `ComponentStatus` groups with the same final field list (`Sources/StatusCore/GoogleParser.swift:40`, `Sources/StatusCore/SlackParser.swift:44`, `Sources/StatusCore/IncidentioParser.swift:43`, `Sources/StatusCore/OktaParser.swift:41`). Their ID, active-incident, child, and severity rules differ (`Sources/StatusCore/GoogleParser.swift:23`, `Sources/StatusCore/SlackParser.swift:30`, `Sources/StatusCore/IncidentioParser.swift:26`, `Sources/StatusCore/OktaParser.swift:25`). Keep explicit constructors so each provider's input checks stay visible.

### dedup-009 — LOW — KEEP SEPARATE — component toggle decisions in UI and model

The picker and monitor both find a component subtree, decide whether all nodes are on, and update disabled keys (`Sources/greendot/ComponentPicker.swift:111`, `Sources/StatusCore/Monitor+Mutations.swift:94`). The picker updates temporary UI state after its callback, while the monitor commits persisted configuration (`Sources/greendot/ComponentPicker.swift:113`, `Sources/StatusCore/Monitor+Mutations.swift:130`). A shared mutation helper would couple UI state to persistence for little code reduction. Keep both paths, with their existing identifier and name handling (`Sources/greendot/ComponentPicker.swift:128`, `Sources/StatusCore/Monitor+Mutations.swift:102`).

### dedup-012 — LOW — KEEP SEPARATE — small snapshot test builders

`AggregatorTests` and `ToastPolicyTests` each build a `PageSnapshot` from a severity with the same component, incident, and reachability values; the fixture names and URLs differ (`Tests/StatusCoreTests/AggregatorTests.swift:93`, `Tests/StatusCoreTests/ToastPolicyTests.swift:129`). A shared parameterized test builder would add a wider interface for two short local methods. Keep them separate unless a third test needs the same shape.

## Recommendations

1. **CONSOLIDATE dedup-001 first.** Reuse `probeJSON` with each existing endpoint and parser. Preserve cancellation, HTTP status, cache body, and final error behavior (`Sources/StatusCore/ProviderProbe+JSONLandings.swift:189`, `Sources/StatusCore/ProviderProbe+AWS.swift:17`, `Sources/StatusCore/ProviderProbe+Salesforce.swift:11`, `Sources/StatusCore/ProviderProbe+Okta.swift:11`).
2. **CONSOLIDATE dedup-002 after that.** Add only the small cache-hit method on `ProbeContext`; keep RSS and Icinga body construction where it is (`Sources/StatusCore/ProviderProbe.swift:79`, `Sources/StatusCore/ProviderProbe+RSS.swift:260`, `Sources/StatusCore/ProviderProbe+Icinga.swift:34`).
3. **CONSOLIDATE dedup-011 with existing code.** Replace the menu test's local green-page builder with `BenchmarkFixtures.greenPage` (`Tests/greendotTests/MenuBuilderTests.swift:219`, `Tests/TestSupport/BenchmarkFixtures.swift:7`).
4. **CONSOLIDATE dedup-003 and dedup-010 when those suites change.** Reuse `JSONScalar.nonempty` in Salesforce, and put only the exact green/red Statuspage payloads in `TestSupport` (`Sources/StatusCore/SalesforceParser.swift:74`, `Sources/StatusCore/StatusioParser.swift:62`, `Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift:6`, `Tests/greendotTests/AppDelegateRefreshErrorTests.swift:9`, `Package.swift:15`).
5. **KEEP SEPARATE dedup-004, dedup-006, dedup-007, dedup-008, dedup-009, and dedup-012.** Their local copies keep provider validation, test inputs, or UI and persistence state clear (`Sources/StatusCore/StatuspageParser.swift:5`, `Sources/StatusCore/ProviderProbe+JSONLandings.swift:35`, `Tests/StatusCoreTests/RssHtmlDiscoveryTests.swift:38`, `Sources/StatusCore/GoogleParser.swift:23`, `Sources/greendot/ComponentPicker.swift:111`, `Tests/StatusCoreTests/AggregatorTests.swift:93`). Review dedup-005 only if the test helpers change (`Tests/greendotTests/StatusPageEditorTests.swift:251`).

## Out of Scope / Flagged for Review

- `PageStore.uniquingPageIDs` and `needsIDNormalisation` use similar duplicate-ID checks, but one updates decoded pages and the other checks raw JSON for missing or invalid IDs. They must agree, yet merging them could weaken file-input validation; no deduplication action is proposed (`Sources/StatusCore/PageStore.swift:159`, `Sources/StatusCore/PageStore.swift:172`).
- Icinga's numeric conversion accepts `Double` and numeric strings; `JSONScalar.intValue` does not. Their common name is not enough reason to merge them (`Sources/StatusCore/IcingaParser.swift:107`, `Sources/StatusCore/StatusioParser.swift:50`).
- Earlier candidates for shared severity text, benchmark page fixtures, timing conversion, and persistence failure setup already have shared implementations in this tree (`Sources/StatusCore/Severity.swift:7`, `Sources/StatusCore/ToastPolicy.swift:48`, `Tests/TestSupport/BenchmarkFixtures.swift:4`, `Tests/TestSupport/BenchmarkFixtures.swift:29`, `Tests/TestSupport/PersistenceFailure.swift:3`).
- This assessment covers duplication only. It proposes no source change, dependency change, PR, or cross-domain audit.

## Machine-Readable Findings

```json
{"findings": [
  {"id": "dedup-001", "file": "Sources/StatusCore/ProviderProbe+AWS.swift", "line": 28, "severity": "HIGH", "confidence": "LIKELY", "recommendation": "CONSOLIDATE", "detail": "AWS, Salesforce, and Okta repeat the existing probeJSON fetch, cache, parse, and error flow; retain provider-specific endpoints and URL rules.", "verified": false},
  {"id": "dedup-002", "file": "Sources/StatusCore/ProviderProbe+JSONLandings.swift", "line": 195, "severity": "MEDIUM", "confidence": "LIKELY", "recommendation": "CONSOLIDATE", "detail": "A reachable prior-snapshot cache check also occurs in Icinga and two RSS paths; a ProbeContext method could share it after dedup-001.", "verified": false},
  {"id": "dedup-010", "file": "Tests/StatusCoreTests/ProbeAndMonitorTests.swift", "line": 6, "severity": "MEDIUM", "confidence": "CERTAIN", "recommendation": "CONSOLIDATE", "detail": "Four test classes contain identical green Statuspage JSON and two also contain identical red JSON; share only these payloads in TestSupport.", "verified": false},
  {"id": "dedup-011", "file": "Tests/greendotTests/MenuBuilderTests.swift", "line": 219, "severity": "MEDIUM", "confidence": "CERTAIN", "recommendation": "CONSOLIDATE", "detail": "MenuBuilderTests.greenPage duplicates the existing BenchmarkFixtures.greenPage shape for three host-only HTTPS URLs.", "verified": false},
  {"id": "dedup-003", "file": "Sources/StatusCore/SalesforceParser.swift", "line": 74, "severity": "LOW", "confidence": "CERTAIN", "recommendation": "CONSOLIDATE", "detail": "Salesforce's nonempty method duplicates JSONScalar.nonempty; use the existing method while retaining numeric-only intID.", "verified": false},
  {"id": "dedup-004", "file": "Sources/StatusCore/StatuspageParser.swift", "line": 11, "severity": "LOW", "confidence": "CERTAIN", "recommendation": "KEEP SEPARATE", "detail": "Four provider parsers repeat short page name and URL defaults; an extraction would add more code and hide local validation.", "verified": false},
  {"id": "dedup-005", "file": "Tests/greendotTests/StatusPageEditorTests.swift", "line": 251, "severity": "LOW", "confidence": "CERTAIN", "recommendation": "REVIEW", "detail": "Three greendotTests files repeat recursive view lookup by accessibility identifier; share in the test target only if these tests change.", "verified": false},
  {"id": "dedup-006", "file": "Sources/StatusCore/ProviderProbe+AWS.swift", "line": 17, "severity": "LOW", "confidence": "CERTAIN", "recommendation": "KEEP SEPARATE", "detail": "Provider landing wrappers share a short outline but use distinct guards and provider calls.", "verified": false},
  {"id": "dedup-007", "file": "Tests/StatusCoreTests/RssHtmlDiscoveryTests.swift", "line": 46, "severity": "LOW", "confidence": "CERTAIN", "recommendation": "KEEP SEPARATE", "detail": "Nine RSS tests repeat a short MapHTTPClient setup beside different malformed or rejected HTML inputs.", "verified": false},
  {"id": "dedup-008", "file": "Sources/StatusCore/GoogleParser.swift", "line": 40, "severity": "LOW", "confidence": "CERTAIN", "recommendation": "KEEP SEPARATE", "detail": "Incident parsers have similar ComponentStatus constructors but different provider rules and input checks.", "verified": false},
  {"id": "dedup-009", "file": "Sources/greendot/ComponentPicker.swift", "line": 111, "severity": "LOW", "confidence": "LIKELY", "recommendation": "KEEP SEPARATE", "detail": "Picker and monitor both toggle subtree keys, but one holds UI state and the other commits persisted configuration.", "verified": false},
  {"id": "dedup-012", "file": "Tests/StatusCoreTests/AggregatorTests.swift", "line": 93, "severity": "LOW", "confidence": "CERTAIN", "recommendation": "KEEP SEPARATE", "detail": "Two test classes build similar severity snapshots, but a shared builder adds a wider interface for only two local helpers.", "verified": false}
]}
```
