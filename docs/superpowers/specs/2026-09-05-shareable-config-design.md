# Shareable config

Date: 2026-09-05

This spec makes `config.json` a settings file that a user can copy between machines and share with other people. It splits cached poll data out of the file, makes the file readable and deterministic, makes load tolerant of hand-edited files, puts the poll interval in the file, and adds two menu items to reveal and reload the file.

## What it is

The user copies `~/Library/Application Support/greendot/config.json` to another machine, or sends it to a colleague. The receiving app loads it, polls the pages, and shows the same list with the same per-page settings. The file contains only settings. It is small, pretty-printed, and stable across saves. The user can edit it by hand.

## Audit findings this spec closes

| # | Finding | Evidence |
|---|---|---|
| 1 | 92% of the file is cached poll snapshot (194 KB of 210 KB on the live config) | `Models.swift` `WatchedPage.snapshot` is persisted |
| 2 | `didSetLaunchAtLogin: true` travels with the file, so machine B never gets the login item | `Monitor+Mutations.swift` `enableLaunchAtLoginOnFirstRun` early return |
| 3 | Every save is byte-different; `Set<String>` reorders per launch; single unsorted line | `Models.swift` `disabledComponentNames: Set<String>`, `PageStore.swift` plain `JSONEncoder()` |
| 4 | Read once at launch; an externally replaced file is clobbered by the next save; no reveal/reload | `Monitor+Polling.swift` `store.save(merge.config)`, `MenuBuilder.swift` |
| 5 | Duplicate `id` or missing `id` fails load with "could not be read" and disables polling | `PageStore.swift` `validate`, `Models.swift` `WatchedPage.init(from:)` |
| 6 | Poll interval is env-only (`GREENDOT_POLL_SECONDS`); a launchd login item has no env | `AppDelegate.swift` `pollInterval(from:)` |
| 7 | Stale shared snapshot causes spurious first-poll notification on machine B | `Monitor+Polling.swift` `pollToast` |
| 8 | Feed URLs may carry `?token=` secrets; 0600 protects locally only | `RssPersistTests.swift` |

## Decisions

These decisions are settled. Do not re-open them in this slice.

| Topic | Decision |
|---|---|
| Files | Two files in the config directory. `config.json` holds settings. `state.json` holds machine-local cache. Both mode `0600`, atomic write. |
| `config.json` shape | `{ "version": 2, "pollSeconds": 60, "pages": [ { "id": "<uuid>", "url": "...", "name": "...", "notificationsEnabled": true, "disabledComponentNames": ["a", "b"] } ] }`. No `snapshot`. No `didSetLaunchAtLogin`. |
| `state.json` shape | `{ "version": 2, "didSetLaunchAtLogin": true, "snapshots": { "<page uuid>": <PageSnapshot> } }`. |
| In-memory model | `AppConfig` stays the single in-memory truth for `Monitor`, including `pages[].snapshot` and `didSetLaunchAtLogin`. Only `PageStore` knows about the two files. `Monitor` code does not change for the split. |
| Encoding | `JSONEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]` for both files. `disabledComponentNames` is encoded as a sorted array. The same `AppConfig` always encodes to the same bytes. |
| Skip unchanged writes | `PageStore.save` reads each target file first and does not write when the bytes are identical. A poll that changes only a snapshot rewrites `state.json` and does not touch `config.json`. |
| Version | `AppConfig.currentVersion = 2`. Load accepts `version <= 2`. A version-1 file (snapshots inline in pages, `didSetLaunchAtLogin` at top level) loads and is split on the next save. When `state.json` has a snapshot for a page id, it wins over an inline one. |
| Missing `state.json` | Load as `didSetLaunchAtLogin: false`, no snapshots. This is the normal case after copying only `config.json`. |
| Missing `config.json` | Load as empty `AppConfig`, as today. |
| Missing page `id` | Mint a `UUID()` on decode. |
| Duplicate page `id` | Keep every page. Mint a fresh `UUID()` for the second and later pages with the same id. Save still rejects duplicates (should be unreachable). |
| Normalised load rewrites | When load minted or replaced any id, `PageStore.load` saves the normalised config back before returning. A load that changed nothing does not write. |
| `pollSeconds` | `AppConfig.pollSeconds: TimeInterval`, default `60`. Always written. On decode: missing, non-finite, or `<= 0` becomes `60`. Env `GREENDOT_POLL_SECONDS` still overrides the file when set and valid (UI tests use it). |
| Menu | Two new items directly under "Refresh": "Reveal Config File" (identifier `reveal-config`) and "Reload Config" (identifier `reload-config`). |
| Reveal | `NSWorkspace.shared.activateFileViewerSelecting([store.configURL])`. |
| Reload | Calls the existing public `Monitor.load()`. On success: rebuild the menu, replace the poll timer with the loaded interval, poll once now. On failure: `presentError`, keep the in-memory config, keep the old timer. |
| Toasts on reload | No change. Pages that disappear keep any delivered toast until the next clear. |
| First-run seed | Unchanged. |
| Secrets in URLs | Not redacted. README warns the user. |
| Grey pulse, toast timing, icon tick | Stay hardcoded. Not settings. |
| Import / export dialogs | Not built. Reveal + Reload is the whole UX. |

## Approaches

1. **Split at the store, keep `AppConfig` whole (chosen).** `PageStore.save` writes settings to `config.json` and cache to `state.json`; `PageStore.load` merges them back into one `AppConfig`. `Monitor`, tests that seed a store, and the editor keep the same types.
2. Move `snapshot` out of `WatchedPage` into a `Monitor` dictionary. Rejected: touches every `Monitor` mutation, the editor, `displaySeverity`, and 30+ tests.
3. Keep one file, strip snapshots on an explicit "Export". Rejected: the local file stays undiffable and the user still cannot copy the file directly.

## Load and save

```
save(config):
  settingsData = encode(config)            // WatchedPage.encode omits snapshot; AppConfig.encode omits didSetLaunchAtLogin
  stateData    = encode(StateFile(version, didSetLaunchAtLogin, snapshots by page id))
  writeIfChanged(configURL, settingsData)
  writeIfChanged(stateURL, stateData)

load():
  config = decode(configURL) or AppConfig()  // tolerant: id minted, duplicates re-minted, pollSeconds defaulted
  state  = decode(stateURL) or nil
  config.didSetLaunchAtLogin = state?.didSetLaunchAtLogin ?? config.didSetLaunchAtLogin(v1 inline) ?? false
  for page in config.pages: page.snapshot = state?.snapshots[page.id] ?? page.snapshot(v1 inline)
  if ids were normalised: save(config)
  return config
```

## Behaviour on machine B after copying `config.json` only

- Pages load with `snapshot == nil`. Menu shows grey dots until the first poll (about one second after launch).
- Component selections apply after the first poll because they are keyed by component id and name.
- No spurious notification: `pollToast` returns nil when `previous` is nil.
- `didSetLaunchAtLogin` is false, so the login item is enabled on first run, as the README promises.
- The first poll re-probes providers once per page (`prefer` is nil). Later polls use the cached provider from `state.json`.

## Tests that change

| Test | Change |
|---|---|
| `PollPerformanceTests.testChangedPollRewritesOnlyStateFile` | Assert `state.json` inode changes and `config.json` inode does not. |
| `PollPerformanceTests.testUnchangedPollRewritesNeitherFile` | Also assert `state.json` inode unchanged. |
| `PageStoreValidationTests.testLoadRejectsDuplicateWatchedPageIDs` | Becomes: load keeps both pages, second gets a new id, file is rewritten with unique ids. |
| `ProbeAndMonitorTests.testPageStoreLoadUnsupportedVersionThrows` | Version 3 throws. |
| `MonitorFirstRunTests` | `didSetLaunchAtLogin` round-trips through `state.json`; assertions on `store.load()` unchanged. |
| `MenuBuilderTests.testMenuHasAboutGreendotImmediatelyAboveQuit` | Unchanged; verify still passes. |

## Docs

README "Config" section describes: the two files and what each holds; how to copy `config.json` to another machine (quit or use Reload Config); Reveal Config File; `pollSeconds`; env overrides; the warning that feed URLs may contain tokens. CHANGELOG gets one line per user-visible change. Write docs in ASD-STE100 style: short sentences, one instruction per sentence, active voice.
