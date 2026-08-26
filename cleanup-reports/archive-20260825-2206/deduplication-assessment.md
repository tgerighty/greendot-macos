# Deduplication Assessment

Scope: `Sources/` and `Tests/` (plus UITests for comparison). Product code was not changed.

DRY was applied only where a shared helper would shrink the code and keep behaviour in one place. Three similar lines, protocol wrappers around one-off parsers, and parallel tests of different paths were left alone.

## Executive Summary

- Total issues found: 16
- Severity breakdown: HIGH=2, MEDIUM=8, LOW=6
- Top 3 priorities
  1. Move `find` / `collect` / key collection onto `ComponentStatus`, and component toggle/set-all onto `WatchedPage` (Monitor and ComponentPicker currently copy the same tree walk and enable/disable rules).
  2. Give `Severity` one display string used by toasts, the empty-page menu row, and Statuspal leaf text.
  3. Share the GitHub `MapHTTPClient` + `Monitor` fixture in `ComponentToggleTests` (two tests paste the same JSON and setup).
- Estimated impact: one `ComponentStatus` helper plus one `WatchedPage` mutator removes about 40 duplicated lines and stops checkbox state drifting from persisted `disabledComponentNames`. A `Severity` label helper stops toast vs menu wording from diverging. Test fixture helpers mainly shorten `ComponentToggleTests` and `ProbeAndMonitorTests`. Parser JSON glue is real but small; collapsing the three parsers would add more code than it removes.

## Critical Findings

### dedup-001 — Exact `find` / `collect` copy (HIGH, CERTAIN, CONSOLIDATE)

`Monitor` and `ComponentPicker` both own this private pair, byte for byte:

```95:105:Sources/StatusCore/Monitor.swift
    private static func find(_ key: String, in items: [ComponentStatus]) -> ComponentStatus? {
        for item in items {
            if item.id == key || item.name == key { return item }
            if let hit = find(key, in: item.children) { return hit }
        }
        return nil
    }

    private static func collect(_ item: ComponentStatus) -> [ComponentStatus] {
        [item] + item.children.flatMap(collect)
    }
```

```163:173:Sources/greendot/ComponentPicker.swift
    private static func find(_ key: String, in items: [ComponentStatus]) -> ComponentStatus? {
        for item in items {
            if item.id == key || item.name == key { return item }
            if let hit = find(key, in: item.children) { return hit }
        }
        return nil
    }

    private static func collect(_ item: ComponentStatus) -> [ComponentStatus] {
        [item] + item.children.flatMap(collect)
    }
```

`Monitor.componentKeys` (`Sources/StatusCore/Monitor.swift:89-93`) is the same walk with `[id, name]` flattened. `ComponentPicker.setEnabled(_:nodes:)` (`Sources/greendot/ComponentPicker.swift:121-123`) builds the same key list.

**Why DRY helps:** these 11 lines implement the only tree index in the app. A later change to id-vs-name matching will be missed on one side. Put `find`, `collect`, and `keys` on `ComponentStatus` (StatusCore) so AppKit code can call them.

### dedup-002 — Identical GitHub monitor fixture in two tests (HIGH, CERTAIN, CONSOLIDATE)

`testToggleComponentPersists` and `testSetAllComponentsOffThenOn` paste the same JSON, client, add, and red-severity assert:

```37:53:Tests/StatusCoreTests/ComponentToggleTests.swift
        let json = """
        {
          "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
          "status": {"indicator": "none"},
          "components": [
            {"name": "API", "status": "operational", "group": false},
            {"name": "Git", "status": "major_outage", "group": false}
          ],
          "incidents": []
        }
        """
        let client = MapHTTPClient(byPath: ["/api/v2/summary.json": (Data(json.utf8), 200)])
        let monitor = Monitor(store: PageStore(directory: dir), client: client)
        try monitor.load()
        try await monitor.add(url: URL(string: "https://www.githubstatus.com")!, name: nil)
        let id = monitor.pages[0].id
        XCTAssertEqual(monitor.pages[0].displaySeverity, .red)
```

The second copy is at `Tests/StatusCoreTests/ComponentToggleTests.swift:67-82` (`load()` omitted). A local helper such as `monitorWithGitHubOutage()` keeps the two tests as separate behaviour checks without the pasted setup.

## Medium Findings

### dedup-003 — Component toggle algorithm (MEDIUM, LIKELY, CONSOLIDATE)

Not byte-identical, but the same rule lives in two layers.

Monitor persist path (`Sources/StatusCore/Monitor.swift:60-75`): find node, collect descendants, take id+name keys, if all enabled then union into `disabledComponentNames` else remove keys.

ComponentPicker UI path (`Sources/greendot/ComponentPicker.swift:107-131`): same find/collect/allOn/setEnabled, then `onToggleComponent` which calls Monitor again. `allClicked` (`ComponentPicker.swift:98-105`) plus `setAllComponents` (`Monitor.swift:77-87`) repeat the “every key on/off” rule.

**Why DRY helps:** the picker currently re-implements enable/disable in a local `Set` and then asks Monitor to do it again. If the two disagree, checkboxes lie. Move `toggleComponent(_:)` and `setAllComponents(enabled:)` onto `WatchedPage`, and let Monitor save after mutate. The picker can keep mixed-state drawing, but it should not own a second copy of the key math.

### dedup-004 — `isOff` is the inverse of `isComponentEnabled` (MEDIUM, CERTAIN, CONSOLIDATE)

```133:135:Sources/greendot/ComponentPicker.swift
    private func isOff(_ component: ComponentStatus) -> Bool {
        disabledNames.contains(component.id) || disabledNames.contains(component.name)
    }
```

```125:127:Sources/StatusCore/Models.swift
    public func isComponentEnabled(_ component: ComponentStatus) -> Bool {
        !disabledComponentNames.contains(component.id) && !disabledComponentNames.contains(component.name)
    }
```

`isComponentEnabled(_ name: String)` only checks the name, so the component overload is the one to reuse. ComponentPicker should call `WatchedPage.isComponentEnabled` (or a `Set` helper on the model) instead of a private inverse.

### dedup-005 — Severity display strings (MEDIUM, CERTAIN, CONSOLIDATE)

Two identical switches:

```32:39:Sources/StatusCore/ToastPolicy.swift
    private static func body(for snapshot: PageSnapshot) -> String {
        if snapshot.isUnreachable { return "Unreachable" }
        switch snapshot.overall {
        case .green: return "Operational"
        case .yellow: return "Degraded"
        case .red: return "Major outage"
        case .grey: return "Unreachable"
        }
    }
```

```154:160:Sources/greendot/MenuBuilder.swift
    private static func overallText(_ severity: Severity) -> String {
        switch severity {
        case .green: return "Operational"
        case .yellow: return "Degraded"
        case .red: return "Major outage"
        case .grey: return "Unreachable"
        }
    }
```

`StatuspalParser.node` (`Sources/StatusCore/StatuspalParser.swift:44-50`) uses the same four labels, except yellow becomes `"Maintenance"` when `type == "scheduled"`.

**Why DRY helps:** toast body and the no-components menu row must stay the same. Put `displayText` on `Severity` (or `PageSnapshot`). Keep the Statuspal `"Maintenance"` exception at the parser; do not fold `StatusMapping.statuspageComponentText` into this, because Statuspage has extra tokens (`Partial outage`).

### dedup-006 — Parser page name / URL extraction (MEDIUM, CERTAIN, CONSOLIDATE)

Three parsers copy this pair (Statuspal splits the name line):

- `Sources/StatusCore/InstatusParser.swift:13-14`
- `Sources/StatusCore/StatuspageParser.swift:23-24`
- `Sources/StatusCore/StatuspalParser.swift:9-11`

```swift
let name = (page["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? sourceURL.host ?? "Status page"
let pageURL = (page["url"] as? String).flatMap(URL.init(string:)) ?? sourceURL
```

A two-line helper such as `ParserSupport.pageIdentity(from:sourceURL:)` is enough. Do not introduce a parser base class for this.

### dedup-007 — JSON object decode (MEDIUM, LIKELY, CONSOLIDATE)

`StatuspageParser.decode` (`Sources/StatusCore/StatuspageParser.swift:92-97`) throws `ParserError.invalidJSON` when the root is not a dictionary. `InstatusParser` (`Sources/StatusCore/InstatusParser.swift:5`) and `StatuspalParser` (`Sources/StatusCore/StatuspalParser.swift:5`) inline `JSONSerialization.jsonObject` and throw `notThisProvider` instead.

Share `decode` and keep the current error split: invalid root → `invalidJSON`; missing provider keys → `notThisProvider`. That is a behaviour fix as well as DRY.

Incident `compactMap` blocks look similar but use different keys (`name` vs `title`, `shortlink` vs `url`). Leave those in each parser.

### dedup-008 — Group vs leaf component title (MEDIUM, LIKELY, CONSOLIDATE)

```136:138:Sources/greendot/MenuBuilder.swift
        let title = component.isGroup || !component.children.isEmpty
            ? component.name
            : "\(component.name)    \(component.statusText)"
```

```78:83:Sources/greendot/ComponentPicker.swift
            let pad = String(repeating: "    ", count: indent)
            let title: String
            if component.isGroup || !component.children.isEmpty {
                title = "\(pad)\(component.name)"
            } else {
                title = "\(pad)\(component.name)  —  \(component.statusText)"
            }
```

The condition `isGroup || !children.isEmpty` is the duplicate. Separators differ (`four spaces` vs `em dash`) and the picker adds indent, so do not force one title string. A `ComponentStatus.showsStatusText` (or `isLeaf`) property would still be worth it.

### dedup-009 — Monitor “find page, mutate, save” (MEDIUM, LIKELY, CONSOLIDATE)

Four methods start the same way:

```swift
guard let index = config.pages.firstIndex(where: { $0.id == id }) else { return }
// mutate config.pages[index]
try store.save(config)
```

Call sites: `edit` (`Sources/StatusCore/Monitor.swift:41`), `toggleNotifications` (`:55`), `toggleComponent` (`:61`), `setAllComponents` (`:78`). `remove` is a different shape (`removeAll`).

A private `mutatePage(id:_:)` that returns after a missed id and then saves would cut the noise. Combine this with moving toggle/set-all onto `WatchedPage` (dedup-003).

### dedup-010 — Repeated temp-dir + MapHTTPClient setup (MEDIUM, LIKELY, CONSOLIDATE)

Beyond the exact GitHub paste (dedup-002), the same temp-store dance appears in:

- `Tests/StatusCoreTests/ComponentToggleTests.swift` (four tests: `:35`, `:65`, `:94`, `:163`)
- `Tests/StatusCoreTests/ProbeAndMonitorTests.swift` (`statuspageJSON` at `:5`, then `:60`, `:74`, `:97`, `:147`, `:176`)

Typical shape: UUID temp dir, `defer { removeItem }`, `MapHTTPClient(byPath: ["/api/v2/summary.json": …])`, `Monitor(store:client:)`, `add`.

A file-local `makeMonitor(json:)` / `tempStore()` helper is enough. Do not share fixtures across test targets.

## Low / Debatable Findings

### dedup-011 — Instatus component mapping not in StatusMapping (LOW, LIKELY, CONSOLIDATE)

`InstatusParser` maps component status inline (`Sources/StatusCore/InstatusParser.swift:26-31`: `OPERATIONAL`/`UP` → green, `MAJOROUTAGE` → red, else yellow). Page-level Instatus mapping already lives in `StatusMapping.instatusPage`. Statuspage and Statuspal component maps are in `StatusMapping`.

Move `instatusComponent` next to `instatusPage` for consistency. Do not merge it with `statuspageComponent`; the tokens differ (`OPERATIONAL` vs `operational`).

### dedup-012 — UITest wait loops (LOW, LIKELY, KEEP SEPARATE)

`UITests/GreenDotUITests/GreenDotUITests.swift` has three deadline polls: `waitForFile` (`:236`), `waitForSaved` (`:250`), `assertOpened` (`:264`). Timeouts and success checks differ. A `waitUntil` helper is optional; the tests are already short.

### dedup-013 — `Monitor.add` vs `edit` probe (LOW, LIKELY, KEEP SEPARATE)

Both call `ProviderProbe.probe`, `normalizedBase`, and `trimmed(name) ?? snapshot.name` (`Sources/StatusCore/Monitor.swift:28-47`). The rest diverges (append a new page vs mutate url/name/snapshot). Extracting `probedIdentity` would save three lines. Leave it.

### dedup-014 — Test `PageSnapshot` factories (LOW, POSSIBLE, KEEP SEPARATE)

`AggregatorTests.snap` (`Tests/StatusCoreTests/AggregatorTests.swift:39`) and `ToastPolicyTests.snap` (`Tests/StatusCoreTests/ToastPolicyTests.swift:55`) both wrap `PageSnapshot` with empty components. Names and URLs differ. A shared test module is heavier than two 10-line helpers.

### dedup-015 — UITestDriver view walk (LOW, POSSIBLE, KEEP SEPARATE)

`find(_:in:)` (`Sources/greendot/UITestDriver.swift:49`) and `collect(from:into:)` (`:61`) both recurse `subviews` and `NSScrollView.documentView`. One searches, one lists. Sharing a walk would add a visitor for little gain.

### dedup-016 — `nestedPage` test fixtures (LOW, POSSIBLE, KEEP SEPARATE)

`MenuBuilderTests.nestedPage` (`Tests/greendotTests/MenuBuilderTests.swift:103`) builds Box Web Application + Content API. `PanelLifecycleTests.nestedPage` (`Tests/greendotTests/PanelLifecycleTests.swift:102`) builds the same group with 20 children for crash tests. Same names, different trees. Do not unify.

## Recommendations

1. **Do first:** add `ComponentStatus.find`, `collect`, and `keys` in StatusCore. Point Monitor and ComponentPicker at them. Then add `WatchedPage.toggleComponent` / `setAllComponents` so enable/disable has one owner. Delete `ComponentPicker.isOff`.
2. **Do second:** `Severity.displayText` (Operational / Degraded / Major outage / Unreachable). Use it from `ToastPolicy` and `MenuBuilder`. Statuspal may still override yellow to Maintenance.
3. **Do in tests:** `ComponentToggleTests.monitorWithGitHubOutage()` (and optionally `tempDir()`). Stop pasting the GitHub JSON.
4. **Do if touching parsers:** `ParserSupport.decodeJSON` + `pageIdentity`. Move Instatus component mapping into `StatusMapping`. Do not merge the three `parse` methods.
5. **Do not:** a `StatusParser` protocol, a shared HTTP client, a MenuBuilder/ComponentPicker title unifier, or parameterized UITests for the click-open rows.

## Out of Scope / Flagged for Review

These look related by name or signature and should stay separate.

| Cluster | Why keep separate |
|---|---|
| `InstatusParser` / `StatuspageParser` / `StatuspalParser` (`parse(data:sourceURL:)`) | Same entry point, different JSON. A protocol would only restate the closures already passed to `ProviderProbe.attempt`. |
| `StatusMapping.statuspage*` / `statuspal` / `instatusPage` | Same output type (`Severity`), different vendor tokens. |
| `URLSessionHTTPClient` / `MapHTTPClient` / `DirectoryHTTPClient` / test `FailingHTTPClient` | Protocol implementations for live HTTP, unit maps, UI-test fixtures, and network failure. |
| `MenuBuilder` / `MenuCommands` / `MenuClickOpener` / `MenuBarController` / `AppEditMenu` | Adjacent names, different jobs (build, invoke/dump, click-through, status item, accessory Edit menu). |
| `URLOpener` vs `MenuClickOpener` | HTTP(S) open vs NSMenu click delivery. |
| `ProviderProbe` sequential Statuspage then Instatus `attempt` calls | Ordered fallback, clearer as two `if let` than a table of parsers. |
| `MenuBarController.reloadMenu` vs `popMenuOnScreen` | Same “defer while tracking” idea, different follow-up (`applyMenu` vs `presentPopMenu`). |
| UITests click-open rows (`testPageRowClickOpensStatusURL` and siblings) vs `MenuBuilderTests` equivalents | Three-line tests of different rows; parameterizing hides the row under test. Dual UI + unit coverage is intentional. |
| `PanelLifecycleTests.testUITestDriverTogglesEveryComponentFiveTimes` vs `testClickingEveryComponentFiveTimesDoesNotCrash` | Two click paths (identifier driver vs `performClick`). |
| `Aggregator.barSeverity` / `fromSeverities` / `severity(from:)` | Thin wrappers over one ranking, not copy-paste. |
| `LaunchAtLogin.enable` vs `toggle` | Both call `SMAppService.mainApp.register()`; enable is first-run, toggle is the menu. |
| `PagePanelController.saveTapped` `https://` prefix vs `ProviderProbe.normalizedBase` | User string vs `URLComponents`. |
| `ComponentStatus` / `WatchedPage` custom `Decodable` | Same missing-key defaulting pattern; extracting a decoder helper would not help. |
| jscpd | Not run. Swift enums and JSON literals clone poorly in token clone detectors; grep + read was used instead. |

## Machine-Readable Findings

```json
{"findings": [
  {"id": "dedup-001", "file": "Sources/StatusCore/Monitor.swift", "line": 95, "severity": "HIGH",
   "confidence": "CERTAIN", "recommendation": "CONSOLIDATE",
   "detail": "Monitor.find/collect is an exact copy of ComponentPicker.find/collect; componentKeys is the same walk.", "verified": true},
  {"id": "dedup-002", "file": "Tests/StatusCoreTests/ComponentToggleTests.swift", "line": 37, "severity": "HIGH",
   "confidence": "CERTAIN", "recommendation": "CONSOLIDATE",
   "detail": "testToggleComponentPersists and testSetAllComponentsOffThenOn paste the same GitHub JSON, MapHTTPClient, add, and red assert.", "verified": true},
  {"id": "dedup-003", "file": "Sources/StatusCore/Monitor.swift", "line": 60, "severity": "MEDIUM",
   "confidence": "LIKELY", "recommendation": "CONSOLIDATE",
   "detail": "toggleComponent/setAllComponents and ComponentPicker.componentClicked/allClicked/setEnabled implement the same enable/disable key rules.", "verified": false},
  {"id": "dedup-004", "file": "Sources/greendot/ComponentPicker.swift", "line": 133, "severity": "MEDIUM",
   "confidence": "CERTAIN", "recommendation": "CONSOLIDATE",
   "detail": "ComponentPicker.isOff is the inverse of WatchedPage.isComponentEnabled(_ component:).", "verified": false},
  {"id": "dedup-005", "file": "Sources/StatusCore/ToastPolicy.swift", "line": 32, "severity": "MEDIUM",
   "confidence": "CERTAIN", "recommendation": "CONSOLIDATE",
   "detail": "ToastPolicy.body and MenuBuilder.overallText use the same Operational/Degraded/Major outage/Unreachable switch.", "verified": false},
  {"id": "dedup-006", "file": "Sources/StatusCore/InstatusParser.swift", "line": 13, "severity": "MEDIUM",
   "confidence": "CERTAIN", "recommendation": "CONSOLIDATE",
   "detail": "All three parsers copy empty-name fallback to host and URL fallback to sourceURL.", "verified": false},
  {"id": "dedup-007", "file": "Sources/StatusCore/StatuspageParser.swift", "line": 92, "severity": "MEDIUM",
   "confidence": "LIKELY", "recommendation": "CONSOLIDATE",
   "detail": "JSONSerialization-to-dictionary is extracted only in StatuspageParser; the others inline it and throw a different error.", "verified": false},
  {"id": "dedup-008", "file": "Sources/greendot/MenuBuilder.swift", "line": 136, "severity": "MEDIUM",
   "confidence": "LIKELY", "recommendation": "CONSOLIDATE",
   "detail": "MenuBuilder and ComponentPicker both hide statusText when isGroup or children is non-empty.", "verified": false},
  {"id": "dedup-009", "file": "Sources/StatusCore/Monitor.swift", "line": 41, "severity": "MEDIUM",
   "confidence": "LIKELY", "recommendation": "CONSOLIDATE",
   "detail": "edit, toggleNotifications, toggleComponent, and setAllComponents repeat firstIndex-by-id then store.save.", "verified": false},
  {"id": "dedup-010", "file": "Tests/StatusCoreTests/ComponentToggleTests.swift", "line": 35, "severity": "MEDIUM",
   "confidence": "LIKELY", "recommendation": "CONSOLIDATE",
   "detail": "Temp-dir PageStore plus MapHTTPClient summary.json setup is repeated across ComponentToggleTests and ProbeAndMonitorTests.", "verified": false},
  {"id": "dedup-011", "file": "Sources/StatusCore/InstatusParser.swift", "line": 26, "severity": "LOW",
   "confidence": "LIKELY", "recommendation": "CONSOLIDATE",
   "detail": "Instatus component severity is inline while other provider maps live in StatusMapping.", "verified": false},
  {"id": "dedup-012", "file": "UITests/GreenDotUITests/GreenDotUITests.swift", "line": 236, "severity": "LOW",
   "confidence": "LIKELY", "recommendation": "KEEP SEPARATE",
   "detail": "waitForFile, waitForSaved, and assertOpened are similar deadline polls with different predicates.", "verified": false},
  {"id": "dedup-013", "file": "Sources/StatusCore/Monitor.swift", "line": 28, "severity": "LOW",
   "confidence": "LIKELY", "recommendation": "KEEP SEPARATE",
   "detail": "add and edit share probe, normalizedBase, and trimmed name; remaining work diverges.", "verified": false},
  {"id": "dedup-014", "file": "Tests/StatusCoreTests/AggregatorTests.swift", "line": 39, "severity": "LOW",
   "confidence": "POSSIBLE", "recommendation": "KEEP SEPARATE",
   "detail": "AggregatorTests.snap and ToastPolicyTests.snap are small PageSnapshot factories with different defaults.", "verified": false},
  {"id": "dedup-015", "file": "Sources/greendot/UITestDriver.swift", "line": 49, "severity": "LOW",
   "confidence": "POSSIBLE", "recommendation": "KEEP SEPARATE",
   "detail": "find and collect both walk NSView/NSScrollView; merging them would add a visitor without shrinking call sites.", "verified": false},
  {"id": "dedup-016", "file": "Tests/greendotTests/MenuBuilderTests.swift", "line": 103, "severity": "LOW",
   "confidence": "POSSIBLE", "recommendation": "KEEP SEPARATE",
   "detail": "nestedPage fixtures in MenuBuilderTests and PanelLifecycleTests share Box names but different child counts.", "verified": false}
]}
```
