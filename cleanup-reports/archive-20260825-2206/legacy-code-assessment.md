# Legacy Code Assessment

## Executive Summary

- Total issues found: 8
- Severity breakdown: HIGH=0, MEDIUM=0, LOW=8
- Classification breakdown: SAFE-TO-REMOVE=5, ACTIVE-DEPRECATED=1, NEEDS-VERIFICATION=2, KEEP=0
- Top priorities:
  1. Delete the leftover `Status Menu.app` entries from `.swiftlint.yml` and `.gitignore`. The product bundle is `greendot.app`; no `Status Menu.app` tree exists in this checkout.
  2. Replace deprecated `NSImage.lockFocus` / `unlockFocus` in `StatusDot` with `NSImage(size:flipped:drawingHandler:)`.
  3. Remove the unused `WatchedPage.isComponentEnabled(_ name:)` overload and the stale UI-test “HTTP server” sentence in the design spec.
- Estimated impact: 6 source/config files plus 1 spec file. About 8–12 LOC of product code and a few ignore/lint lines can go now. The drawing change is a replacement, not a deletion.
- Estimated possible LOC reduction: approximately 10 LOC if the SAFE-TO-REMOVE items are applied. There is no large compatibility facade to retire.
- This is a brand-new app (initial commit 2026-08-21). There are no TODO/FIXME markers in product Swift, no `status-app` leftover string, and no concluded A/B flag. The GREENDOT_* environment switches are live UI-test seams, not dormant product flags.

## Critical Findings

No HIGH-severity legacy findings were identified. In particular, no source item met a `SAFE-TO-REMOVE` standard that also implied a large superseded implementation.

## Medium Findings

None. The leftover product name and deprecated drawing API are small and local.

## Low / Debatable Findings

### legacy-001 — `.swiftlint.yml` and `.gitignore` still name `Status Menu.app`

- Location: `.swiftlint.yml:8`, `.gitignore:18`
- Classification: **SAFE-TO-REMOVE**
- Evidence: SwiftLint `excluded` lists `.build`, `UITests`, `greendot.app`, and `Status Menu.app`. `.gitignore` ignores both `greendot.app` and `Status Menu.app`. `Makefile` builds `APP := greendot.app`. `Resources/Info.plist` uses bundle name/id `greendot` / `com.tgerighty.greendot`. A read of `Status Menu.app/Contents/Info.plist` fails; that bundle is not in the tree. Repository search for `status-app` returns no hits. Git history starts as a “status-page menu bar app” and then names the product greendot; the old bundle name remains only in ignore/lint lists.
- Risk: leaving a dead exclude hides a future folder of that name from lint, and it documents a product name that is no longer used.
- Recommendation: delete the `Status Menu.app` lines. Keep the `greendot.app` ignores.

### legacy-002 — Design spec filename still uses the pre-greendot “status-menu” name

- Location: `docs/superpowers/specs/2026-08-21-status-menu-design.md:1`
- Classification: **NEEDS-VERIFICATION**
- Evidence: the spec body names the product greendot and bundle `com.tgerighty.greendot`. The file name is `2026-08-21-status-menu-design.md`. No other in-repo path references that filename. External planner/agent links to `docs/superpowers/specs/` were not checked.
- Risk: a rename without a search of agent/planner references would break those links. Keeping the old name preserves a second product identity next to greendot.
- Recommendation: grep agent docs and chat history for the filename; rename to a greendot-prefixed spec only if nothing external points at it.

### legacy-003 — Spec still says UI tests start a local HTTP server

- Location: `docs/superpowers/specs/2026-08-21-status-menu-design.md:124`
- Classification: **SAFE-TO-REMOVE**
- Evidence: the spec says ``make uitest`` “starts a local fixture HTTP server”. `Makefile` `uitest` builds the app, waits for the process to exit, generates the UI-test xcodeproj, and runs `xcodebuild test`. There is no server target. `DirectoryHTTPClient` is documented as the fixture so UI tests “do not need a real HTTP server in the XCTest runner process”. `AppDelegate` selects that client when `GREENDOT_FIXTURE_DIR` is set; `GreenDotUITests` writes JSON files under that directory.
- Risk: a later change could re-introduce a server to match the spec, duplicating the fixture client.
- Recommendation: replace the sentence with the DirectoryHTTPClient / `GREENDOT_FIXTURE_DIR` path.

### legacy-004 — `NSUserNotificationAlertStyle` remains in Info.plist after the UserNotifications cutover

- Location: `Resources/Info.plist:27-28`
- Classification: **SAFE-TO-REMOVE**
- Evidence: `Notifier.swift` posts through `UNUserNotificationCenter`. The plist still sets `NSUserNotificationAlertStyle` to `banner`, which belonged to the deprecated `NSUserNotification` API. `Notifier` never reads the key. For `UNNotification`, that plist value does not select banner vs alert.
- Risk: none for current posting. Removing it does not change the UserNotifications permission flow.
- Recommendation: delete the key/value from `Resources/Info.plist` (the built `greendot.app` copy is generated).

### legacy-005 — `StatusDot` still draws with deprecated `NSImage.lockFocus`

- Location: `Sources/greendot/StatusDot.swift:7-10`
- Classification: **ACTIVE-DEPRECATED**
- Evidence: `lockFocus()` / `unlockFocus()` are deprecated AppKit symbols. Apple marks them incompatible with resolution-independent drawing. The current replacement is `NSImage(size:flipped:drawingHandler:)`. This is the live icon renderer, not a second unused path.
- Risk: the calls still work on macOS 13+, but a future SDK can remove them. A naive replacement must keep 1x/2x menu-bar sharpness.
- Recommendation: rewrite `StatusDot.image` with a drawing handler; keep the same oval and system colours. Do not delete the type.

### legacy-006 — String `isComponentEnabled` overload has no callers

- Location: `Sources/StatusCore/Models.swift:121-123`
- Classification: **SAFE-TO-REMOVE**
- Evidence: `isComponentEnabled(_ name: String)` only appears at its definition. Production uses `isComponentEnabled(_ component: ComponentStatus)`, which checks both `id` and `name`. `Monitor.toggleComponent` inlines a string `contains` when no tree node is found, rather than calling the string overload. This looks like a leftover from the name-only toggle, before component ids existed.
- Risk: none in-repo. The method is public on a library type, but this repo is the only client.
- Recommendation: delete the string overload. Keep the component overload and the id-or-name disable set.

### legacy-007 — Comments still say “menu-bar extra”

- Location: `Sources/greendot/MenuBarController.swift:37`, `UITests/GreenDotUITests/GreenDotUITests.swift:5`
- Classification: **SAFE-TO-REMOVE**
- Evidence: the chosen stack is AppKit `NSStatusItem`. The spec records SwiftUI `MenuBarExtra` as rejected. `MenuBarController.popMenuOnScreen` comments that a “menu-bar manager parks the extra off-screen”. UI tests mention “off-screen extra frames”. No `MenuBarExtra` type exists in Sources.
- Risk: comments only. They imply a SwiftUI extra that is not in the binary.
- Recommendation: say “status item” / “menu-bar item” instead of “extra”.

### legacy-008 — “Old config” test does not load a pre-`disabledComponentNames` page

- Location: `Tests/StatusCoreTests/ComponentToggleTests.swift:162-173`
- Classification: **NEEDS-VERIFICATION**
- Evidence: `WatchedPage` decodes `disabledComponentNames` with `decodeIfPresent` defaulting to `[]`, which is a real missing-key compatibility path. The test named `testOldConfigWithoutDisabledNamesStillLoads` writes `{"version":1,"pages":[],"didSetLaunchAtLogin":false}` and only asserts `pages.isEmpty`. It never omits `disabledComponentNames` on a page object. `AppConfig.currentVersion` is still 1; there is no v0 migrator.
- Risk: renaming or deleting the test without adding a page that lacks the key would leave the decoder default untested. Treating the test as proof of an old on-disk schema overstates what shipped (the app is new; version is 1).
- Recommendation: either rename it to an empty-config load test, or give it a page JSON that omits `disabledComponentNames` and `notificationsEnabled`. Do not add a version-0 migrator unless a real old file exists.

## Feature Flag Inventory

| Flag / switch | Default | Checked-in use | Assessment |
|---|---|---|---|
| `GREENDOT_CONFIG_DIR` | unset → `~/Library/Application Support/greendot` | UI tests set a scratch dir; `PageStore.defaultDirectory` reads it | **KEEP** — current test/prod split |
| `GREENDOT_FIXTURE_DIR` | unset → `URLSessionHTTPClient` | UI tests set it; `AppDelegate` then uses `DirectoryHTTPClient` | **KEEP** — current fixture seam |
| `GREENDOT_SKIP_LOGIN_ITEM` | unset → register on first run | UI tests set `1` | **KEEP** |
| `GREENDOT_SKIP_SEED` | unset → seed OpenAI if empty | UI tests set `1` | **KEEP** |
| `GREENDOT_POLL_SECONDS` | `60` | UI tests set `3600` | **KEEP** |
| `GREENDOT_UI_TEST` | unset → no distributed-notification hooks | UI tests set `1`; `installUITestHooks` requires it plus a config dir | **KEEP** |
| `GREENDOT_OPEN_URL_LOG` | unset → `NSWorkspace.shared.open` | UI tests set a log path; `URLOpener` then records instead of opening | **KEEP** |
| `GREENDOT_MENU_DUMP` / `GREENDOT_ID_DUMP` | unset → no dump | UI tests set paths under the config dir | **KEEP** |

No always-on/off product flag or unused env toggle was found. `swiftlint` disables the `todo` rule; there are no TODO/FIXME comments in `Sources` or `Tests` to hide.

## Dual-Path Inventory

| Current path | Other path | Status |
|---|---|---|
| Bundle `greendot.app` | Ignore/lint entry `Status Menu.app` | Remove the leftover name (`legacy-001`) |
| `URLSessionHTTPClient` in normal launch | `DirectoryHTTPClient` when `GREENDOT_FIXTURE_DIR` is set | Keep; UI-test fixture, not a superseded client |
| `MapHTTPClient` in `StatusCore` | Same type used only from `StatusCoreTests` | Keep as the unit-test HTTP double; not a compatibility facade |
| `UNUserNotificationCenter` | Plist `NSUserNotificationAlertStyle` | Remove the plist key (`legacy-004`) |
| `NSStatusItem` + `MenuClickOpener` | Spec-rejected SwiftUI `MenuBarExtra`; comments still say “extra” | Keep the AppKit path; edit comments (`legacy-007`) |
| Statuspal `current_status_type` | Fallback `status_page.current_incident_type` | Keep; external JSON shapes |
| Statuspage incident `name` / `shortlink` | Fallback `title` / `url` | Keep; external JSON shapes |
| Disable set keyed by component `id` | Also stores/matches `name` | Keep while snapshots can lack stable ids (`id` defaults to `name`) |
| `snapshot?.url` when opening a page | Fallback `page.url` | Keep; probe may canonicalise the public URL |
| Spec: UI tests start an HTTP server | Code: file-backed `DirectoryHTTPClient` | Spec is stale (`legacy-003`) |
| `WatchedPage.isComponentEnabled(ComponentStatus)` | Unused `isComponentEnabled(String)` | Delete the string overload (`legacy-006`) |
| Config `decodeIfPresent` defaults for new keys | No version-0 file format | Keep the defaults; the “old config” test does not prove a v0 schema (`legacy-008`) |

`statuspal.io` vs `statuspal.eu` probe hosts are current provider endpoints, not in-repo generations.

## Recommendations

1. Apply the name cleanup first: drop `Status Menu.app` from `.swiftlint.yml` and `.gitignore`. Search confirmed no `status-app` leftover and no `Status Menu.app` bundle.
2. Replace `lockFocus` in `StatusDot` in a single change with a drawing-handler image. That is the only ACTIVE-DEPRECATED runtime API.
3. Delete `isComponentEnabled(_ name:)` and the stale HTTP-server sentence. Optionally rewrite the two “extra” comments.
4. Before renaming the design spec, confirm no planner/agent path depends on `2026-08-21-status-menu-design.md`.
5. Do not remove GREENDOT_* switches, `DirectoryHTTPClient`, `MapHTTPClient`, or provider JSON fallbacks. Those are live seams or external contracts.
6. Do not invent a config v0 migrator. `AppConfig.currentVersion` is 1 and this product is new.

## Out of Scope / Flagged for Review

- `status-app` as a token does not appear in this repository. Closest leftovers: `Status Menu.app` in ignore/lint, and the `status-menu-design.md` filename.
- `greendot.app/` on disk is a built artifact (also gitignored). It was not treated as product source.
- `UITests/GreenDotUITests.xcodeproj` is generated by `xcodegen` and gitignored; SwiftLint already excludes `UITests`.
- `MapHTTPClient` lives in `Sources/StatusCore` rather than the test target. That is a test double placement choice, not a superseded production client. Moving it is optional hygiene, not legacy removal.
- HTML status scraping is listed as out of v1 in the spec and is not implemented. Statuspal HTML is only used to find a subdomain. That is current probe behaviour, not a leftover scraper.
- `AppEditMenu` “Quit greendot” and the status-item “Quit greendot” are both required (application menu vs menu-bar menu).
- External/operator scripts outside this repository were not searched. The unused public `isComponentEnabled(String)` assumption is in-repo only.
- Apple SDK deprecation of `lockFocus` was confirmed from current AppKit docs; this report’s JSON `verified` flags remain false per assessment rules.

## Machine-Readable Findings

```json
{
  "findings": [
    {
      "id": "legacy-001",
      "file": ".swiftlint.yml",
      "line": 8,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "REMOVE",
      "detail": "SwiftLint and gitignore still exclude Status Menu.app after the product bundle became greendot.app; that old bundle is not in the tree.",
      "verified": true
    },
    {
      "id": "legacy-002",
      "file": "docs/superpowers/specs/2026-08-21-status-menu-design.md",
      "line": 1,
      "severity": "LOW",
      "confidence": "LIKELY",
      "recommendation": "REVIEW",
      "detail": "The design spec body names greendot but the filename still uses the pre-rename status-menu title; external references were not checked.",
      "verified": false
    },
    {
      "id": "legacy-003",
      "file": "docs/superpowers/specs/2026-08-21-status-menu-design.md",
      "line": 124,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "REMOVE",
      "detail": "The spec says make uitest starts a local fixture HTTP server, but the Makefile and DirectoryHTTPClient path never start a server.",
      "verified": true
    },
    {
      "id": "legacy-004",
      "file": "Resources/Info.plist",
      "line": 27,
      "severity": "LOW",
      "confidence": "LIKELY",
      "recommendation": "REMOVE",
      "detail": "NSUserNotificationAlertStyle remains in Info.plist although Notifier posts only through UNUserNotificationCenter.",
      "verified": false
    },
    {
      "id": "legacy-005",
      "file": "Sources/greendot/StatusDot.swift",
      "line": 7,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "MIGRATE",
      "detail": "StatusDot still draws the menu-bar icon with deprecated NSImage.lockFocus/unlockFocus instead of a drawing handler.",
      "verified": true
    },
    {
      "id": "legacy-006",
      "file": "Sources/StatusCore/Models.swift",
      "line": 121,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "REMOVE",
      "detail": "WatchedPage.isComponentEnabled(_ name: String) has no in-repo callers after the id-and-name ComponentStatus overload became the live path.",
      "verified": true
    },
    {
      "id": "legacy-007",
      "file": "Sources/greendot/MenuBarController.swift",
      "line": 37,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "REMOVE",
      "detail": "Comments still describe a menu-bar extra although MenuBarExtra was rejected and the implementation is NSStatusItem.",
      "verified": false
    },
    {
      "id": "legacy-008",
      "file": "Tests/StatusCoreTests/ComponentToggleTests.swift",
      "line": 162,
      "severity": "LOW",
      "confidence": "LIKELY",
      "recommendation": "REVIEW",
      "detail": "testOldConfigWithoutDisabledNamesStillLoads loads an empty v1 config and does not prove missing disabledComponentNames on a watched page.",
      "verified": false
    }
  ]
}
```
