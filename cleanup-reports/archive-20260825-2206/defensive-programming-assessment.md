# Defensive Programming Assessment

**Date**: 2026-08-21
**Scope**: Product Swift under `Sources/StatusCore` and `Sources/greendot`. Tests and UI tests were scanned for `try?` / `catch` inventory only. Their `try? FileManager.removeItem` and fixture `URL(string:)!` sites are LEGITIMATE test I/O and are not action items.
**Method**: Every product `try?`, `do/catch`, throwing I/O/parse/HTTP call, and force unwrap was read in surrounding context. System-boundary handling (HTTP, file I/O, JSON parse, AppKit/ServiceManagement) is not flagged as removable.

## Executive Summary

- **Sites analyzed**: 16 product `try?`, 9 product `catch` blocks, 0 empty `catch {}`, 0 `try!`, 0 `as!`, 1 product force unwrap (`groupID!`), plus throwing HTTP/file/JSON boundaries and one missing completion handler.
- **Total classified findings**: 25 (JSON `def-001` … `def-025`).
- **By classification**: ERROR-HIDING 4 · NEEDS-REFACTOR 5 · UNNECESSARY 1 · LEGITIMATE 15.
- **Severity (actionable only)**: HIGH 1 · MEDIUM 6 · LOW 3.
- **Headline**: StatusCore already throws on store/probe failures. The menu-bar shell swallows those errors with `try?` on load, seed, menu mutations, and poll persistence. Add/edit from the panel is the only user path that shows `NSAlert`. There are no empty catches. Do not remove HTTP, file, or JSON handling.
- **Top priorities**:
  1. **Stop swallowing `monitor.load()`** (`def-001`). A corrupt or unreadable `config.json` starts as empty in-memory config. First-run seed can then overwrite the file with a single OpenAI page.
  2. **Stop swallowing store mutations in the menu/panel** (`def-003`, `def-004`). `remove` / notify / component toggles update memory, then `try?` hides a failed write. The UI looks saved; the next launch reverts.
  3. **Log poll failures and persist poll snapshots without hiding the write** (`def-004`, `def-006`, `def-007`). Grey isolation is correct. Silent `try? store.save` and HTTP 5xx-as-unsupported are not.

## Critical Findings

### def-001 HIGH · ERROR-HIDING — `Sources/greendot/AppDelegate.swift:24`

```swift
try? monitor.load()
```

`Monitor.load()` is `throws` and `PageStore.load()` already classifies missing vs corrupt vs other I/O. Missing file returns empty `AppConfig` without throwing (first-run). Any throw (corrupt JSON, permission, unexpected Cocoa error) is discarded.

- **Error lost**: `StoreError.corrupt` and non-missing file I/O.
- **User impact**: The bar starts with zero pages. If `GREENDOT_SKIP_SEED` is unset, `def-002` then probes OpenAI and `Monitor.add` writes a new `config.json`, replacing the unreadable file. The user loses the previous page list with no alert.
- **Do not remove**: `PageStore.load()` itself. That is a file/JSON boundary (`def-012`, `def-013`).
- **Fix**: Catch in `applicationDidFinishLaunching`, show `NSAlert(error:)`, and skip seed when load threw. Keep first-run empty-config seed only when load succeeded with no pages.

### def-002 MEDIUM · ERROR-HIDING — `Sources/greendot/AppDelegate.swift:47`

```swift
try? await monitor.add(url: url, name: "OpenAI")
```

First-launch seed. `add` throws `ProbeError` (network/unsupported) or store write errors.

- **Error lost**: probe and save failures for the documented default page.
- **User impact**: Empty “No status pages” menu with no reason. Combined with `def-001`, this is also the overwrite path for a corrupt store.
- **Fix**: Same alert as add-panel (`def-018`), or `NSLog` plus skip. Never seed after a failed load.

### def-003 MEDIUM · ERROR-HIDING — `Sources/greendot/AppDelegate.swift:92,96,139,145,151`

Menu and edit-panel closures:

```swift
try? self?.monitor?.remove(id: id)
try? self?.monitor?.toggleNotifications(id: id)
try? self?.monitor?.toggleComponent(id: page.id, name: name)
try? self?.monitor?.setAllComponents(id: page.id, enabled: enabled)
try? self?.monitor?.remove(id: page.id)
```

Each Monitor method mutates `config` first, then `try store.save(config)`. The shell discards the save error and calls `rebuild()`.

- **Error lost**: directory create, JSON encode, atomic write, `chmod 0600`.
- **User impact**: Remove, notification toggle, and component checkboxes appear applied. Restart restores the old `config.json`. Add/edit in the same panel correctly uses `NSAlert` (`def-018`).
- **Fix**: Match the panel save path: `do/catch` + `NSAlert(error:)`. Rebuild only after a successful save, or rebuild and then alert so memory/disk are not left silently split.

### def-004 MEDIUM · ERROR-HIDING — `Sources/StatusCore/Monitor.swift:148`

```swift
try? store.save(config)
```

`pollAll()` writes every page snapshot (including `isUnreachable`) after the poll loop. Failure is ignored. Return value is still the toast list, so notifications can fire for a state that never hit disk.

- **Error lost**: same store write errors as `def-003`.
- **User impact**: Restart shows the last successful save. If that save is old, `WatchedPage.displaySeverity` with a missing snapshot uses zero components and `Aggregator.fromSeverities([])` returns **green** until the next poll. This `try? store.save` is the persistence backstop for in-memory mutations that `def-003` already failed to write.
- **Fix**: Return save failure to the app (or log + keep a `lastSaveError`). Do not use `try?`. Do not delete the save.

## Medium Findings

### def-006 MEDIUM · NEEDS-REFACTOR — `Sources/StatusCore/Monitor.swift:116`

```swift
} catch {
    snapshot = PageSnapshot(..., overall: .grey, isUnreachable: true)
}
```

Per-page isolation is correct. One probe failure must not abort the rest of the list, and grey is the product rule for fetch failure.

- **What is missing**: no `NSLog` / no error object. Unsupported vs unreachable vs store-unrelated `Error` all become the same grey snapshot.
- **Fix**: Keep the catch. Log `error.localizedDescription` (and page URL). Do not rethrow from `pollAll`.

### def-007 MEDIUM · NEEDS-REFACTOR — `Sources/StatusCore/ProviderProbe.swift:90-98,58-61`

```swift
guard status == 200 else { return .miss }
...
if !sawHTTP && sawNetworkError {
    throw ProbeError.unreachable
}
throw ProbeError.unsupported
```

HTTP 5xx/429 still sets `sawHTTP` and counts as a provider miss. After all endpoints miss, add/edit throws `unsupported` (“not a known status page format”). `pollAll` greys any throw, so existing pages still go grey.

- **Error lost**: server-side fetch failure, misclassified as “wrong format” on the add/edit panel.
- **Fix**: Treat 5xx/429 (and status `0` from a non-HTTP response) as `.networkError`. Keep 404 as miss. This is classification at an HTTP boundary, not removal of handling.

### def-008 MEDIUM · NEEDS-REFACTOR (MISSING handler) — `Sources/greendot/Notifier.swift:24`

```swift
UNUserNotificationCenter.current().add(request)
```

`add(_:withCompletionHandler:)` is called without a handler. Permission denial, invalid content, or delivery error is dropped. `requestPermissionIfNeeded` already logs authorization errors.

- **Fix**: Pass a completion and `NSLog` on error, same pattern as permission. Do not fail the poll loop.

## Low Findings

### def-005 LOW · NEEDS-REFACTOR — `Sources/StatusCore/Monitor.swift:24`

```swift
try? store.save(config)
```

First-run `didSetLaunchAtLogin = true` then best-effort save, then `onLaunchAtLoginEnable?()`. If the save fails, the next launch retries (disk flag still false). If the save succeeds and `SMAppService.register` fails, the flag stays true and launch-at-login never retries (`def-009`).

- **Fix**: Log save failure. Prefer `def-009` over deleting this `try?`.

### def-009 LOW · NEEDS-REFACTOR — `Sources/StatusCore/Monitor.swift:21-26` + `Sources/greendot/LaunchAtLogin.swift:9-15`

The first-run flag is persisted before `register()` succeeds. `LaunchAtLogin.enable` logs the ServiceManagement error and returns. Design says launch-at-login defaults on.

- **Fix**: Set and save `didSetLaunchAtLogin` only after `register()` succeeds, or retry while `SMAppService.mainApp.status != .enabled`. Keep the `catch` + `NSLog` in `LaunchAtLogin` (`def-017`).

### def-010 LOW · UNNECESSARY — `Sources/StatusCore/ProviderProbe.swift:146`

```swift
guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
    return nil
}
```

`pattern` is a compile-time literal. A compile failure would silently disable Statuspal HTML subdomain extraction forever.

- **Not removable as a boundary**: `NSRegularExpression` throws by API contract. Optional change: `static let` compiled once, or treat compile failure as a programmer error. Do not turn a successful HTML fetch into a hard add failure.

## Legitimate (keep — not removable)

These are system-boundary or AppKit/test paths. Cleanup must not delete them.

### def-011 LEGITIMATE — `Sources/StatusCore/StatuspageParser.swift:65`

`Dictionary(grouping: grouped) { $0.groupID! }` after `filter { $0.groupID != nil && !$0.isGroup }`. Safe unwrap, not error-hiding. Optional `compactMap` for style only.

### def-012 LEGITIMATE — `Sources/StatusCore/PageStore.swift:41-47`

Missing `config.json` → empty `AppConfig`. Other I/O is rethrown. Correct first-run file I/O.

### def-013 LEGITIMATE — `Sources/StatusCore/PageStore.swift:53-54`

Decode / version failure → `StoreError.corrupt`. Correct JSON parse boundary. The defect is the caller swallow (`def-001`).

### def-014 LEGITIMATE — `Sources/StatusCore/ProviderProbe.swift:93-94`

Parse / wrong-provider JSON → `.miss` so the next provider can run. Correct parse boundary.

### def-015 LEGITIMATE — `Sources/StatusCore/ProviderProbe.swift:96-97`

`client.get` throw → `.networkError`. Correct HTTP boundary.

### def-016 LEGITIMATE — `Sources/StatusCore/ProviderProbe.swift:121-122`

Statuspal HTML fetch failure sets `sawNetworkError`. Correct HTTP boundary.

### def-017 LEGITIMATE — `Sources/greendot/LaunchAtLogin.swift:13,27`

`SMAppService` register/unregister errors are logged. Correct ServiceManagement boundary.

### def-018 LEGITIMATE — `Sources/greendot/AppDelegate.swift:129-133`

Panel add/edit shows `NSAlert(error:)`. This is the pattern other `try?` call sites should copy.

### def-019 LEGITIMATE — `Sources/greendot/URLOpener.swift:31-36`

`try?` on `FileHandle` / atomic write is UI-test URL logging (`GREENDOT_OPEN_URL_LOG`), not user config. Best-effort I/O. Do not make log-write failure block `NSWorkspace.open` in production (production returns before `append` when the log path is empty).

### def-020 LEGITIMATE — `Sources/greendot/AppDelegate.swift:211`

`try? body.write` for UI-test dumps, after `PathSafety.contained`. Test I/O. Failure should not crash the app.

### def-021 LEGITIMATE — parsers `compactMap`

`StatuspageParser` / `StatuspalParser` / `InstatusParser` skip rows without a title/name. Partial JSON at a parse boundary. Keep.

### def-022 LEGITIMATE — `Sources/StatusCore/DirectoryHTTPClient.swift:18,22`

`Data(contentsOf:)` throws to the probe. Test fixture I/O. Keep.

### def-023 LEGITIMATE — Tests / UITests `try? FileManager.default.removeItem`

Teardown cleanup. Keep.

### def-024 LEGITIMATE — `Sources/StatusCore/Models.swift` `Decodable`

Missing optional keys default; required keys throw into `StoreError.corrupt`. Keep fail-closed decode.

### def-025 LEGITIMATE — `Sources/StatusCore/HTTPClient.swift:15`

`session.data(from:)` throws to `ProviderProbe`. Correct HTTP boundary. `(response as? HTTPURLResponse)?.statusCode ?? 0` is classified under `def-007` (treat 0 as network), not as removable handling.

## Inventory notes

| Pattern | Product count | Notes |
|---|---|---|
| `try?` | 16 | 8 in `AppDelegate` (4 ERROR-HIDING clusters + seed + dump), 2 `try? store.save` in `Monitor`, 5 URL-log I/O, 1 regex |
| `catch {}` / empty catch | 0 | None |
| `try!` / `as!` | 0 | None |
| Force unwrap | 1 | `groupID!` (`def-011`) |
| Missing handler | 1 | `Notifier.add` (`def-008`) |

Test `try?` (temp-dir cleanup, `String(contentsOf:)`) and test `URL(string:)!` are excluded from action counts.

## Recommendations

1. **Surface store errors in the app shell.** Replace `try? monitor.load()` and the five mutation `try?` sites with `do/catch` + `NSAlert`, matching panel save. Skip OpenAI seed when load threw.
2. **Make `Monitor.pollAll` report save failure.** Keep per-page grey isolation. Log the probe error. Do not `try? store.save`.
3. **Classify HTTP 5xx/429/status 0 as unreachable** in `ProviderProbe.attempt`, not as unsupported format.
4. **Log `UNUserNotificationCenter.add` failures.** Keep posting off the poll success path.
5. **Do not remove** PageStore missing-file handling, probe parse/network catches, parser `compactMap`, LaunchAtLogin `NSLog`, URL-log `try?`, or UI-test dump `try?`.

## Out of scope

- Changing poll interval, provider set, or grey-pulse rules.
- Making `DirectoryHTTPClient` / `MapHTTPClient` production HTTP.
- Deleting test teardown `try?`.
- `PageStore.defaultDirectory` `[0]` on `FileManager.urls(for:in:)` — Foundation contract, not error-hiding.

## Machine-Readable Findings

```json
{
  "findings": [
    {
      "id": "def-001",
      "file": "Sources/greendot/AppDelegate.swift",
      "line": 24,
      "severity": "HIGH",
      "confidence": "CERTAIN",
      "recommendation": "ERROR-HIDING",
      "detail": "try? monitor.load() discards StoreError.corrupt and non-missing I/O. Empty in-memory config plus first-run seed can overwrite the user's config.json. Surface NSAlert; do not remove PageStore.load boundary handling.",
      "verified": true
    },
    {
      "id": "def-002",
      "file": "Sources/greendot/AppDelegate.swift",
      "line": 47,
      "severity": "MEDIUM",
      "confidence": "CERTAIN",
      "recommendation": "ERROR-HIDING",
      "detail": "try? await monitor.add(...) swallows probe/save failure for the OpenAI first-run seed and can persist a replacement config after a failed load. Alert or log; skip seed when load threw.",
      "verified": false
    },
    {
      "id": "def-003",
      "file": "Sources/greendot/AppDelegate.swift",
      "line": 92,
      "severity": "MEDIUM",
      "confidence": "CERTAIN",
      "recommendation": "ERROR-HIDING",
      "detail": "try? on remove (92,151), toggleNotifications (96), toggleComponent (139), setAllComponents (145). Memory mutates, save errors discarded, rebuild shows success. Match panel NSAlert; do not remove store.save.",
      "verified": true
    },
    {
      "id": "def-004",
      "file": "Sources/StatusCore/Monitor.swift",
      "line": 148,
      "severity": "MEDIUM",
      "confidence": "CERTAIN",
      "recommendation": "ERROR-HIDING",
      "detail": "pollAll try? store.save hides snapshot persistence failure. Restart can show green from an empty snapshot until the next poll. Return or log save errors; keep the write.",
      "verified": false
    },
    {
      "id": "def-005",
      "file": "Sources/StatusCore/Monitor.swift",
      "line": 24,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "NEEDS-REFACTOR",
      "detail": "enableLaunchAtLoginOnFirstRun uses try? store.save. Next launch retries if the write failed. Log the error; coordinate with def-009 so the flag is not committed before register succeeds.",
      "verified": false
    },
    {
      "id": "def-006",
      "file": "Sources/StatusCore/Monitor.swift",
      "line": 116,
      "severity": "MEDIUM",
      "confidence": "CERTAIN",
      "recommendation": "NEEDS-REFACTOR",
      "detail": "pollAll per-page catch correctly greys unreachable pages but logs nothing. Keep isolation; log the probe error.",
      "verified": false
    },
    {
      "id": "def-007",
      "file": "Sources/StatusCore/ProviderProbe.swift",
      "line": 90,
      "severity": "MEDIUM",
      "confidence": "CERTAIN",
      "recommendation": "NEEDS-REFACTOR",
      "detail": "Non-200 including 5xx/429 becomes .miss; sawHTTP then throws unsupported on add/edit. Treat 5xx/429/status 0 as networkError. Keep 404 as miss. Do not remove HTTP handling.",
      "verified": false
    },
    {
      "id": "def-008",
      "file": "Sources/greendot/Notifier.swift",
      "line": 24,
      "severity": "MEDIUM",
      "confidence": "CERTAIN",
      "recommendation": "NEEDS-REFACTOR",
      "detail": "MISSING: UNUserNotificationCenter.add(request) has no completion handler. Delivery/permission errors are dropped. Log in the completion; do not fail poll.",
      "verified": false
    },
    {
      "id": "def-009",
      "file": "Sources/StatusCore/Monitor.swift",
      "line": 23,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "NEEDS-REFACTOR",
      "detail": "didSetLaunchAtLogin is set and saved before SMAppService.register. A failed enable is logged in LaunchAtLogin but never retried. Persist the flag only after success. Keep LaunchAtLogin catch+NSLog.",
      "verified": false
    },
    {
      "id": "def-010",
      "file": "Sources/StatusCore/ProviderProbe.swift",
      "line": 146,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "UNNECESSARY",
      "detail": "try? NSRegularExpression on a static Statuspal pattern. Compile failure would silently skip HTML subdomain extraction. Optional static compile; not a removable I/O boundary.",
      "verified": false
    },
    {
      "id": "def-011",
      "file": "Sources/StatusCore/StatuspageParser.swift",
      "line": 65,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "LEGITIMATE",
      "detail": "groupID! after filter { groupID != nil }. Safe unwrap, not error-hiding. Style-only compactMap optional.",
      "verified": false
    },
    {
      "id": "def-012",
      "file": "Sources/StatusCore/PageStore.swift",
      "line": 41,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "LEGITIMATE",
      "detail": "Missing config.json returns empty AppConfig; other Cocoa I/O is rethrown. First-run file I/O. Do not remove.",
      "verified": false
    },
    {
      "id": "def-013",
      "file": "Sources/StatusCore/PageStore.swift",
      "line": 53,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "LEGITIMATE",
      "detail": "JSON decode/version failure throws StoreError.corrupt. Parse boundary. Do not remove. Caller swallow is def-001.",
      "verified": false
    },
    {
      "id": "def-014",
      "file": "Sources/StatusCore/ProviderProbe.swift",
      "line": 93,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "LEGITIMATE",
      "detail": "Parse/wrong-provider JSON returns .miss so the next provider can run. Parse boundary. Do not remove.",
      "verified": false
    },
    {
      "id": "def-015",
      "file": "Sources/StatusCore/ProviderProbe.swift",
      "line": 96,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "LEGITIMATE",
      "detail": "client.get throw returns .networkError. HTTP boundary. Do not remove.",
      "verified": false
    },
    {
      "id": "def-016",
      "file": "Sources/StatusCore/ProviderProbe.swift",
      "line": 121,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "LEGITIMATE",
      "detail": "Statuspal HTML fetch catch sets sawNetworkError. HTTP boundary. Do not remove.",
      "verified": false
    },
    {
      "id": "def-017",
      "file": "Sources/greendot/LaunchAtLogin.swift",
      "line": 13,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "LEGITIMATE",
      "detail": "SMAppService register/unregister catch logs localizedDescription (also line 27). ServiceManagement boundary. Do not remove.",
      "verified": false
    },
    {
      "id": "def-018",
      "file": "Sources/greendot/AppDelegate.swift",
      "line": 129,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "LEGITIMATE",
      "detail": "Panel add/edit catch shows NSAlert(error:). Keep as the user-facing pattern for other Monitor throws.",
      "verified": false
    },
    {
      "id": "def-019",
      "file": "Sources/greendot/URLOpener.swift",
      "line": 31,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "LEGITIMATE",
      "detail": "try? FileHandle/atomic write for GREENDOT_OPEN_URL_LOG (lines 31-36). Test I/O; must not block production NSWorkspace.open.",
      "verified": false
    },
    {
      "id": "def-020",
      "file": "Sources/greendot/AppDelegate.swift",
      "line": 211,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "LEGITIMATE",
      "detail": "try? writeDump after PathSafety.contained. UI-test I/O. Do not remove.",
      "verified": false
    },
    {
      "id": "def-021",
      "file": "Sources/StatusCore/StatuspageParser.swift",
      "line": 28,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "LEGITIMATE",
      "detail": "compactMap drops incident/component rows without names (also StatuspalParser, InstatusParser). Partial JSON parse. Do not remove.",
      "verified": false
    },
    {
      "id": "def-022",
      "file": "Sources/StatusCore/DirectoryHTTPClient.swift",
      "line": 18,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "LEGITIMATE",
      "detail": "Data(contentsOf:) throws to the probe for fixture files. Test I/O boundary. Do not remove.",
      "verified": false
    },
    {
      "id": "def-023",
      "file": "Tests/StatusCoreTests/ProbeAndMonitorTests.swift",
      "line": 61,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "LEGITIMATE",
      "detail": "Cluster: test/UITest try? FileManager.removeItem and try? String(contentsOf:) teardown/read. Test I/O. Do not remove.",
      "verified": false
    },
    {
      "id": "def-024",
      "file": "Sources/StatusCore/Models.swift",
      "line": 39,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "LEGITIMATE",
      "detail": "Codable defaults optional keys and throws on required decode, mapped to StoreError.corrupt by PageStore. Fail-closed JSON. Do not remove.",
      "verified": false
    },
    {
      "id": "def-025",
      "file": "Sources/StatusCore/HTTPClient.swift",
      "line": 15,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "LEGITIMATE",
      "detail": "URLSession.data(from:) throws into ProviderProbe. HTTP boundary. statusCode ?? 0 belongs with def-007 classification, not removal.",
      "verified": false
    }
  ]
}
```
