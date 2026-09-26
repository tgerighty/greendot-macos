Ponytail: full intensity. Keep `Any` at real trust boundaries. Prefer native Swift types and the smallest change that preserves validation, security, and accessibility.

# Weak Typing Assessment

## Executive Summary

- Total actionable issues: 8. Severity: HIGH=2, MEDIUM=4, LOW=2. The two high priorities are component status values that become green when an external JSON field is missing or has the wrong type. The menu then uses component severity in place of the page's overall severity. `Sources/StatusCore/StatuspageParser.swift:47` `Sources/StatusCore/InstatusParser.swift:24` `Sources/StatusCore/Models.swift:128`
- Next priorities are malformed Okta JSON that becomes an empty green result, numeric status coercion, and top-level incident arrays that discard records with the wrong shape. `Sources/StatusCore/OktaParser.swift:70` `Sources/StatusCore/IcingaParser.swift:107` `Sources/StatusCore/StatusioParser.swift:50` `Sources/StatusCore/AwsParser.swift:5`
- Estimated scope: 10 production files for the 8 findings. Use local guards or narrower casts; no new dependency or provider-wide model layer is justified by these findings. The package declares only local targets. `Package.swift:5`
- Method: source and test inspection. The host has no `swift`, `swiftc`, `swiftlint`, or `xcodebuild` command, so the inferred payload outcomes below need a macOS test run before an implementation is accepted. Existing tests cover normal provider payloads and a concurrent first-run call, but not the malformed cases in these findings. `Tests/StatusCoreTests/ParserTests.swift:5` `Tests/StatusCoreTests/MonitorFirstRunTests.swift:7`

## Critical Findings

### WT-001 — Missing Statuspage component status becomes green (HIGH; confidence HIGH)

`nest` accepts a component with a `name` and substitutes `"operational"` when `status` is absent or not a string. The mapping makes that value green. For a payload with `status.indicator = "major"` and `components = [{"name":"API"}]`, the parser records a red overall result and a green component. `WatchedPage.displaySeverity` then uses the nonempty component tree, so the menu can show green. This is a source-level inference; no payload test was run here. `Sources/StatusCore/StatuspageParser.swift:6` `Sources/StatusCore/StatuspageParser.swift:41` `Sources/StatusCore/StatuspageParser.swift:47` `Sources/StatusCore/StatusMapping.swift:11` `Sources/StatusCore/Models.swift:128`

**Replacement type/action:** Keep the external dictionary at entry. Require a nonempty `String` for each component status before constructing the already typed `Row.status: String`; return a parse error or a non-green unknown status on invalid input. Do not silently create an operational status. The local `Row` already supplies the internal type. `Sources/StatusCore/StatuspageParser.swift:32` `Sources/StatusCore/StatuspageParser.swift:40` `Sources/StatusCore/ParserError.swift:3`

### WT-002 — Missing Instatus component status becomes green (HIGH; confidence HIGH)

The parser requires a string for `page.status` but substitutes `"OPERATIONAL"` for a missing or mistyped component `status`. That branch maps to green. When a page has any component, `displaySeverity` reads the component tree. A `HASISSUES` page with a named component that has no valid status can therefore appear green. This is a source-level inference. `Sources/StatusCore/InstatusParser.swift:5` `Sources/StatusCore/InstatusParser.swift:22` `Sources/StatusCore/InstatusParser.swift:24` `Sources/StatusCore/InstatusParser.swift:27` `Sources/StatusCore/Models.swift:128`

**Replacement type/action:** Validate the component status as `String` before creating `ComponentStatus`; treat invalid input as unknown/non-green or reject the payload. Preserve the existing `PageSnapshot` output type. `Sources/StatusCore/InstatusParser.swift:22` `Sources/StatusCore/InstatusParser.swift:32` `Sources/StatusCore/InstatusParser.swift:34`

## Medium Findings

### WT-003 — Malformed Okta incident JSON becomes an empty green tree (MEDIUM; confidence HIGH)

The presence of the embedded `incidents` span admits an Okta page, but `array` converts JSON parse errors or a non-array root to `[]`. The empty component tree maps to green. A malformed incident payload can therefore be reported as healthy. The test rejects an HTML page without the span but does not cover a malformed span. `Sources/StatusCore/OktaParser.swift:6` `Sources/StatusCore/OktaParser.swift:9` `Sources/StatusCore/OktaParser.swift:18` `Sources/StatusCore/OktaParser.swift:70` `Sources/StatusCore/ComponentTree.swift:24` `Tests/StatusCoreTests/OktaParserTests.swift:66`

**Replacement type/action:** Make the required incident array parser throw and require `[[String: Any]]` after `JSONSerialization`; keep the optional planned-outage array optional. Do not replace external data with `any` or add a provider SDK. `Sources/StatusCore/OktaParser.swift:9` `Sources/StatusCore/OktaParser.swift:10` `Sources/StatusCore/OktaParser.swift:70`

### WT-004 — Icinga numeric state loses its original shape (MEDIUM; confidence MEDIUM)

`intValue` accepts `NSNumber` through `.intValue` before the `Double` and `String` branches. The state then controls the green/red mapping. Fractional or out-of-range JSON numbers can be narrowed without an explicit integral/range check; a value near zero can be treated as state zero. The current fixtures use integral numeric values such as `1.0`, so an integral check must retain those inputs. This is a risk inferred from the conversion path. `Sources/StatusCore/IcingaParser.swift:79` `Sources/StatusCore/IcingaParser.swift:107` `Sources/StatusCore/StatusMapping.swift:68` `Tests/StatusCoreTests/IcingaParserTests.swift:15`

**Replacement type/action:** Keep `Any?` only at JSON lookup. Convert to `Int?` only when a numeric value is finite, integral, and in `Int` range; preserve the existing accepted integral strings if the provider needs them. An invalid state already maps to yellow through `Int?`. `Sources/StatusCore/IcingaParser.swift:107` `Sources/StatusCore/StatusMapping.swift:68`

### WT-005 — Status.io numeric code loses its original shape (MEDIUM; confidence MEDIUM)

`JSONScalar.intValue` also accepts `NSNumber.intValue` without an integral/range check. Status code 100 means green, so a malformed fractional code can be narrowed to a known code. The tests exercise integer codes only. This is a risk inferred from the conversion path. `Sources/StatusCore/StatusioParser.swift:10` `Sources/StatusCore/StatusioParser.swift:50` `Sources/StatusCore/StatusMapping.swift:100` `Tests/StatusCoreTests/StatusioParserTests.swift:11`

**Replacement type/action:** Make `JSONScalar.intValue` return `Int?` only for a finite, integral, in-range number. Reuse that one helper for Status.io and other current callers; keep unknown codes yellow. `Sources/StatusCore/StatusioParser.swift:50` `Sources/StatusCore/StatusioParser.swift:56` `Sources/StatusCore/StatusMapping.swift:100`

### WT-006 — Top-level incident arrays drop malformed records (MEDIUM; confidence HIGH)

AWS, Google, and Salesforce parse the root as `[Any]`, then use `compactMap` to discard non-object members. If all members have the wrong shape, the resulting component tree is empty and its severity is green. The providers already require an array root, so a narrower `[[String: Any]]` cast can reject this shape at entry without adding model structs. `Sources/StatusCore/AwsParser.swift:5` `Sources/StatusCore/AwsParser.swift:8` `Sources/StatusCore/GoogleParser.swift:5` `Sources/StatusCore/GoogleParser.swift:8` `Sources/StatusCore/SalesforceParser.swift:5` `Sources/StatusCore/SalesforceParser.swift:8` `Sources/StatusCore/ComponentTree.swift:24`

**Replacement type/action:** Require `[[String: Any]]` for the root and reject a non-object member. Keep per-record field validation; AWS already skips a record without its required ARN, which is a separate provider decision. `Sources/StatusCore/AwsParser.swift:23` `Sources/StatusCore/AwsParser.swift:24`

## Low / Debatable Findings

### WT-007 — An unchecked `Sendable` monitor has a mutable callback (LOW; confidence MEDIUM)

`Monitor` declares `@unchecked Sendable`, while `onLaunchAtLoginEnable` is a public mutable closure without `@Sendable` or lock protection. The first-run method reads and invokes it after it releases the transition lock. The app assigns the callback during launch before its first call, so a race needs a concurrent reassignment and has not been shown in the app flow. A test does call the first-run method from global queues. `Sources/StatusCore/Monitor.swift:3` `Sources/StatusCore/Monitor.swift:29` `Sources/StatusCore/Monitor+Mutations.swift:27` `Sources/StatusCore/Monitor+Mutations.swift:39` `Sources/greendot/AppDelegate.swift:43` `Tests/StatusCoreTests/MonitorFirstRunTests.swift:32`

**Replacement type/action:** If the callback must remain mutable after initialization, store a `(@Sendable () -> Void)?` behind the existing state lock and read a snapshot before invocation. If it is always set once, pass an immutable callback at construction instead. Check actor needs at the app call site before changing the public API. `Sources/StatusCore/Monitor.swift:14` `Sources/StatusCore/Monitor.swift:29` `Sources/greendot/AppDelegate.swift:43`

### WT-008 — A Foundation collection bridge adds a needless cast (LOW; confidence HIGH)

The Statuspal probe makes a `[String]`, bridges it through `NSOrderedSet`, casts it back to `[String]`, and falls back to the original array if the cast fails. The current control flow appends at most one subdomain before this line, so deduplication has no work to do. `Sources/StatusCore/ProviderProbe.swift:182` `Sources/StatusCore/ProviderProbe.swift:186` `Sources/StatusCore/ProviderProbe.swift:195` `Sources/StatusCore/ProviderProbe.swift:202`

**Replacement type/action:** Use the existing `[String]` directly. If a later source can append more than one value, use a native `Set<String>` only if duplicates become possible. `Sources/StatusCore/ProviderProbe.swift:182` `Sources/StatusCore/ProviderProbe.swift:202`

## Recommendations

1. Correct WT-001 and WT-002 at the JSON-to-`ComponentStatus` boundary. Add one malformed-field test for each, including the final `WatchedPage.displaySeverity` value. `Sources/StatusCore/StatuspageParser.swift:40` `Sources/StatusCore/InstatusParser.swift:22` `Sources/StatusCore/Models.swift:128`
2. Make the required Okta incident array fail on bad JSON. Then use one malformed-root test each for AWS, Google, and Salesforce before changing their `[Any]` casts. `Sources/StatusCore/OktaParser.swift:70` `Sources/StatusCore/AwsParser.swift:5` `Sources/StatusCore/GoogleParser.swift:5` `Sources/StatusCore/SalesforceParser.swift:5`
3. Validate numeric status values before converting to `Int`. Preserve integral `1.0` Icinga input and the integer Status.io codes shown in existing tests. `Sources/StatusCore/IcingaParser.swift:107` `Sources/StatusCore/StatusioParser.swift:50` `Tests/StatusCoreTests/IcingaParserTests.swift:15` `Tests/StatusCoreTests/StatusioParserTests.swift:11`
4. Remove the Statuspal collection bridge. Revisit the mutable `Sendable` callback only with a demonstrated need for reassignment or a concurrency check. `Sources/StatusCore/ProviderProbe.swift:202` `Sources/StatusCore/Monitor.swift:29`

## Out of Scope / Flagged for Review

The following inventory covers the explicit `Any` declarations in production Swift. **KEEP** means the value comes from untrusted JSON or a native framework interface and is narrowed before use. It is not a request to replace `Any` with a provider-wide `Codable` layer. The normal internal output is already `PageSnapshot` or `ComponentStatus`. `Sources/StatusCore/StatuspageParser.swift:83` `Sources/StatusCore/StatuspageParser.swift:21` `Sources/StatusCore/Models.swift:21`

| Source and weak declaration | Current role; proposed type or decision |
| --- | --- |
| `Sources/StatusCore/AppleParser.swift:5`, `Sources/StatusCore/AppleParser.swift:6`, `Sources/StatusCore/AppleParser.swift:21`, `Sources/StatusCore/AppleParser.swift:23` | KEEP JSON object/array until narrowed to `ComponentStatus`. |
| `Sources/StatusCore/AwsParser.swift:5`, `Sources/StatusCore/AwsParser.swift:9`, `Sources/StatusCore/AwsParser.swift:23`, `Sources/StatusCore/AwsParser.swift:39`, `Sources/StatusCore/AwsParser.swift:40`, `Sources/StatusCore/AwsParser.swift:42`, `Sources/StatusCore/AwsParser.swift:57` | Root `[Any]` is WT-006; keep local JSON dictionaries and `Any?` scalar checks, with `ComponentStatus` as output. |
| `Sources/StatusCore/FlashdutyParser.swift:5`, `Sources/StatusCore/FlashdutyParser.swift:7`, `Sources/StatusCore/FlashdutyParser.swift:11`, `Sources/StatusCore/FlashdutyParser.swift:26`, `Sources/StatusCore/FlashdutyParser.swift:27` | KEEP JSON input; `events` returns typed `[Incident]`. |
| `Sources/StatusCore/GoogleParser.swift:5`, `Sources/StatusCore/GoogleParser.swift:9`, `Sources/StatusCore/GoogleParser.swift:23`, `Sources/StatusCore/GoogleParser.swift:29` | Root `[Any]` is WT-006; keep nested JSON checks and `ComponentStatus` output. |
| `Sources/StatusCore/HerokuParser.swift:5`, `Sources/StatusCore/HerokuParser.swift:6`, `Sources/StatusCore/HerokuParser.swift:19`, `Sources/StatusCore/HerokuParser.swift:30` | KEEP JSON input; parsed entries become `ComponentStatus`. |
| `Sources/StatusCore/IcingaParser.swift:38`, `Sources/StatusCore/IcingaParser.swift:39`, `Sources/StatusCore/IcingaParser.swift:40`, `Sources/StatusCore/IcingaParser.swift:43`, `Sources/StatusCore/IcingaParser.swift:75`, `Sources/StatusCore/IcingaParser.swift:76`, `Sources/StatusCore/IcingaParser.swift:87`, `Sources/StatusCore/IcingaParser.swift:88`, `Sources/StatusCore/IcingaParser.swift:103`, `Sources/StatusCore/IcingaParser.swift:107`, `Sources/StatusCore/IcingaParser.swift:115` | KEEP Icinga's JSON boundary and typed `HostGroup`/`ServiceRecord` result; numeric conversion is WT-004. |
| `Sources/StatusCore/IncidentioParser.swift:5`, `Sources/StatusCore/IncidentioParser.swift:6`, `Sources/StatusCore/IncidentioParser.swift:14`, `Sources/StatusCore/IncidentioParser.swift:26`, `Sources/StatusCore/IncidentioParser.swift:32` | KEEP JSON input; incidents become `ComponentStatus`. |
| `Sources/StatusCore/InstatusParser.swift:5`, `Sources/StatusCore/InstatusParser.swift:6`, `Sources/StatusCore/InstatusParser.swift:15`, `Sources/StatusCore/InstatusParser.swift:21` | KEEP JSON input; strengthen the component status validation in WT-002. |
| `Sources/StatusCore/OktaParser.swift:25`, `Sources/StatusCore/OktaParser.swift:51`, `Sources/StatusCore/OktaParser.swift:64`, `Sources/StatusCore/OktaParser.swift:70`, `Sources/StatusCore/OktaParser.swift:71` | KEEP JSON input; change the required array's error handling in WT-003. |
| `Sources/StatusCore/SalesforceParser.swift:5`, `Sources/StatusCore/SalesforceParser.swift:9`, `Sources/StatusCore/SalesforceParser.swift:23`, `Sources/StatusCore/SalesforceParser.swift:37`, `Sources/StatusCore/SalesforceParser.swift:52`, `Sources/StatusCore/SalesforceParser.swift:67` | Root `[Any]` is WT-006; keep the local JSON scalar checks. |
| `Sources/StatusCore/SlackParser.swift:5`, `Sources/StatusCore/SlackParser.swift:12`, `Sources/StatusCore/SlackParser.swift:30` | KEEP JSON input; incidents become `ComponentStatus`. |
| `Sources/StatusCore/StatusioParser.swift:5`, `Sources/StatusCore/StatusioParser.swift:6`, `Sources/StatusCore/StatusioParser.swift:7`, `Sources/StatusCore/StatusioParser.swift:11`, `Sources/StatusCore/StatusioParser.swift:25`, `Sources/StatusCore/StatusioParser.swift:28`, `Sources/StatusCore/StatusioParser.swift:50`, `Sources/StatusCore/StatusioParser.swift:56`, `Sources/StatusCore/StatusioParser.swift:69`, `Sources/StatusCore/StatusioParser.swift:70` | KEEP JSON input; `JSONScalar.intValue` is WT-005. |
| `Sources/StatusCore/StatuspageParser.swift:6`, `Sources/StatusCore/StatuspageParser.swift:10`, `Sources/StatusCore/StatuspageParser.swift:13`, `Sources/StatusCore/StatuspageParser.swift:15`, `Sources/StatusCore/StatuspageParser.swift:40`, `Sources/StatusCore/StatuspageParser.swift:83`, `Sources/StatusCore/StatuspageParser.swift:84` | KEEP JSON input and local typed `Row`; its status fallback is WT-001. |
| `Sources/StatusCore/StatuspalParser.swift:5`, `Sources/StatusCore/StatuspalParser.swift:6`, `Sources/StatusCore/StatuspalParser.swift:13`, `Sources/StatusCore/StatuspalParser.swift:15`, `Sources/StatusCore/StatuspalParser.swift:31`, `Sources/StatusCore/StatuspalParser.swift:45` | KEEP JSON input; nested services become `ComponentStatus`. |
| `Sources/StatusCore/PageStore.swift:175`, `Sources/StatusCore/PageStore.swift:176` | KEEP the local `[String: Any]` check of a user-editable file for ID normalization; the main load uses typed `AppConfig` decoding. |
| `Sources/greendot/BuildInfo.swift:5`, `Sources/greendot/BuildInfo.swift:10`, `Sources/greendot/BuildInfo.swift:16`, `Sources/greendot/BuildInfo.swift:23` | KEEP Foundation info-dictionary and AppKit option `Any` types; both values are narrowed to `String` before use. |
| `Sources/greendot/MenuClickOpener.swift:11` | KEEP the `Any?` event-monitor token; it is returned to `NSEvent.removeMonitor`, the native matching API. `Sources/greendot/MenuClickOpener.swift:38` `Sources/greendot/MenuClickOpener.swift:55` |

Other checked casts are native boundary checks: `HTTPURLResponse` from `URLSession` (`Sources/StatusCore/HTTPClient.swift:85`), `XMLElement` from XML nodes (`Sources/StatusCore/RssParser.swift:242`), `NSButton`/`NSTextField` from AppKit views (`Sources/greendot/UITestDriver.swift:36` `Sources/greendot/UITestDriver.swift:40`), `TargetAction` from `representedObject` (`Sources/greendot/MenuCommands.swift:41`), and a string from notification `object` (`Sources/greendot/AppDelegate.swift:243`). KEEP their conditional casts; the source APIs do not promise a narrower value. `Sources/greendot/MenuBuilder.swift:220`

Other production `@unchecked Sendable` declarations need targeted concurrency review before any removal: `PageStore` locks its mutable remembered config bytes (`Sources/StatusCore/PageStore.swift:44` `Sources/StatusCore/PageStore.swift:222`); `PathNetworkReachability` locks its stored state and callback (`Sources/StatusCore/NetworkReachability.swift:16` `Sources/StatusCore/NetworkReachability.swift:25` `Sources/StatusCore/NetworkReachability.swift:31`); the redirect delegate has no mutable stored state (`Sources/StatusCore/HTTPClient.swift:95`); and the notification-center adapter locks lazy initialization (`Sources/greendot/SystemToastDelivery.swift:22` `Sources/greendot/SystemToastDelivery.swift:26`). No data race is asserted for those types here. `Monitor` is assessed separately in WT-007. `Sources/StatusCore/Monitor.swift:3`

No TypeScript `@types/*` packages apply to this Swift package. `Package.swift:1` `Package.swift:5`

## Machine-Readable Findings

```json
{"findings": [
  {"id":"weak-typing-001","file":"Sources/StatusCore/StatuspageParser.swift","line":47,"severity":"HIGH","confidence":"HIGH","recommendation":"VALIDATE_COMPONENT_STATUS","detail":"A missing or wrong-type component status defaults to operational and can make a red page display green.","verified":false},
  {"id":"weak-typing-002","file":"Sources/StatusCore/InstatusParser.swift","line":24,"severity":"HIGH","confidence":"HIGH","recommendation":"VALIDATE_COMPONENT_STATUS","detail":"A missing or wrong-type component status defaults to OPERATIONAL and can make an unhealthy page display green.","verified":false},
  {"id":"weak-typing-003","file":"Sources/StatusCore/OktaParser.swift","line":70,"severity":"MEDIUM","confidence":"HIGH","recommendation":"REJECT_MALFORMED_REQUIRED_JSON","detail":"Malformed required incident JSON becomes an empty green component tree.","verified":false},
  {"id":"weak-typing-004","file":"Sources/StatusCore/IcingaParser.swift","line":107,"severity":"MEDIUM","confidence":"MEDIUM","recommendation":"VALIDATE_INTEGRAL_NUMBER","detail":"Numeric state is narrowed to Int without an explicit integral or range check.","verified":false},
  {"id":"weak-typing-005","file":"Sources/StatusCore/StatusioParser.swift","line":50,"severity":"MEDIUM","confidence":"MEDIUM","recommendation":"VALIDATE_INTEGRAL_NUMBER","detail":"Numeric status code is narrowed to Int without an explicit integral or range check.","verified":false},
  {"id":"weak-typing-006","file":"Sources/StatusCore/AwsParser.swift","line":5,"severity":"MEDIUM","confidence":"HIGH","recommendation":"NARROW_ROOT_ARRAY","detail":"AWS, Google, and Salesforce accept Any root elements and discard non-object records, allowing an empty green result.","verified":false},
  {"id":"weak-typing-007","file":"Sources/StatusCore/Monitor.swift","line":29,"severity":"LOW","confidence":"MEDIUM","recommendation":"REVIEW_SENDABLE_CALLBACK","detail":"A public mutable non-Sendable callback is outside the lock of an unchecked Sendable class.","verified":false},
  {"id":"weak-typing-008","file":"Sources/StatusCore/ProviderProbe.swift","line":202,"severity":"LOW","confidence":"HIGH","recommendation":"REMOVE_NEEDLESS_BRIDGE","detail":"NSOrderedSet and a conditional cast deduplicate an array that currently gets at most one element.","verified":false}
]}
```
