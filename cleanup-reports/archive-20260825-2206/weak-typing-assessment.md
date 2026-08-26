# Weak Typing Assessment — greendot

Scope: `Sources/` (product: `StatusCore` + `greendot`) and `Tests/` + `UITests/`
for IUO / selector / force-unwrap inventory. Excludes `.build/`, `greendot.app/`,
`cleanup-reports/`. Swift 5.9, macOS 13, AppKit menu-bar app. This report does
not invent findings to hit a quota, and it does **not** recommend replacing
`Any` at JSON parse boundaries with guessed Codable shapes.

## Executive Summary

Product code is tightly typed once data is inside the app. Domain models
(`Severity`, `ComponentStatus`, `PageSnapshot`, `WatchedPage`, `AppConfig`) are
enums/structs with `Codable` on the **local** config file. `Any` / `[String: Any]`
appear almost only at true boundaries: three external status-page JSON parsers,
`NSEvent` monitor tokens, `NSMenuItem.representedObject`, `URLResponse`,
`Notification.object`, and AppKit view-tree walks.

| Metric | Production (`Sources/`) | Tests + UITests |
|---|---|---|
| `Any` / `[String: Any]` lines | 18 | 0 (`AnyObject?` × 1) |
| `as?` | 50 | 3 |
| `as!` | 0 | 0 |
| `try!` | 0 | 0 |
| Force unwrap `!` (non-boolean) | 1 (`groupID!`) | 36× `URL(string:)!` literals |
| IUO (`Type!`) | 0 | 6 (UITest `setUp`) |
| `NSSelectorFromString` | 0 | 1 |
| `Selector(("…"))` | 2 | 0 |
| `objc_setAssociatedObject` | 0 | 0 |
| `@unchecked Sendable` | 2 types | 0 |

**Actionable strengthenings: 3 Low** (one production force unwrap, one ObjC
uniqueness bridge, one test selector). **KEEP: all JSON `[String: Any]` and all
AppKit `Any` tokens.** Zero Critical.

The JSON parsers already fail closed (`ParserError.notThisProvider` /
`compactMap` skip) and immediately map into `PageSnapshot`. That is the correct
unknown-at-boundary shape. Do not “tighten” those dictionaries with sample-based
Decodable structs.

## Findings

### weak-001 — `StatuspageParser.nest` force-unwraps `groupID!`

- File: `Sources/StatusCore/StatuspageParser.swift:65`
- After `parsed.filter { $0.groupID != nil && !$0.isGroup }`, the next line is
  `Dictionary(grouping: grouped) { $0.groupID! }`. Swift does not promote
  `String?` across that filter, so this is a real `!`. It is safe only while the
  filter stays in lockstep with the unwrap.
- Proposed: drop the `!` with `compactMap`:

```swift
let grouped: [(String, Row)] = parsed.compactMap { item in
    guard let groupID = item.groupID, !item.isGroup else { return nil }
    return (groupID, item)
}
let childrenByGroup = Dictionary(grouping: grouped, by: \.0).mapValues { $0.map(\.1) }
```

- Severity: LOW (filter currently guarantees non-nil). Confidence: HIGH.
- Recommendation: STRENGTHEN.

### weak-002 — `NSOrderedSet` uniqueness then `as? [String]`

- File: `Sources/StatusCore/ProviderProbe.swift:124`
- `Array(NSOrderedSet(array: subdomains)) as? [String] ?? subdomains` uses an
  untyped ObjC collection as a uniqueness tool. `Array(NSOrderedSet)` is
  `[Any]`. If the `as? [String]` bridge fails, the `??` **keeps duplicates**
  instead of failing.
- Proposed: stay in Swift:

```swift
var unique: [String] = []
var seen = Set<String>()
for name in subdomains where seen.insert(name).inserted {
    unique.append(name)
}
```

- Severity: LOW (today’s `[String]` input does bridge). Confidence: HIGH.
- Recommendation: STRENGTHEN.

### weak-003 — test helper uses `AnyObject` + `NSSelectorFromString("invoke")`

- File: `Tests/greendotTests/MenuBuilderTests.swift:91-92`
- `item.representedObject as AnyObject?` then `perform(NSSelectorFromString("invoke"))`
  is a stringly-typed dispatch. Production already stores a `TargetAction` and
  invokes it with `as? TargetAction` (`MenuCommands.swift:41`,
  `MenuClickOpener.swift:62`). The test module `@testable import`s `greendot`.
- Proposed:

```swift
guard let item, let box = item.representedObject as? TargetAction else { return }
box.invoke()
```

- Severity: LOW (tests only). Confidence: HIGH.
- Recommendation: STRENGTHEN.

### weak-004 — `[String: Any]` in Statuspage / Instatus / Statuspal parsers

- Files: `Sources/StatusCore/StatuspageParser.swift` (decode + field `as?`),
  `InstatusParser.swift:5-24`, `StatuspalParser.swift:5-51`
- `JSONSerialization.jsonObject(with:)` returns `Any`. Top-level
  `as? [String: Any]` plus per-key `as? String` / `as? Bool` / `as? Int` is the
  provider-sniff: a miss throws `ParserError.notThisProvider` (or skips the
  row). Nested objects never escape the parser; results are `PageSnapshot`,
  `ComponentStatus`, `Incident`, `Severity`.
- Statuspal `id` is `Int` **or** `String` (`rawID as? Int` / `as? String`). A
  guessed `Decodable` struct that picks one would drop real pages.
- Local config already uses `JSONDecoder` (`PageStore.swift:50`). That split
  (typed own file / untyped foreign JSON) is correct.
- Proposed: **none**. Do not replace boundary `Any` with sample Codable DTOs.
- Severity: n/a. Confidence: HIGH.
- Recommendation: KEEP.

### weak-005 — `NSEvent` monitor stored as `Any?`

- File: `Sources/greendot/MenuClickOpener.swift:10`
- `NSEvent.addLocalMonitorForEvents(matching:handler:)` returns `Any?`.
  `NSEvent.removeMonitor(_:)` takes `Any`. There is no stronger public token
  type.
- Recommendation: KEEP. Confidence: HIGH.

### weak-006 — `NSMenuItem.representedObject as? TargetAction`

- Files: `Sources/greendot/MenuCommands.swift:41`,
  `Sources/greendot/MenuClickOpener.swift:62`; write site
  `MenuBuilder.swift:191`
- `representedObject` is AppKit `Any?`. Both reads use `as?` and fail closed
  (`return false` / `return event`). `TargetAction` is the typed box; `#selector(TargetAction.invoke)` is the typed action.
- Recommendation: KEEP. Confidence: HIGH.

### weak-007 — `URLResponse as? HTTPURLResponse`

- File: `Sources/StatusCore/HTTPClient.swift:16`
- `URLSession.data(from:)` yields `URLResponse`. Status code lives on
  `HTTPURLResponse`. `as?` with `?? 0` is the API boundary (non-HTTP → miss).
- Recommendation: KEEP. Confidence: HIGH.

### weak-008 — `DistributedNotificationCenter` payload `as? String`

- File: `Sources/greendot/AppDelegate.swift:200`
- `Notification.object` is `Any?`. UI-test hooks send a string path /
  identifier. `as? String ?? ""` fails closed (empty handler no-op).
- Recommendation: KEEP. Confidence: HIGH.

### weak-009 — AppKit view-tree `as? NSButton` / `NSTextField` / `NSScrollView`

- File: `Sources/greendot/UITestDriver.swift:35-65` (also
  `Tests/greendotTests/PanelLifecycleTests.swift:90`)
- Walking `NSView.subviews` has no typed child list. `as?` is the AppKit
  boundary; misses return `nil` / skip.
- Recommendation: KEEP. Confidence: HIGH.

### weak-010 — UITest IUOs assigned in `setUpWithError`

- File: `UITests/GreenDotUITests/GreenDotUITests.swift:8-13`
- `XCUIApplication!` and path `URL!`s are the XCTest `setUp` pattern. Every
  IUO is assigned before tests run. Production has **zero** IUOs.
- Recommendation: KEEP. Confidence: HIGH.

### weak-011 — `@unchecked Sendable` on `Monitor` and `PageStore`

- Files: `Sources/StatusCore/Monitor.swift:3`,
  `Sources/StatusCore/PageStore.swift:20`
- Classes with mutable `config` / file I/O, called from launch, `Timer`+`Task`,
  and menu closures. `@unchecked Sendable` is a concurrency escape hatch, not
  `Any`, but it erases isolation the same way.
- Proposed (optional, larger than this pass): isolate `Monitor` on `@MainActor`
  (UI already hops to `MainActor.run` after `pollAll`) or guard `config` with a
  lock. Do not paper over it with more `Any`.
- Severity: LOW (app is effectively single-window, main-thread UI).
  Confidence: MEDIUM.
- Recommendation: REVIEW.

### weak-012 — string `Selector(("undo:"))` / `Selector(("redo:"))`

- File: `Sources/greendot/AppEditMenu.swift:27-28`
- Cut/copy/paste/select-all use typed `#selector(NSText.*)`; undo/redo use
  string selectors because the target is the first responder, not a concrete
  instance. Same family as `NSSelectorFromString`, but this **is** the AppKit
  first-responder contract (`"undo:"` / `"redo:"`).
- Recommendation: KEEP. Confidence: HIGH.

## Out of Scope / not findings

- **No `as!`, `try!`, `objc_setAssociatedObject`, or production IUO.**
- **Test `URL(string: "https://…")!`** (36 literals, plus `javascript:alert(1)`
  in `URLOpenerTests`). Compile-time-known URLs; XCTest convention. Production
  uses `if let` / `guard let` (`PagePanelController.swift:143`,
  `AppDelegate.swift:46`, `ProviderProbe.swift:128`).
- **`FileManager.urls(for: .applicationSupportDirectory, …)[0]`**
  (`PageStore.swift:33`). Foundation always returns at least one URL for this
  search path; not an `Any`/`!` escape.
- **`error as NSError`** (`PageStore.swift:42`). Required to read
  `NSCocoaErrorDomain` / missing-file codes. KEEP at the Cocoa error boundary.
- **`#selector` on `NSButton` / `NSMenuItem` / `NSApplication` / `NSText`.**
  Typed AppKit actions, not `NSSelectorFromString`.
- **`catch { return .miss }` in `ProviderProbe.attempt`.** Error policy for
  provider sniffing, not a type hole.

## Priorities

1. **weak-001** (STRENGTHEN, LOW) — remove the only production force unwrap.
2. **weak-002** (STRENGTHEN, LOW) — replace `NSOrderedSet` uniqueness with a
   typed `[String]` pass.
3. **weak-003** (STRENGTHEN, LOW) — tests: `as? TargetAction` + `invoke()`.
4. **Do not touch JSON parsers** (weak-004 KEEP). Unknown-at-boundary is
   correct; Codable guesses would hide provider differences.

```json
{"findings":[{"id":"weak-001","file":"Sources/StatusCore/StatuspageParser.swift","line":65,"severity":"LOW","confidence":"HIGH","recommendation":"STRENGTHEN","detail":"Dictionary(grouping:) uses groupID! after a != nil filter; replace with compactMap so the key is String, not String?.","verified":false},{"id":"weak-002","file":"Sources/StatusCore/ProviderProbe.swift","line":124,"severity":"LOW","confidence":"HIGH","recommendation":"STRENGTHEN","detail":"NSOrderedSet uniqueness then as? [String] ?? subdomains; if the bridge fails, duplicates are kept. Use a typed seen-Set pass.","verified":false},{"id":"weak-003","file":"Tests/greendotTests/MenuBuilderTests.swift","line":91,"severity":"LOW","confidence":"HIGH","recommendation":"STRENGTHEN","detail":"Test invoke helper uses representedObject as AnyObject? + NSSelectorFromString(\"invoke\"); cast to TargetAction and call invoke().","verified":false},{"id":"weak-004","file":"Sources/StatusCore/StatuspageParser.swift","line":92,"severity":"LOW","confidence":"HIGH","recommendation":"KEEP","detail":"[String: Any] from JSONSerialization in StatuspageParser/InstatusParser/StatuspalParser is the external JSON boundary; as? field reads fail closed into PageSnapshot. Do not replace with guessed Codable DTOs.","verified":false},{"id":"weak-005","file":"Sources/greendot/MenuClickOpener.swift","line":10,"severity":"LOW","confidence":"HIGH","recommendation":"KEEP","detail":"NSEvent.addLocalMonitorForEvents returns Any?; removeMonitor takes Any. AppKit token boundary.","verified":false},{"id":"weak-006","file":"Sources/greendot/MenuCommands.swift","line":41,"severity":"LOW","confidence":"HIGH","recommendation":"KEEP","detail":"NSMenuItem.representedObject is Any?; production already uses as? TargetAction and fails closed.","verified":false},{"id":"weak-007","file":"Sources/StatusCore/HTTPClient.swift","line":16,"severity":"LOW","confidence":"HIGH","recommendation":"KEEP","detail":"URLSession yields URLResponse; as? HTTPURLResponse is the HTTP boundary (non-HTTP → status 0).","verified":false},{"id":"weak-008","file":"Sources/greendot/AppDelegate.swift","line":200,"severity":"LOW","confidence":"HIGH","recommendation":"KEEP","detail":"Notification.object is Any?; UI-test hooks read as? String ?? \"\".","verified":false},{"id":"weak-009","file":"Sources/greendot/UITestDriver.swift","line":35,"severity":"LOW","confidence":"HIGH","recommendation":"KEEP","detail":"NSView tree walks use as? NSButton/NSTextField/NSScrollView; AppKit has no typed child list.","verified":false},{"id":"weak-010","file":"UITests/GreenDotUITests/GreenDotUITests.swift","line":8,"severity":"LOW","confidence":"HIGH","recommendation":"KEEP","detail":"Six XCTest IUOs assigned in setUpWithError; production has zero IUOs.","verified":false},{"id":"weak-011","file":"Sources/StatusCore/Monitor.swift","line":3,"severity":"LOW","confidence":"MEDIUM","recommendation":"REVIEW","detail":"Monitor and PageStore are @unchecked Sendable classes with mutable config; consider @MainActor (optional, larger change).","verified":false},{"id":"weak-012","file":"Sources/greendot/AppEditMenu.swift","line":27,"severity":"LOW","confidence":"HIGH","recommendation":"KEEP","detail":"Selector((\"undo:\"))/Selector((\"redo:\")) are AppKit first-responder actions; cut/copy/paste already use typed #selector(NSText.*).","verified":false}]}
```
