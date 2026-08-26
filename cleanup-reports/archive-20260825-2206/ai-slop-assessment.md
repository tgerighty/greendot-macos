# AI Slop Assessment

Scope: `Sources/` (product). Tests and UITests were read only to see whether a helper is a real seam. The analysis below did not change product code.

## Apply status (2026-08-21)

Branch: `cleanup/ai-slop`
Baseline: `50df55e43f489d4e1daf701b8a08522b0c23ce42`
Apply commit: `fa9273c2bd91a0e561a31addb23450229182d12c`

| ID | Disposition |
|---|---|
| slop-001 | APPLIED |
| slop-002 | APPLIED |
| slop-003 | APPLIED |
| slop-004 | SKIPPED |
| slop-005 | DEFERRED (`Models.swift` outside allowlist) |
| slop-006 | DEFERRED (`Monitor.swift` outside allowlist) |
| slop-007 | SKIPPED |

Applied **3/3** of the apply list (**3/7** findings). Logs: `ai-slop-apply-log.md`, `ai-slop-deferred.md`. Post-edit `swift test` (58 passed) and `swiftlint lint --strict` (0 violations).

Comments that say WHY were not flagged: AppKit constraints, the Add/Edit SIGSEGV, and the grey-pulse / bar-colour rules. TODOs that name real work were not found.

## Executive Summary
- Total issues found: 7
- Severity breakdown: HIGH=0, MEDIUM=2, LOW=5
- Category breakdown: COMMENT-SLOP=0, STUB=1, LARP=5, DEAD-COMMENT=0, OVER-DOCUMENTED=0, COMMENTED-OUT-CODE=0, WRAPPER-LARP=1
- Top 3 priorities
  1. Stop the fake `menu.title` reads in `MenuClickOpener` (three NSMenuDelegate methods).
  2. Remove unused `WatchedPage.isComponentEnabled(_ name:)` — it checks only the name, not id.
  3. Drop redundant `_ =` on `@discardableResult` calls in `AppDelegate`.
- Estimated impact: about 12 lines in 7 files. No runtime change if the keep-alive `_ = previous` and `alert.runModal()` lines stay.

The comment surface is small and mostly load-bearing. The slop is unused-value silencing, one no-op default, and two one-line type wrappers.

## Critical Findings

None.

## Medium Findings

### slop-001 — Fake use of `menu.title` (MEDIUM, CERTAIN, REMOVE)

`MenuClickOpener` never reads the menu. Each NSMenuDelegate method still does `_ = menu.title`:

```26:50:Sources/greendot/MenuClickOpener.swift
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        highlighted = item
        _ = menu.title
    }

    func menuWillOpen(_ menu: NSMenu) {
        ...
        _ = menu.title
    }

    func menuDidClose(_ menu: NSMenu) {
        ...
        _ = menu.title
    }
```

`.title` is not an AppKit constraint. `applicationDidFinishLaunching(_ notification:)` leaves its unused parameter alone, so this is not a project-wide unused-parameter rule. Use `_` in the parameter list (`_ _: NSMenu`) or ignore the parameter.

### slop-005 — Unused name-only enable check (MEDIUM, CERTAIN, REMOVE)

```121:127:Sources/StatusCore/Models.swift
    public func isComponentEnabled(_ name: String) -> Bool {
        !disabledComponentNames.contains(name)
    }

    public func isComponentEnabled(_ component: ComponentStatus) -> Bool {
        !disabledComponentNames.contains(component.id) && !disabledComponentNames.contains(component.name)
    }
```

Nothing calls the `String` overload. The component overload is the one `filterEnabled` and `Monitor.toggleComponent` use. The name-only method does not look at `id`, so a later caller would miss disables keyed by component id (`g1`, `c1`, …).

## Low / Debatable Findings

### slop-002 — `_ = sender` in `allClicked` (LOW, CERTAIN, REMOVE)

```98:105:Sources/greendot/ComponentPicker.swift
    @objc private func allClicked(_ sender: NSButton) {
        ...
        onSetAll(!allOn)
        _ = sender
    }
```

`componentClicked` uses `sender`. `allClicked` does not. The `@objc` selector can keep an unnamed parameter.

### slop-003 — `_ =` on methods that already discard their result (LOW, CERTAIN, REMOVE)

`LaunchAtLogin.toggle`, `MenuBarController.performMenuPath`, and `UITestDriver.clickIdentifier` / `setField` / `focusField` are `@discardableResult`. `AppDelegate` still writes `_ =`:

- `Sources/greendot/AppDelegate.swift:106` — `_ = LaunchAtLogin.toggle()`
- `:173` — `_ = self?.menuBar?.performMenuPath(path)`
- `:179` — `_ = UITestDriver.clickIdentifier(identifier)`
- `:187` — `_ = UITestDriver.setField(...)`
- `:190` — `_ = UITestDriver.focusField(...)`

Do not touch `_ = alert.runModal()` (`:132`) or `_ = previous` (`:160`). `runModal()` is not discardable. `previous` is the keep-alive for the SIGSEGV comment above it.

### slop-004 — No-op picker callbacks (LOW, LIKELY, REVIEW)

```27:31:Sources/greendot/PagePanelController.swift
            self.picker = ComponentPicker(
                page: page,
                onToggleComponent: onToggleComponent ?? { _ in },
                onSetAll: onSetAll ?? { _ in }
            )
```

Edit in the app always passes real closures. The empty `{ _ in }` defaults let tests construct a panel with only `onSave`. They also hide a missing callback in production. Optional closures on `ComponentPicker` would make the hole visible.

### slop-006 — No-op copy of `isUnreachable` (LOW, CERTAIN, REMOVE)

```136:141:Sources/StatusCore/Monitor.swift
                current: {
                    var copy = snapshot
                    copy.overall = config.pages[index].displaySeverity
                    copy.isUnreachable = snapshot.isUnreachable
                    return copy
                }(),
```

`copy` starts as `snapshot`, so the `isUnreachable` assignment does nothing. Keep the `overall` write; it is the value `ToastPolicy` compares.

### slop-007 — One-line type wrappers (LOW, POSSIBLE, INLINE)

```34:39:Sources/greendot/UITestDriver.swift
    private static func findButton(_ identifier: String) -> NSButton? {
        find(identifier) as? NSButton
    }

    private static func findField(_ identifier: String) -> NSTextField? {
        find(identifier) as? NSTextField
    }
```

Each wrapper is one cast. Inlining at the three call sites (`clickIdentifier`, `setField`, `focusField`) is enough. Keep `find(_:)` / `find(_:in:)`; those walks are real.

## Heat Map

| File | Findings | Dominant category |
|---|---:|---|
| `Sources/greendot/MenuClickOpener.swift` | 1 (3 sites) | LARP |
| `Sources/greendot/AppDelegate.swift` | 1 (5 sites) | LARP |
| `Sources/StatusCore/Models.swift` | 1 | LARP |
| `Sources/greendot/ComponentPicker.swift` | 1 | LARP |
| `Sources/greendot/PagePanelController.swift` | 1 | STUB |
| `Sources/StatusCore/Monitor.swift` | 1 | LARP |
| `Sources/greendot/UITestDriver.swift` | 1 | WRAPPER-LARP |

## Recommendations

1. **Do first:** delete the three `_ = menu.title` lines. If the compiler warns, name the unused parameter `_`.
2. **Do second:** delete `isComponentEnabled(_ name: String)`. Keep the `ComponentStatus` overload.
3. **Do third:** drop `_ =` on `@discardableResult` calls in `AppDelegate`. Leave the SIGSEGV keep-alive and `runModal()`.
4. **Do if touching the picker:** make `onToggleComponent` / `onSetAll` optional, or keep the no-ops only if tests must omit them.
5. **Do not:** strip WHY comments on AppKit, pulse colour, or the deferred panel release.

## Out of Scope / Flagged for Review

These look like slop at a glance and should stay.

| Item | Why keep |
|---|---|
| `AppDelegate.swift:157-160` (`_ = previous` + SIGSEGV comment) | Crash fix. The assignment keeps the old panel alive until after the menu action returns. |
| `AppDelegate.swift:132` (`_ = alert.runModal()`) | `runModal()` returns a response. This is a real ignore, not a fake use. |
| `URLOpener.swift:33` (`_ = try? handle.seekToEnd()`) | `seekToEnd()` returns a file offset. |
| `PagePanelController.closeWindow()` + “Same path as the window close button” | Test seam for `NSWindow.close` vs `close()` / `orderOut` (the crash path). |
| `AppEditMenu`, `TargetAction`, `MenuClickOpener` header, `clickIsOnMenuRow` | AppKit constraints (accessory Edit menu, retained target, submenu click, titled windows). |
| `MenuBarController.popMenuOnScreen` | UI tests need an on-screen pop when the extra is off-screen. |
| `DirectoryHTTPClient` header | Why fixtures exist (no HTTP server in XCTest). |
| `GreyPulse` / `Aggregator.barSeverity` comments | Colour rules that the `if` chain does not state. |
| `URLOpener.open(_:)` → injectable `open` | Production composition root and UI-test log path. |
| `MenuBarController.performMenuPath` / `dumpMenu` | They bind `menuProvider`; not empty wrappers. |
| `LaunchAtLogin.enable` vs `toggle` | First-run register vs menu toggle. |
| `Aggregator.barSeverity` / `fromSeverities` / `severity(from:)` | Named ranking, not copy-paste wrappers. |
| Tests: `_ = NSApplication.shared`, `_ = target.perform`, `_ = try await ProviderProbe.probe` | AppKit bootstrap, `perform` result, and expected-throw probes. |
| Commented-out code / TODO / FIXME | None in `Sources/`. |

## Machine-Readable Findings

```json
{"findings": [
  {"id": "slop-001", "file": "Sources/greendot/MenuClickOpener.swift", "line": 28, "severity": "MEDIUM",
   "confidence": "CERTAIN", "recommendation": "REMOVE",
   "detail": "Three NSMenuDelegate methods do _ = menu.title only to silence the unused menu parameter.", "verified": true},
  {"id": "slop-002", "file": "Sources/greendot/ComponentPicker.swift", "line": 104, "severity": "LOW",
   "confidence": "CERTAIN", "recommendation": "REMOVE",
   "detail": "allClicked ends with _ = sender; the button is unused.", "verified": true},
  {"id": "slop-003", "file": "Sources/greendot/AppDelegate.swift", "line": 106, "severity": "LOW",
   "confidence": "CERTAIN", "recommendation": "REMOVE",
   "detail": "Redundant _ = on @discardableResult toggle/performMenuPath/clickIdentifier/setField/focusField (lines 106, 173, 179, 187, 190). Do not touch runModal or previous.", "verified": true},
  {"id": "slop-004", "file": "Sources/greendot/PagePanelController.swift", "line": 29, "severity": "LOW",
   "confidence": "LIKELY", "recommendation": "REVIEW",
   "detail": "ComponentPicker gets onToggleComponent/onSetAll ?? { _ in } no-ops; app edit always passes real closures.", "verified": false},
  {"id": "slop-005", "file": "Sources/StatusCore/Models.swift", "line": 121, "severity": "MEDIUM",
   "confidence": "CERTAIN", "recommendation": "REMOVE",
   "detail": "isComponentEnabled(_ name: String) has no callers and ignores component id.", "verified": true},
  {"id": "slop-006", "file": "Sources/StatusCore/Monitor.swift", "line": 139, "severity": "LOW",
   "confidence": "CERTAIN", "recommendation": "REMOVE",
   "detail": "copy.isUnreachable = snapshot.isUnreachable is a no-op after var copy = snapshot.", "verified": false},
  {"id": "slop-007", "file": "Sources/greendot/UITestDriver.swift", "line": 34, "severity": "LOW",
   "confidence": "POSSIBLE", "recommendation": "INLINE",
   "detail": "findButton and findField are one-line as? wrappers around find(_:).", "verified": false}
]}
```
