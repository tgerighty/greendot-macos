# AI Slop Removal — Apply Log

Date: 2026-08-21
Worktree: `/Users/terry.gerighty/coding/greendot.ai-slop`
Branch: `cleanup/ai-slop`
Baseline HEAD: `50df55e43f489d4e1daf701b8a08522b0c23ce42`
Apply commit: `fa9273c2bd91a0e561a31addb23450229182d12c`

Applied 3/3 of the apply list. Findings in the assessment: 7. Deferred: 2. Skipped: 2.

Allowlist (only these files were writable):

- `Sources/greendot/MenuClickOpener.swift`
- `Sources/greendot/ComponentPicker.swift`
- `Sources/greendot/AppDelegate.swift`
- `Tests/greendotTests/MenuBuilderTests.swift` (no change)
- `Tests/greendotTests/PanelLifecycleTests.swift` (no change)

Crash-fix comments in `AppDelegate.openPanel` and `MenuClickOpener` were not changed. `_ = previous` and `_ = alert.runModal()` were not changed.

## slop-001

- **File:** `Sources/greendot/MenuClickOpener.swift`
- **Line:** 26–50 (three NSMenuDelegate methods)
- **Recommendation:** REMOVE (verified: true)
- **Change:** Removed `_ = menu.title` from `menu(_:willHighlight:)`, `menuWillOpen(_:)`, and `menuDidClose(_:)`. Named the unused protocol parameter `_` so click behaviour is unchanged.

### Verification

- Baseline `swift test` — 58 passed
- Post-edit `swift test` — 58 passed
- Post-edit `swiftlint lint --strict` — 0 violations

### Result

Applied cleanly. Click path (`handleClick`, `clickIsOnMenuRow`, `TargetAction.invoke`) was not changed.

## slop-002

- **File:** `Sources/greendot/ComponentPicker.swift`
- **Line:** 98
- **Recommendation:** REMOVE (verified: true)
- **Change:** Removed `_ = sender` from `allClicked`. The `@objc` selector still uses an unnamed parameter (`allClicked(_:)`).

### Verification

- Baseline `swift test` — 58 passed (includes `PanelLifecycleTests` All/component clicks)
- Post-edit `swift test` — 58 passed
- Post-edit `swiftlint lint --strict` — 0 violations

### Result

Applied cleanly.

## slop-003

- **File:** `Sources/greendot/AppDelegate.swift`
- **Lines:** 106, 173, 179, 187, 190
- **Recommendation:** REMOVE (verified: true)
- **Change:** Removed redundant `_ =` on `@discardableResult` calls: `LaunchAtLogin.toggle()`, `performMenuPath`, `clickIdentifier`, `setField`, `focusField`.

### Kept

- `_ = alert.runModal()` (line 132)
- `_ = previous` and the SIGSEGV comment above it (lines 157–160)

### Verification

- Baseline `swift test` — 58 passed
- Post-edit `swift test` — 58 passed
- Post-edit `swiftlint lint --strict` — 0 violations

### Result

Applied cleanly. No other files touched.
