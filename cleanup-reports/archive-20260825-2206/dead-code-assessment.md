# Dead Code Analysis Assessment

_Assessment date: 2026-08-21. Scope: current working tree at `50df55e` (`main`). Product code under `Sources/` was read-only; this file is the only write. All machine-readable findings remain `verified: false`; the independent adversarial verification stage must run before any automated application._

## Executive Summary

- **Total issues found: 9.** Severity breakdown: **HIGH=0, MEDIUM=1, LOW=8**.
- **Confidence breakdown:** CERTAIN=4, LIKELY=4, UNCERTAIN=1.
- **Immediately removable production code:** approximately **12 physical LOC** across 4 CERTAIN findings (one unused public method, three unused imports, one unused test-double initializer parameter).
- **Dead LOC by confidence:** CERTAIN=12, LIKELY=7 (plus one unreferenced PNG asset), UNCERTAIN=0 recommended for deletion (~26 LOC of DNC-backed menu-pop infrastructure must stay until a poster is ruled out).
- **Unused files / dependencies:** no Swift source file is unreferenced. `Package.swift` declares no external packages. Makefile targets, Info.plist keys except one, and every `GREENDOT_*` env var have a consumer.
- **Top 3 priorities:**
  1. Remove `WatchedPage.isComponentEnabled(_ name: String)` (`Sources/StatusCore/Models.swift:121`). It is a public subset of the live `ComponentStatus` overload and never has a caller.
  2. Delete the four unused imports (`main.swift` `StatusCore`; `Foundation` in `Severity.swift`, `StatusMapping.swift`, `ToastPolicy.swift`).
  3. Do **not** delete `showMenu` / `popMenuOnScreen`. That path is a DistributedNotificationCenter hook, and `be69c74` just changed it.

## Research Performed

- Inventoried every type, method, and file under `Sources/StatusCore` (14 files) and `Sources/greendot` (14 files), then grepped the whole tree (Sources, Tests, UITests, Makefile, Package.swift, Info.plist, sonar-project.properties, README, design spec).
- Cross-checked dynamic surfaces before any CERTAIN label:
  - `@objc` / `#selector` / `Selector(("undo:"))` / `NSSelectorFromString("invoke")` (`AppEditMenu`, `TargetAction`, `ComponentPicker`, `PagePanelController`, tests).
  - DistributedNotificationCenter names `com.tgerighty.greendot.{showMenu,clickMenu,dumpMenu,clickIdentifier,dumpIdentifiers,setField,focusField}`.
  - Env vars `GREENDOT_CONFIG_DIR`, `GREENDOT_FIXTURE_DIR`, `GREENDOT_SKIP_LOGIN_ITEM`, `GREENDOT_SKIP_SEED`, `GREENDOT_POLL_SECONDS`, `GREENDOT_UI_TEST`, `GREENDOT_OPEN_URL_LOG`, `GREENDOT_MENU_DUMP`, `GREENDOT_ID_DUMP`.
  - Accessibility identifiers (`url-field`, `name-field`, `save-button`, `cancel-button`, `remove-page-button`, `status-page-panel`, `component-all`, `component-list`, `component-*`, menu identifiers).
- Read `Package.swift` (no external dependencies), `Makefile`, `Resources/Info.plist`, `sonar-project.properties`, `.swiftlint.yml`, `.gitignore`.
- Reconstructed `git log --oneline` from `.git/logs/HEAD` and `.git/logs/refs/heads/main`. Unique product commits on this repo, newest first:
  - `50df55e` / `be69c74` `[FIX] Do not replace the menu while popMenuOnScreen is tracking`
  - `33ffed5` `[FIX] Address code-review findings on URL open and UI-test hooks`
  - `191e5c1` / `9620e62` `[FEATURE] Open page URL from menu rows and complete UI tests`
  - `4a5f0b4` `[FIX] Rename test client ok so extras SwiftLint identifier_name is clean`
  - `b0c808d` `[FIX] Clear SwiftLint errors that would fail the extras gate`
  - `9a721e6` `[FIX] OpenAI Edit crash from released-when-closed window`
  - `889a31d` `[FIX] Crash when opening Edit for a second status page`
  - `489d128` `[FEATURE] All and group on/off for component trees`
  - `0588846` `[FEATURE] Nested status-page component groups`
  - `bd5f5b2` `[FIX] Allow copy and paste in the Add Status Page fields`
  - `0931789` `[FEATURE] Toggle components in the edit dialog`
  - `b18e16f` `[FEATURE] greendot menu-bar status monitor`
  - `fe60c54` `[PLAN] Bootstrap private macOS status-page menu bar app repo`
- The whole history is 2026-08-21. Recency was **not** used to drop CERTAIN unused-symbol findings. Recency **was** used to keep DNC / UI-test hooks below CERTAIN and off the delete list.

## Critical Findings

- None. No HIGH unused module, unused production type, or unused Package.swift dependency.

## Medium Findings

### M1 — unused public String overload of `isComponentEnabled` (CERTAIN, 3 LOC)

`Sources/StatusCore/Models.swift:121-123`:

```swift
public func isComponentEnabled(_ name: String) -> Bool {
    !disabledComponentNames.contains(name)
}
```

Repository-wide `isComponentEnabled` hits are only the two overloads plus:

- `Models.swift:131` — `isComponentEnabled(item)` (the `ComponentStatus` overload)
- `Monitor.swift:68` — `isComponentEnabled($0)` (same)

When `Monitor.toggleComponent` has no tree node it inlines `disabledComponentNames.contains(name)` instead of calling the String overload. `ComponentPicker` also uses the set directly.

The live overload (`Models.swift:125`) checks **both** `component.id` and `component.name`. The String method does not, so leaving it public is a footgun, not a useful alias.

Git: name-only helper landed with component toggles in `0931789`; the id-aware overload landed with nested groups in `0588846` / `489d128`. No later commit added a String-overload caller.

**Recommendation: REMOVE** the String overload (3 LOC). Keep `isComponentEnabled(_ component:)`.

## Low / Debatable Findings

### L1 — unused `import StatusCore` in `main.swift` (CERTAIN, 1 LOC)

`Sources/greendot/main.swift:2` imports `StatusCore` but the file only talks to AppKit (`NSApplication`, `AppDelegate`). `AppDelegate.swift` already imports `StatusCore`. SPM still links StatusCore through the executable target dependency.

**Recommendation: REMOVE** the import.

### L2 — unused `import Foundation` in three StatusCore files (CERTAIN, 3 LOC)

These files import Foundation and then use only Swift stdlib / same-module types:

| File | Line | Types actually used |
|---|---|---|
| `Sources/StatusCore/Severity.swift` | 1 | `String`, `Codable`, `Equatable`, `Sendable` |
| `Sources/StatusCore/StatusMapping.swift` | 1 | `String`, `Severity` |
| `Sources/StatusCore/ToastPolicy.swift` | 1 | `String`, `Severity`, `PageSnapshot`, `Toast` |

Sibling files (`Models.swift`, `GreyPulse.swift`, parsers, `PageStore.swift`) still need Foundation for `URL` / `Date` / `Data` / `UUID`. This is per-file unused import, not a module-level unused dependency.

SwiftLint `unused_import` is an analyzer rule and is not enabled in `.swiftlint.yml`, which is why `make lint` would not have caught these.

**Recommendation: REMOVE** the three imports.

### L3 — `MapHTTPClient` initializer `byURL:` parameter has no caller (CERTAIN, 5 LOC)

`Sources/StatusCore/HTTPClient.swift:25-32` maps `byURL: [String: (String, Int)]` into `Data` tuples. Every test constructs with `byPath:` only, or with `MapHTTPClient()` and then assigns `client.byURL[...] = (Data(...), 200)` (`ProbeAndMonitorTests.swift:50`). No call site passes the `byURL:` argument.

The `byURL` **property** is live. Only the String-to-Data init mapping is dead.

**Recommendation: REMOVE** the unused parameter and the mapping loop; keep `public var byURL` and the `byPath:` init.

### L4 — `NSUserNotificationAlertStyle` is leftover from the old notification API (LIKELY, 2 LOC)

`Resources/Info.plist:27-28` sets `NSUserNotificationAlertStyle` = `banner`. Runtime posting goes through `UNUserNotificationCenter` in `Sources/greendot/Notifier.swift:7,24`. That key belongs to the deprecated `NSUserNotificationCenter` API.

Why not CERTAIN: Apple can still read the key for Notification Center style on some macOS versions. Removing it needs a banner-style check on 13+.

**Recommendation: REVIEW**, then drop the key if banners still appear from `UNUserNotificationCenter` alone.

### L5 — `Resources/AppIcon.png` is not part of the build (LIKELY, 1 file)

`Makefile:22` copies `Resources/AppIcon.icns`. `Resources/Info.plist:13-14` names `AppIcon` (the icns, no extension). No Swift, Makefile, or plist reference to `AppIcon.png`. The PNG is the same green-dot artwork as the icns.

Why not CERTAIN: it is the obvious master for regenerating the icns. Deleting it without an icon pipeline would lose source art.

**Recommendation: REVIEW**. Keep as icon master, or add a one-line comment / Make recipe so the file is an intentional input.

### L6 — `PagePanelController` conforms to `NSWindowDelegate` with no methods (LIKELY, 3 LOC)

`Sources/greendot/PagePanelController.swift:9` declares `NSWindowDelegate`. The class implements none of the protocol methods (no `windowWillClose` / `windowShouldClose`). It still assigns `window.delegate = self` (`:47`) and clears it in `close()` (`:60`).

`closeWindow()` (`:64-66`) is **not** dead: `Tests/greendotTests/PanelLifecycleTests.swift:24` calls it to cover the `9a721e6` released-when-closed crash.

**Recommendation: REVIEW**. Dropping the empty conformance is safe if `delegate = nil` is no longer needed to break a callback. Do not remove `closeWindow()`.

### L7 — stale `Status Menu.app` ignore rules (LIKELY, 2 config lines)

`.gitignore:18` and `.swiftlint.yml:8` still exclude `Status Menu.app`. The product name is `greendot`; Makefile emits `greendot.app`. No remaining tree reference to `Status Menu`.

Likely leftover from bootstrap `fe60c54`. Harmless, not product code.

**Recommendation: REMOVE** those two ignore lines in a config cleanup. Not a source-code deletion.

### L8 — `showMenu` DNC observer has no in-repo poster (UNCERTAIN, KEEP)

`Sources/greendot/AppDelegate.swift:169-171` observes `com.tgerighty.greendot.showMenu` and calls `MenuBarController.popMenuOnScreen()` (`:38-45`). UI tests post `clickMenu`, `dumpMenu`, `clickIdentifier`, `dumpIdentifiers`, `setField`, and `focusField` — **not** `showMenu` (`UITests/GreenDotUITests/GreenDotUITests.swift`).

That observer plus `needsPop` / `presentPopMenu()` / the `flushDeferredMenuWork` pop branch is about 26 LOC with no current in-repo poster. It is still a DNC name, the comment says UI tests use it when the extra is parked off-screen, and `be69c74` (on the `50df55e` mainline) just taught `popMenuOnScreen` to defer while a menu is tracking.

**Recommendation: KEEP**. Never CERTAIN. Do not delete DNC observers, env-gated UITestDriver, or `TargetAction.invoke`.

## Dependency Assessment

| Manifest | Result |
|---|---|
| `Package.swift` | No external packages. Targets `StatusCore`, `greendot`, `StatusCoreTests`, `greendotTests` each have in-tree importers. `greendotTests` needs both `greendot` and `StatusCore`. |
| `Makefile` | `build`, `test`, `app`, `install`, `clean`, `uitest`, `lint` are all reachable. `SWIFTFLAGS` / `CONFIG` are used. |
| `Resources/Info.plist` | Live keys: bundle id, `LSUIElement`, icon, version. Only `NSUserNotificationAlertStyle` looks unused (L4). |
| `sonar-project.properties` | `sonar.sources=Sources`, `sonar.tests=Tests`, UITests/docs/app bundles excluded. No unused analyzer plugin reference in-tree. |
| System frameworks | `AppKit`, `Foundation`, `UserNotifications`, `ServiceManagement` each have a direct call site. |

## Recommendations

1. After adversarial verification, apply the four CERTAIN `REMOVE` findings as one small change: String overload, unused imports, unused `MapHTTPClient` init parameter. Re-run `swift test` and `swiftlint lint --strict`.
2. Leave every DNC name, `@objc` selector, `GREENDOT_*` env var, and accessibility identifier in place. Current UI tests not posting `showMenu` is not proof that the hook is dead.
3. Treat `AppIcon.png` and `NSUserNotificationAlertStyle` as product/asset review, not mechanical deletion.
4. Do not move `MapHTTPClient` or `DirectoryHTTPClient` out of StatusCore in this cleanup. Both have callers (tests; AppDelegate fixture path). Hosting test doubles next to `HTTPClient` is the local pattern.

## Out of Scope / Flagged for Review

- **Documented test seam, not dead:** `Aggregator.barSeverity(from:)` (`Severity.swift:12`) is called only from `Tests/StatusCoreTests/AggregatorTests.swift`. Production uses `Monitor.barSeverity()` → `Aggregator.fromSeverities` on `displaySeverity`. The design spec (`docs/superpowers/specs/2026-08-21-status-menu-design.md`) lists “Aggregator: snapshots → bar severity” as an intentional TDD seam. KEEP.
- **Test-only production wrappers that tests still call:** `PagePanelController.closeWindow()`, `URLOpener.open(_:logPath:workspace:)`, `MapHTTPClient` as a type, `MenuCommands.perform` / `dump`. KEEP.
- **Env-gated UI-test driver:** `UITestDriver`, `installUITestHooks()`, `GREENDOT_UI_TEST`, dump paths. KEEP. Dynamic.
- **ObjC / selector surfaces:** `TargetAction.invoke`, `AppEditMenu` `Selector(("undo:"))` / `redo:`, `saveTapped` / `cancelTapped` / `removeTapped`, `allClicked` / `componentClicked`, `NSMenuDelegate` methods on `MenuClickOpener`. KEEP.
- **Accessibility identifiers without a current test click:** `status-page-panel`, `remove-page-button`. They label live controls. Unused in XCTest is not unused in the UI.
- **No unused Swift file.** All 28 source files are imported, instantiated, or are SPM members of a live target.
- **`greendot.app/` on disk** is the Makefile output and is gitignored. Not a source finding.
- **Duplicate `find` / `collect` helpers** in `Monitor` and `ComponentPicker` are duplication, not dead code.

## Machine-Readable Findings

```json
{
  "findings": [
    {
      "id": "dead-001",
      "file": "Sources/StatusCore/Models.swift",
      "line": 121,
      "severity": "MEDIUM",
      "confidence": "CERTAIN",
      "recommendation": "REMOVE",
      "detail": "WatchedPage.isComponentEnabled(_ name: String) has zero call sites. Production uses the ComponentStatus overload that checks both id and name. Monitor.toggleComponent inlines disabledComponentNames.contains(name) instead. 3 LOC public footgun leftover from 0931789 after ids landed in 0588846/489d128.",
      "verified": true
    },
    {
      "id": "dead-002",
      "file": "Sources/greendot/main.swift",
      "line": 2,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "REMOVE",
      "detail": "import StatusCore is unused in main.swift; the file only wires NSApplication and AppDelegate. StatusCore is already imported by AppDelegate and listed as an executableTarget dependency.",
      "verified": true
    },
    {
      "id": "dead-003",
      "file": "Sources/StatusCore/Severity.swift",
      "line": 1,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "REMOVE",
      "detail": "Unused import Foundation in Severity.swift:1, StatusMapping.swift:1, and ToastPolicy.swift:1 (3 LOC). Those files use only Swift stdlib and same-module types. Other StatusCore files still need Foundation.",
      "verified": true
    },
    {
      "id": "dead-004",
      "file": "Sources/StatusCore/HTTPClient.swift",
      "line": 25,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "REMOVE",
      "detail": "MapHTTPClient.init(byPath:byURL:) never receives a byURL argument. Tests pass byPath or mutate the byURL property with Data tuples. Remove the unused parameter and String-to-Data mapping (~5 LOC); keep the byURL property.",
      "verified": true
    },
    {
      "id": "dead-005",
      "file": "Resources/Info.plist",
      "line": 27,
      "severity": "LOW",
      "confidence": "LIKELY",
      "recommendation": "REVIEW",
      "detail": "NSUserNotificationAlertStyle is the deprecated NSUserNotificationCenter key. Notifier posts through UNUserNotificationCenter. Confirm banner style on macOS 13+ before deleting the key.",
      "verified": false
    },
    {
      "id": "dead-006",
      "file": "Resources/AppIcon.png",
      "line": 1,
      "severity": "LOW",
      "confidence": "LIKELY",
      "recommendation": "REVIEW",
      "detail": "AppIcon.png is never copied or referenced. Makefile and Info.plist use AppIcon.icns. The PNG matches the shipped green-dot art and is likely the icns master; do not delete without an icon source-of-truth decision.",
      "verified": false
    },
    {
      "id": "dead-007",
      "file": "Sources/greendot/PagePanelController.swift",
      "line": 9,
      "severity": "LOW",
      "confidence": "LIKELY",
      "recommendation": "REVIEW",
      "detail": "PagePanelController conforms to NSWindowDelegate but implements no delegate methods. window.delegate is still set and cleared. closeWindow() is not dead (PanelLifecycleTests). Review whether the empty conformance can go.",
      "verified": false
    },
    {
      "id": "dead-008",
      "file": "Sources/greendot/AppDelegate.swift",
      "line": 169,
      "severity": "LOW",
      "confidence": "UNCERTAIN",
      "recommendation": "KEEP",
      "detail": "com.tgerighty.greendot.showMenu has no in-repo poster; UI tests use clickMenu instead. popMenuOnScreen/needsPop/presentPopMenu (~26 LOC) is DNC-backed and was changed in be69c74. Never classify DNC names CERTAIN.",
      "verified": false
    },
    {
      "id": "dead-009",
      "file": ".gitignore",
      "line": 18,
      "severity": "LOW",
      "confidence": "LIKELY",
      "recommendation": "REMOVE",
      "detail": "Status Menu.app is listed in .gitignore:18 and .swiftlint.yml:8. The product is greendot.app. Leftover from fe60c54 bootstrap naming; config noise only.",
      "verified": false
    }
  ]
}
```
