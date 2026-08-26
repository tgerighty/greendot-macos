# Independent defensive-programming review

## Verdict

REQUEST_CHANGES

## Suspected behavior changes

- **Corrupt `config.json` is still replaced on launch.** `loadMonitor` shows an alert and skips seed and `enableLaunchAtLoginOnFirstRun`, but `applicationDidFinishLaunching` always starts `pollAndRefresh()`. `Monitor.pollAll()` ends with `try? store.save(config)`. After a failed load, `config` is still the empty `AppConfig()` from `Monitor.init`, so that save writes a valid empty file over the corrupt one. `testLoadMonitorPresentsCorruptStoreErrorAndLeavesFile` only calls `loadMonitor` and never reaches this Task/timer path. vs `50df55e` the user still loses pages; they now get an alert and an empty list instead of a silent OpenAI seed.
- **`StoreError` has no `LocalizedError` text.** `ProbeError` and `ParserError` do. `NSAlert(error:)` for `.corrupt` (and a rethrown Cocoa I/O error) is untested as UI. Tests only store the `Error` value. The user can see a generic `StatusCore.StoreError error 0` dialog, then an empty menu after the poll save.
- **Failed menu/panel store mutations do not roll back memory.** `Monitor.remove` / `toggleNotifications` / `toggleComponent` / `setAllComponents` still change `config` and then `try store.save`. `performStoreChange` skips `rebuild()` on throw (intended), but in-memory state stays mutated. `ComponentPicker` already flips local checkboxes before `onToggleComponent`. A second click can invert memory again. Tests assert that `presentError` runs, not menu/checkbox/disk agreement.

## Notes

- **StatusDot:** `lockFocus` → `NSImage(size:flipped:drawingHandler:)` keeps a 1pt inset oval, `systemGreen` / `systemYellow` / `systemRed` / `systemGray`, `isTemplate = false`, and `accessibilityDescription = severity.rawValue`. Characterization tests only check non-nil and size (12 and 14). They would not catch a colour or backing-scale change. The oval in the handler uses `rect` (image bounds), which matches `size - 2` when the handler is called with the image size. Drawing is now live (retina / dynamic colour) instead of a baked 1x bitmap. That is the usual replacement, not a logic bug.
- **ComponentTree:** `find` / `collect` / `componentKeys` match the old private copies (id-or-name DFS, preorder collect, `[id, name]` keys). `Monitor.toggleComponent` / `setAllComponents` and `ComponentPicker` still use the same all-on union / remove-keys rules. No behaviour change found.
- **Unused API:** Removing `WatchedPage.isComponentEnabled(_ name: String)` is safe in this repo (no callers; live path is the `ComponentStatus` overload). Removing `MapHTTPClient`’s unused `byURL:` String-to-Data init argument is safe; `byURL` as a property remains. Unused `import StatusCore` / `import Foundation` removals are compile-only.
- `pollAll`’s `try? store.save` was left as unverified def-004. That leftover is what breaks the def-001 “do not replace a corrupt store” promise.
