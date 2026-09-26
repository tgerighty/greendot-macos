PONYTAIL MODE ACTIVE — level: full

# Circular Dependency Analysis Assessment

Scope: `greendot`, circular dependencies only. Baseline: `9320756a8a8bfdacbc4d45aad53ed1591513a12e`, 2026-09-26. Report-only analysis.

## Executive Summary

- Total findings: **4**. Severity: **HIGH=0, MEDIUM=2, LOW=2**. The two LOW entries describe file grouping and recommend KEEP. Evidence: `Sources/StatusCore/HTTPAuth.swift:15`, `Sources/StatusCore/SlackParser.swift:21`, `Sources/StatusCore/Models.swift:132`, `Sources/StatusCore/StateFile.swift:20`.
- No declared package-target cycle exists. All target dependencies point toward `StatusCore` or toward targets that depend on `StatusCore`. Evidence: `Package.swift:8`, `Package.swift:11`, `Package.swift:16`, `Package.swift:20`, `Package.swift:24`.
- No BREAKING cycle was established. The structural return edges call a URL predicate or a URL-normalization helper. Neither helper starts another probe. Evidence: `Sources/StatusCore/ProviderProbe+Icinga.swift:4`, `Sources/StatusCore/ProviderProbe.swift:49`.
- Priority 1: review the transport-to-probe dependency when changing Icinga routing. Preserve its authentication and TLS behavior. Evidence: `Sources/StatusCore/HTTPAuth.swift:15`, `Sources/StatusCore/HTTPAuth.swift:24`, `Sources/StatusCore/HTTPClient.swift:118`.
- Priority 2: remove parser-to-probe references through one shared URL helper if independent parser reuse becomes necessary. Evidence: `Sources/StatusCore/ProviderProbe.swift:49`, `Sources/StatusCore/ProviderProbe+JSONLandings.swift:45`, `Sources/StatusCore/SlackParser.swift:21`.
- Priority 3: keep the model and persistence file arrangements unless a concrete module split requires different ownership. Evidence: `Sources/StatusCore/Models.swift:21`, `Sources/StatusCore/Models.swift:132`, `Sources/StatusCore/PageStore.swift:3`, `Sources/StatusCore/StateFile.swift:38`.
- Estimated optional change impact: about **30 existing lines across 10 existing source files**, plus relocated helper bodies. No material LOC reduction is expected. The estimates come from the two helper definitions and their callers below. Evidence: `Sources/StatusCore/ProviderProbe+Icinga.swift:4`, `Sources/StatusCore/HTTPAuth.swift:15`, `Sources/StatusCore/ProviderProbe.swift:49`, `Sources/StatusCore/URLAuth.swift:3`, and the six parser references in CIRC-002.

### Pre-flight and method

The repository uses Swift Package Manager, Swift tools 5.9, and macOS 13 or later. The UI uses AppKit. Evidence: `Package.swift:1`, `Package.swift:6`, `Sources/greendot/AppDelegate.swift:1`.

The manifest declares five local targets and no external package dependency entries. The separate UI-test project declares one UI-test target. Evidence: `Package.swift:4`, `Package.swift:8`, `Package.swift:10`, `Package.swift:15`, `Package.swift:19`, `Package.swift:23`, `UITests/project.yml:6`.

Session tool check: `command -v` found `rg` and `python3`. It did not find `swift`, `swiftc`, `swiftlint`, `madge`, `lint-imports`, `pydeps`, `grimp`, or `importlab`. This is an environment observation, not a repository defect. The repository's native commands require Swift and SwiftLint. Evidence: `Makefile:10`, `Makefile:13`, `Makefile:19`.

Read-only analysis used import searches, numbered source reads, and inline Python standard-library scripts. The scripts checked the manifest graph with `graphlib.TopologicalSorter` and collected candidate cycles from named-type references. A second pass assigned Swift extensions to their owning type. Manual reads checked each reported edge. The import inventory covered `Sources`, `Tests`, and `UITests`. The source scan covered 68 production files and 78 test/support files. No tool installation, build, test execution, or dependency resolution occurred.

The lexical scan is a candidate detector, not a Swift compiler. It does not resolve every inferred type, string interpolation, or dynamic callback. Accordingly, this report makes no claim about runtime success or exhaustive call-graph coverage. The native test command is `swift test`, and the documented build platform is macOS with Xcode. Evidence: `Makefile:13`, `README.md:30`.

### Package import graph

An arrow means “depends on.” These target edges have no path back to their starting target.

| Target | Local dependencies | Evidence |
|---|---|---|
| `StatusCore` | None declared | `Package.swift:8` |
| `TestSupport` | `StatusCore` | `Package.swift:11`, `Tests/TestSupport/HTTPClientDoubles.swift:2` |
| `greendot` | `StatusCore` | `Package.swift:16`, `Sources/greendot/AppDelegate.swift:2` |
| `StatusCoreTests` | `StatusCore`, `TestSupport` | `Package.swift:20`, `Tests/StatusCoreTests/AwsProbeTests.swift:2`, `Tests/StatusCoreTests/AwsProbeTests.swift:3` |
| `greendotTests` | `greendot`, `StatusCore`, `TestSupport` | `Package.swift:24`, `Tests/greendotTests/AppDelegateConfigMenuTests.swift:2`, `Tests/greendotTests/AppDelegateConfigMenuTests.swift:4`, `Tests/greendotTests/AppDelegateConfigMenuTests.swift:5` |

The findings below concern references inside `StatusCore`, not circular `import` statements. Swift extensions contribute methods to the same type. For example, the probe implementation and its Icinga extension both belong to `ProviderProbe`. Evidence: `Package.swift:8`, `Sources/StatusCore/ProviderProbe.swift:23`, `Sources/StatusCore/ProviderProbe+Icinga.swift:3`.

## Critical Findings

None established. There is no declared target cycle, and the identified return helpers do not call the probe dispatcher. This is a source-analysis result, not a successful build result. Evidence: `Package.swift:8`, `Package.swift:11`, `Package.swift:16`, `Package.swift:20`, `Package.swift:24`, `Sources/StatusCore/ProviderProbe.swift:49`, `Sources/StatusCore/ProviderProbe+Icinga.swift:4`.

## Medium Findings

### CIRC-001 — HTTP policy depends on the probe implementation

**Classification:** MEDIUM / STRUCTURAL. **Recommendation:** REVIEW. **Confidence:** CERTAIN for the source references. **Verified:** false.

The complete file-reference cycle is:

```text
HTTPClient.swift
  -> HTTPAuth.swift             HTTPClient.swift:82 or HTTPClient.swift:118
  -> ProviderProbe+Icinga.swift HTTPAuth.swift:15 or HTTPAuth.swift:24
  -> HTTPClient.swift          ProviderProbe+Icinga.swift:82
```

All files in this diagram are under `Sources/StatusCore/`. The edges are:

| Edge | Evidence |
|---|---|
| Live transport calls the authentication helper | `Sources/StatusCore/HTTPClient.swift:82` |
| The transport delegate calls the TLS policy helper | `Sources/StatusCore/HTTPClient.swift:118` |
| Both helpers call `ProviderProbe.isIcingaAPI` | `Sources/StatusCore/HTTPAuth.swift:15`, `Sources/StatusCore/HTTPAuth.swift:24` |
| The Icinga extension owns that predicate and also fetches through `HTTPClient` | `Sources/StatusCore/ProviderProbe+Icinga.swift:4`, `Sources/StatusCore/ProviderProbe+Icinga.swift:82`, `Sources/StatusCore/ProviderProbe+Icinga.swift:85` |

**Why it exists:** HTTP policy reuses the probe's Icinga URL classification. The same classification selects JSON headers, TLS handling, and Icinga probing. Evidence: `Sources/StatusCore/HTTPAuth.swift:15`, `Sources/StatusCore/HTTPAuth.swift:24`, `Sources/StatusCore/ProviderProbe+Icinga.swift:15`.

**Limit:** This is a file/layer cycle, not a cycle between the `HTTPClient` protocol and `ProviderProbe`. The protocol has no probe reference. Its concrete implementation shares its file. The predicate returns a Boolean without fetching. Evidence: `Sources/StatusCore/HTTPClient.swift:42`, `Sources/StatusCore/HTTPClient.swift:54`, `Sources/StatusCore/ProviderProbe+Icinga.swift:4`.

**Weakest link and minimal resolution:** If changing this boundary, move the existing predicate into the existing `HTTPAuth` enum. Let both TLS policy and probing call `HTTPAuth.isIcingaAPI`. Move the body unchanged. This removes HTTP policy's reference to the probe without adding a module or protocol. Evidence: `Sources/StatusCore/HTTPAuth.swift:3`, `Sources/StatusCore/HTTPAuth.swift:15`, `Sources/StatusCore/HTTPAuth.swift:24`, `Sources/StatusCore/ProviderProbe+Icinga.swift:4`, `Sources/StatusCore/ProviderProbe+Icinga.swift:15`, `Sources/StatusCore/ProviderProbe+Icinga.swift:72`.

**Blast radius:** Two existing source files, about 10–15 existing lines affected by movement and caller changes. Risk: MEDIUM because this predicate also controls TLS handling. Preserve all path, host, and port conditions. Do not broaden the accepted URLs to simplify the dependency. Evidence: `Sources/StatusCore/ProviderProbe+Icinga.swift:4`, `Sources/StatusCore/HTTPAuth.swift:24`, `Sources/StatusCore/HTTPClient.swift:116`.

**Future validation:** Reuse the authentication, TLS-policy, and Icinga routing tests. These tests were read but not run here. Evidence: `Tests/StatusCoreTests/HTTPAuthTests.swift:5`, `Tests/StatusCoreTests/HTTPAuthTests.swift:23`, `Tests/StatusCoreTests/IcingaProbeTests.swift:26`, `Tests/StatusCoreTests/IcingaProbeTests.swift:36`.

### CIRC-002 — Six parsers depend on the probe that selects them

**Classification:** MEDIUM / STRUCTURAL. **Recommendation:** REVIEW. **Confidence:** CERTAIN for the source references. **Verified:** false.

Each row is a complete cycle between logical types. The forward reference selects or invokes a parser. The return reference calls `ProviderProbe.normalizedBase`.

| Cycle | Probe-to-parser reference | Parser-to-probe reference |
|---|---|---|
| `ProviderProbe -> SlackParser -> ProviderProbe` | `Sources/StatusCore/ProviderProbe+JSONLandings.swift:45` | `Sources/StatusCore/SlackParser.swift:21` |
| `ProviderProbe -> HerokuParser -> ProviderProbe` | `Sources/StatusCore/ProviderProbe+JSONLandings.swift:62` | `Sources/StatusCore/HerokuParser.swift:45` |
| `ProviderProbe -> GoogleParser -> ProviderProbe` | `Sources/StatusCore/ProviderProbe+JSONLandings.swift:81` | `Sources/StatusCore/GoogleParser.swift:14` |
| `ProviderProbe -> AppleParser -> ProviderProbe` | `Sources/StatusCore/ProviderProbe+JSONLandings.swift:98` | `Sources/StatusCore/AppleParser.swift:12` |
| `ProviderProbe -> IncidentioParser -> ProviderProbe` | `Sources/StatusCore/ProviderProbe+JSONLandings.swift:140` | `Sources/StatusCore/IncidentioParser.swift:13` |
| `ProviderProbe -> OktaParser -> ProviderProbe` | `Sources/StatusCore/ProviderProbe+Okta.swift:40` | `Sources/StatusCore/OktaParser.swift:16` |

The extension declarations bind those forward references to `ProviderProbe`. The common return helper lives in its base file. This produces one connected group of seven mutually reachable types, with six direct two-type cycles. Evidence: `Sources/StatusCore/ProviderProbe+JSONLandings.swift:3`, `Sources/StatusCore/ProviderProbe+Okta.swift:3`, `Sources/StatusCore/ProviderProbe.swift:49`, and the twelve references above.

**Why it exists:** Parsers reuse URL normalization that belongs to the orchestration type. The helper adds a missing scheme, removes query and fragment, and removes trailing path slashes. It does not invoke a parser. Evidence: `Sources/StatusCore/ProviderProbe.swift:49`, `Sources/StatusCore/ProviderProbe.swift:51`, `Sources/StatusCore/ProviderProbe.swift:54`, `Sources/StatusCore/ProviderProbe.swift:57`.

**Impact:** A parser extracted into an independent target would retain a reference to the orchestration type for this small helper. The present package keeps both in one target, so this does not establish a build failure. Evidence: `Sources/StatusCore/SlackParser.swift:21`, `Sources/StatusCore/OktaParser.swift:16`, `Package.swift:8`.

**Weakest link and minimal resolution:** If independent parser reuse is needed, move the unchanged helper body to an internal function in the existing URL-helper file. Change the six parser calls to use that function. Retain the public `ProviderProbe.normalizedBase` entry point as a forwarding method. This preserves existing callers without adding a new target or utility framework. Evidence: `Sources/StatusCore/URLAuth.swift:1`, `Sources/StatusCore/URLAuth.swift:3`, `Sources/StatusCore/ProviderProbe.swift:49`, `Tests/StatusCoreTests/AwsProbeTests.swift:26`, and the six parser references above.

Do not merely delete the parser calls because the probe also normalizes URLs. The parsers expose public entry points, and tests call them directly. Evidence: `Sources/StatusCore/ProviderProbe+JSONLandings.swift:203`, `Sources/StatusCore/SlackParser.swift:4`, `Tests/StatusCoreTests/SlackParserTests.swift:11`, `Tests/StatusCoreTests/OktaParserTests.swift:14`.

Do not substitute `persistedPageURL`. That function preserves query and trailing slash, unlike `normalizedBase`. Evidence: `Sources/StatusCore/ProviderProbe.swift:54`, `Sources/StatusCore/ProviderProbe.swift:57`, `Sources/StatusCore/ProviderProbe.swift:62`, `Tests/StatusCoreTests/RssPersistTests.swift:19`.

**Blast radius:** Eight existing source files: six parsers, `ProviderProbe.swift`, and `URLAuth.swift`. About 20 existing lines move or change. Risk: LOW to MEDIUM if URL behavior and the public entry point stay unchanged. Evidence: the six parser references above, `Sources/StatusCore/ProviderProbe.swift:49`, `Sources/StatusCore/URLAuth.swift:3`.

**Future validation:** Reuse parser and probe tests, including direct parser URL assertions. Add one focused normalization check if the helper moves. Cover scheme, query, fragment, and trailing slash behavior. The tests were not run here. Evidence: `Tests/StatusCoreTests/SlackParserTests.swift:14`, `Tests/StatusCoreTests/OktaParserTests.swift:17`, `Tests/StatusCoreTests/SaaSPlatformProbeTests.swift:28`, `Tests/StatusCoreTests/OktaProbeTests.swift:14`, `Sources/StatusCore/ProviderProbe.swift:49`.

## Low / Debatable Findings

### CIRC-003 — Model/tree file cycle comes from grouping different types

**Classification:** LOW / COSMETIC file grouping, not a barrel artifact. **Recommendation:** KEEP. **Verified:** false.

File cycle: `Models.swift -> ComponentTree.swift -> Models.swift`. `WatchedPage` calls tree aggregation, while tree functions accept `ComponentStatus`. Evidence: `Sources/StatusCore/Models.swift:132`, `Sources/StatusCore/Models.swift:148`, `Sources/StatusCore/ComponentTree.swift:25`, `Sources/StatusCore/Models.swift:21`.

The type chain is `WatchedPage -> ComponentTree -> ComponentStatus -> Severity`. `ComponentStatus` does not call `WatchedPage` or `ComponentTree`. Thus the file cycle does not establish mutual type ownership. Evidence: `Sources/StatusCore/Models.swift:100`, `Sources/StatusCore/Models.swift:132`, `Sources/StatusCore/ComponentTree.swift:25`, `Sources/StatusCore/Models.swift:21`, `Sources/StatusCore/Models.swift:24`.

**Weakest link:** File grouping. Keep the existing arrangement. If an actual module split requires it, move the `WatchedPage` declaration and Codable extension together. No new interface is needed. Evidence: `Sources/StatusCore/Models.swift:100`, `Sources/StatusCore/Models.swift:163`.

**Blast radius:** Recommended change: zero files and zero LOC. Optional split: two files, with 89 physical lines moved. Risk: LOW for a pure move. Preserve enabled-component behavior. Evidence: `Sources/StatusCore/Models.swift:100`, `Sources/StatusCore/Models.swift:188`, `Tests/StatusCoreTests/ComponentTreeSeverityTests.swift:43`.

### CIRC-004 — Persistence file cycle comes from the location of AppConfig

**Classification:** LOW / COSMETIC file grouping, not a barrel artifact. **Recommendation:** KEEP. **Verified:** false.

File cycle: `PageStore.swift -> StateFile.swift -> PageStore.swift`. The store decodes and creates `StateFile`. `StateFile` reads constants from `AppConfig`, which shares the store's file. Evidence: `Sources/StatusCore/PageStore.swift:134`, `Sources/StatusCore/PageStore.swift:200`, `Sources/StatusCore/StateFile.swift:20`, `Sources/StatusCore/StateFile.swift:31`, `Sources/StatusCore/PageStore.swift:3`.

`StateFile.swift` also declares `AppConfig`'s Codable conformance. The `AppConfig` declaration itself does not depend on `PageStore` or `StateFile`. This is file organization, not a recursive load/save call. Evidence: `Sources/StatusCore/StateFile.swift:38`, `Sources/StatusCore/PageStore.swift:3`, `Sources/StatusCore/PageStore.swift:28`.

**Weakest link:** File grouping. Keep it unless persistence becomes a separate module. For that concrete split, move the `AppConfig` declaration beside its existing Codable extension. This removes the file-level return edge without duplicating version constants. Evidence: `Sources/StatusCore/PageStore.swift:3`, `Sources/StatusCore/StateFile.swift:20`, `Sources/StatusCore/StateFile.swift:38`.

**Blast radius:** Recommended change: zero files and zero LOC. Optional move: two existing files and 26 physical lines moved. Risk: LOW for a pure move. Preserve decoding defaults, validation, and save rollback. Evidence: `Sources/StatusCore/PageStore.swift:3`, `Sources/StatusCore/PageStore.swift:28`, `Sources/StatusCore/StateFile.swift:44`, `Sources/StatusCore/PageStore.swift:264`, `Sources/StatusCore/PageStore.swift:204`.

## Recommendations

1. Keep the current target graph. No new package or dependency is needed to address these observations. Evidence: `Package.swift:8`, `Package.swift:11`, `Package.swift:16`, `Package.swift:20`, `Package.swift:24`.
2. Treat CIRC-001 as a small ownership change during relevant Icinga maintenance. Reuse one unchanged predicate and retain the existing security decisions. Evidence: `Sources/StatusCore/ProviderProbe+Icinga.swift:4`, `Sources/StatusCore/HTTPAuth.swift:15`, `Sources/StatusCore/HTTPAuth.swift:24`.
3. Defer CIRC-002 until parser reuse or a target split supplies a concrete need. Then extract only the shared URL function. Evidence: `Package.swift:8`, `Sources/StatusCore/ProviderProbe.swift:49`, `Sources/StatusCore/SlackParser.swift:21`.
4. Keep CIRC-003 and CIRC-004. File splitting alone does not remove a runtime failure demonstrated by this assessment. Evidence: `Sources/StatusCore/Models.swift:132`, `Sources/StatusCore/ComponentTree.swift:25`, `Sources/StatusCore/StateFile.swift:20`, `Sources/StatusCore/PageStore.swift:3`.

## Out of Scope / Flagged for Review

- **Same-type extensions:** Do not count the `Monitor+Polling`/`Monitor+PollConfirmation` method references as a module cycle. Both extend `Monitor`. Evidence: `Sources/StatusCore/Monitor+Polling.swift:3`, `Sources/StatusCore/Monitor+Polling.swift:14`, `Sources/StatusCore/Monitor+PollConfirmation.swift:3`, `Sources/StatusCore/Monitor+PollConfirmation.swift:18`.
- **AppDelegate grouping:** `AppDelegate.swift` uses `ConfigMenuError`, while that error's file also extends `AppDelegate`. The error type has no delegate dependency. Keep this arrangement. Evidence: `Sources/greendot/AppDelegate.swift:174`, `Sources/greendot/AppDelegate+Config.swift:5`, `Sources/greendot/AppDelegate+Config.swift:13`.
- **Callbacks:** Menu handlers and editor callbacks are not concrete imports back to `AppDelegate`. Do not infer a dependency cycle from callbacks alone. Evidence: `Sources/greendot/MenuBuilder.swift:20`, `Sources/greendot/AppDelegate.swift:139`, `Sources/greendot/AppDelegate.swift:182`, `Sources/greendot/StatusPageEditor.swift:8`.
- **Barrels:** The import scan found no `@_exported import` declarations. The package graph uses explicit target dependencies. The LOW observations concern co-located types, not re-export files. Evidence: `Package.swift:11`, `Package.swift:16`, `Package.swift:20`, `Package.swift:24`, `Sources/StatusCore/Models.swift:21`, `Sources/StatusCore/PageStore.swift:3`.
- **Runtime checks:** Native builds, tests, object-retention analysis, and dynamic call-graph verification remain outside this static assessment. No compile, initialization, or memory failure is asserted. The repository requires native Swift/AppKit tooling. Evidence: `Makefile:10`, `Makefile:13`, `Sources/greendot/AppDelegate.swift:1`, `README.md:30`.
- **Security policy:** This report assesses dependency direction only. It does not approve or redesign the TLS exception. Any later predicate move must preserve its boundary conditions and receive focused validation. Evidence: `Sources/StatusCore/ProviderProbe+Icinga.swift:4`, `Sources/StatusCore/HTTPAuth.swift:24`, `Sources/StatusCore/HTTPClient.swift:118`, `Tests/StatusCoreTests/HTTPAuthTests.swift:23`.

## Machine-Readable Findings

The entries describe analysis findings. All `verified` values remain `false`. `REVIEW` requires a scope decision before implementation. `KEEP` requests no change.

```json
{
  "findings": [
    {
      "id": "circular-deps-001",
      "file": "Sources/StatusCore/HTTPAuth.swift",
      "line": 15,
      "severity": "MEDIUM",
      "confidence": "CERTAIN",
      "recommendation": "REVIEW",
      "cycle_kind": "STRUCTURAL",
      "detail": "A file/layer cycle connects Sources/StatusCore/HTTPClient.swift:82 and Sources/StatusCore/HTTPClient.swift:118 to Sources/StatusCore/HTTPAuth.swift:15 and Sources/StatusCore/HTTPAuth.swift:24, then to Sources/StatusCore/ProviderProbe+Icinga.swift:4 and back through its HTTPClient parameter at Sources/StatusCore/ProviderProbe+Icinga.swift:82. The protocol itself has no return dependency. During relevant maintenance, move the unchanged predicate into HTTPAuth. This affects two source files and requires preservation of all TLS and URL conditions.",
      "verified": false
    },
    {
      "id": "circular-deps-002",
      "file": "Sources/StatusCore/ProviderProbe.swift",
      "line": 49,
      "severity": "MEDIUM",
      "confidence": "CERTAIN",
      "recommendation": "REVIEW",
      "cycle_kind": "STRUCTURAL",
      "detail": "ProviderProbe selects six parsers at Sources/StatusCore/ProviderProbe+JSONLandings.swift:45, Sources/StatusCore/ProviderProbe+JSONLandings.swift:62, Sources/StatusCore/ProviderProbe+JSONLandings.swift:81, Sources/StatusCore/ProviderProbe+JSONLandings.swift:98, Sources/StatusCore/ProviderProbe+JSONLandings.swift:140, and Sources/StatusCore/ProviderProbe+Okta.swift:40. Return references call its URL helper at Sources/StatusCore/SlackParser.swift:21, Sources/StatusCore/HerokuParser.swift:45, Sources/StatusCore/GoogleParser.swift:14, Sources/StatusCore/AppleParser.swift:12, Sources/StatusCore/IncidentioParser.swift:13, and Sources/StatusCore/OktaParser.swift:16. If independent parser reuse is required, extract the unchanged helper into the existing URLAuth.swift file and preserve the public probe method as a forwarder. Eight source files would change.",
      "verified": false
    },
    {
      "id": "circular-deps-003",
      "file": "Sources/StatusCore/Models.swift",
      "line": 132,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "KEEP",
      "cycle_kind": "COSMETIC",
      "detail": "Sources/StatusCore/Models.swift:132 calls ComponentTree, whose parameter at Sources/StatusCore/ComponentTree.swift:25 uses ComponentStatus declared at Sources/StatusCore/Models.swift:21. This is a file-grouping cycle. The distinct type chain does not return from ComponentStatus to WatchedPage. Keep the arrangement unless an actual module split requires moving WatchedPage.",
      "verified": false
    },
    {
      "id": "circular-deps-004",
      "file": "Sources/StatusCore/StateFile.swift",
      "line": 20,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "KEEP",
      "cycle_kind": "COSMETIC",
      "detail": "Sources/StatusCore/PageStore.swift:134 decodes StateFile, which refers at Sources/StatusCore/StateFile.swift:20 to AppConfig declared in Sources/StatusCore/PageStore.swift:3. Sources/StatusCore/StateFile.swift:38 also extends AppConfig. The model has no store dependency. Keep this file grouping unless a concrete persistence split requires moving the AppConfig declaration beside its conformance.",
      "verified": false
    }
  ]
}
```
