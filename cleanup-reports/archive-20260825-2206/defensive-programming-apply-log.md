# Defensive Programming Apply Log

Date: 2026-08-21
Branch: `cleanup/defensive-programming`
Base: `00b9d00bd5afa562e86198a402d97ac01b9b27fb` (`cleanup/apply`, phase 2 merged)

Applied **2/2** verified `ERROR-HIDING` items (`def-001`, `def-003`).
Also applied the `def-002` skip-seed rule that belongs to `def-001`.
Skipped all LEGITIMATE items and all unverified items. See `defensive-programming-deferred.md`.

## Result

| Item | Verdict | Commit |
|---|---|---|
| def-001 | APPLIED | `8fd764ac20da474000d0e1738e45d9922c26dda6` |
| def-002 (skip seed after failed load) | APPLIED as part of def-001 | `8fd764ac20da474000d0e1738e45d9922c26dda6` |
| def-002 (alert on seed probe/save) | SKIPPED (`verified: false`) | — |
| def-003 | APPLIED | `8fd764ac20da474000d0e1738e45d9922c26dda6` |
| def-004 | SKIPPED (`verified: false`) | — |
| def-005 … def-010 | SKIPPED (unverified NEEDS-REFACTOR / UNNECESSARY) | — |
| def-011 … def-025 | SKIPPED (LEGITIMATE) | — |

No revert. No files outside the allowlist.

## Commits

| SHA | Message |
|---|---|
| `f7d513d5a5a29080a5fe5441353733681504c26c` | `[REFACTOR] Lock store load and save error paths before surfacing them` |
| `8fd764ac20da474000d0e1738e45d9922c26dda6` | `[FIX] Surface monitor load and menu store errors with NSAlert` |

HEAD: `8fd764ac20da474000d0e1738e45d9922c26dda6`

## TDD

### RED

Baseline at `00b9d00`: `swift test` → **76 passed**. `swiftlint lint --strict` → **0 violations in 38 files**.

Added store and monitor error-path tests in `Tests/StatusCoreTests/ProbeAndMonitorTests.swift`:

- `testPageStoreLoadMissingFileReturnsEmptyConfigAndDoesNotWrite` — missing `config.json` returns empty `AppConfig` and does not write the file
- `testPageStoreLoadCorruptJSONThrows` — corrupt JSON throws `StoreError.corrupt`
- `testPageStoreLoadUnsupportedVersionThrows` — version 99 throws `StoreError.corrupt`
- `testMonitorLoadThrowsOnCorruptStoreAndLeavesPagesEmpty` — `Monitor.load` throws and leaves pages empty
- `testMonitorMutationsThrowWhenStoreCannotSave` — `remove`, `toggleNotifications`, `toggleComponent`, and `setAllComponents` throw when `store.save` cannot write

`swift test`: **81 passed**. SwiftLint clean. Commit `f7d513d`.

Then added AppDelegate tests in `Tests/greendotTests/PanelLifecycleTests.swift`. Compile failed: `AppDelegate` had no `presentError`, `loadMonitor`, `performStoreChange`, or `shouldSeedOpenAI`.

### GREEN

Wired `Sources/greendot/AppDelegate.swift`:

- **def-001** — `loadMonitor` catches `Monitor.load`, calls `presentError` (`NSAlert(error:)`), and returns false. Seed runs only when load succeeded, pages are empty, and `GREENDOT_SKIP_SEED` is unset. Missing file still succeeds and can seed. First-run launch-at-login save also waits for a successful load so it cannot overwrite a corrupt `config.json`.
- **def-003** — `performStoreChange` replaces `try?` on menu/panel `remove`, `toggleNotifications`, `toggleComponent`, and `setAllComponents`. Save errors show `NSAlert`. Rebuild runs only after a successful save. Add/edit uses the same `presentError` seam.
- Tests replace `presentError` with a callback. Unit tests do not show a modal.

`swift test`: **86 passed**. `swiftlint lint --strict`: **0 violations in 38 files**.

Commit `8fd764a`.

`PageStore.swift` and `Monitor.swift` did not change. They already throw. `ComponentToggleTests.swift` did not change. Save-failure coverage lives in `ProbeAndMonitorTests` to stay under SwiftLint `type_body_length`.

## Files touched (allowlist)

- `Sources/greendot/AppDelegate.swift`
- `Tests/StatusCoreTests/ProbeAndMonitorTests.swift`
- `Tests/greendotTests/PanelLifecycleTests.swift`

Not changed: `Sources/StatusCore/Monitor.swift`, `Sources/StatusCore/PageStore.swift`, `Tests/StatusCoreTests/ComponentToggleTests.swift`.

`git diff --name-only 00b9d00..HEAD` lists only the three files above.

## Test status

GREEN. `swift test` 86/86 pass. `swiftlint lint --strict` clean.

No `try? monitor.load()`. Menu and panel mutations do not use `try?`. Remaining product `try?` in `AppDelegate` are seed `add` (`def-002`, unverified) and UI-test dump write (`def-020`, LEGITIMATE).
