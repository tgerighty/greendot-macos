PONYTAIL MODE ACTIVE — level: full

# Legacy Code Assessment

## Executive Summary

- Total findings: 5. Severity: HIGH=0, MEDIUM=1, LOW=4. No path is safe to remove now: the version-1 file upgrade remains documented (`docs/settings-files.md:191`), older field defaults remain documented (`docs/settings-files.md:71`), and the two UI compatibility behaviors have tests (`Tests/greendotTests/PanelLifecycleTests.swift:9`, `Tests/greendotTests/ComponentSelectionIndexTests.swift:48`).
- Top priorities: retain the version-1 upgrade until support ends (`docs/settings-files.md:197`); retain decoders for older and hand-edited files (`Sources/StatusCore/Models.swift:56`, `Sources/StatusCore/Models.swift:170`); keep the AppKit lifetime fix until its exact menu action has a macOS regression check (`Sources/greendot/AppDelegate.swift:196`).
- Estimated impact: 0 production LOC can be removed safely now. The five findings span eight source files (`Sources/StatusCore/PageStore.swift:149`, `Sources/StatusCore/StateFile.swift:43`, `Sources/StatusCore/Models.swift:56`, `Sources/greendot/AppDelegate.swift:196`, `Sources/greendot/AppDelegate+Config.swift:33`, `Sources/greendot/StatusPageEditor.swift:65`, `Sources/greendot/ComponentSelectionIndex.swift:60`, `Sources/greendot/ComponentPicker.swift:90`). The version-1 path has about 14 directly identifiable production lines in its legacy decoder and stripping branches; this is only a conditional estimate because version-2 files can still carry stale fields (`Sources/StatusCore/PageStore.swift:149`, `Sources/StatusCore/StateFile.swift:52`, `Sources/StatusCore/Models.swift:176`, `Tests/StatusCoreTests/LegacyFieldTests.swift:45`).
- Pre-flight: this is a Swift Package Manager project for macOS 13 (`Package.swift:1`, `Package.swift:6`). The repo defines `swift build`, `swift test`, and `swiftlint lint` commands (`Makefile:8`, `Makefile:11`, `Makefile:17`). This Linux worker has `rg` and `git`, but no `swift`, `swiftlint`, or `cloc`; the assessment uses read-only source, test, and history inspection. No build or runtime test was run.

## Critical Findings

None. No source path has a confirmed safe removal; the version-1 migration is still part of the documented upgrade (`docs/settings-files.md:197`).

## Medium Findings

### legacy-001 — Version-1 single-file migration is still active

**Class: ACTIVE-DEPRECATED. Recommendation: KEEP.** The current config format is version 2 (`Sources/StatusCore/PageStore.swift:4`, `docs/settings-files.md:49`), but `PageStore.load` accepts older versions and preserves inline machine state only for version 1 (`Sources/StatusCore/PageStore.swift:93`, `Sources/StatusCore/PageStore.swift:97`, `Sources/StatusCore/PageStore.swift:149`). The version-1 launch flag and page snapshot are decoded from `config.json` (`Sources/StatusCore/StateFile.swift:43`, `Sources/StatusCore/Models.swift:176`). The next save writes `config.json` and `state.json` separately (`Sources/StatusCore/PageStore.swift:198`, `Sources/StatusCore/PageStore.swift:200`); this upgrade is explicitly documented as deferred until the next save (`docs/settings-files.md:204`) and checked by a fixture test (`Tests/StatusCoreTests/StateFileSplitTests.swift:81`). Removing this path now could discard an existing user's cached snapshot or launch setting. Decide a supported-format cutoff and migration policy before changing it. Estimated safe reduction: 0 LOC (`docs/settings-files.md:197`, `Tests/StatusCoreTests/StateFileSplitTests.swift:88`).

## Low / Debatable Findings

### legacy-002 — Older watched-page field defaults

**Class: NEEDS-VERIFICATION. Recommendation: KEEP.** `WatchedPage` gives a missing ID a new UUID and defaults missing notification and disabled-component fields (`Sources/StatusCore/Models.swift:170`, `Sources/StatusCore/Models.swift:174`). Missing fields and ID repair are part of the current hand-edit contract (`docs/settings-files.md:71`, `docs/settings-files.md:74`), and the store checks whether to persist repaired IDs (`Sources/StatusCore/PageStore.swift:101`, `Sources/StatusCore/PageStore.swift:174`). These defaults also support older saved files, but no inventory of user files establishes that the old cases have ended. Removing them would make documented incomplete files fail or change their behavior (`docs/settings-files.md:65`). Estimated safe reduction: 0 LOC.

### legacy-003 — Older component snapshot defaults

**Class: NEEDS-VERIFICATION. Recommendation: KEEP.** `ComponentStatus` supplies `id = name`, empty children, and `isGroup = false` when older snapshots lack those fields (`Sources/StatusCore/Models.swift:56`, `Sources/StatusCore/Models.swift:58`). The cache still decodes page snapshots from `state.json` (`Sources/StatusCore/StateFile.swift:17`, `Sources/StatusCore/PageStore.swift:134`) and can decode inline snapshots while loading version 1 (`Sources/StatusCore/Models.swift:176`). Removing these defaults could reject saved snapshots with the older shape. Confirm a supported cache-format cutoff before removal. Estimated safe reduction: 0 LOC.

### legacy-004 — AppKit panel lifetime workaround

**Class: NEEDS-VERIFICATION. Recommendation: REVIEW.** The menu action retains the prior editor until the next main-queue turn because releasing it in that action caused an AppKit deallocation crash (`Sources/greendot/AppDelegate.swift:177`, `Sources/greendot/AppDelegate.swift:196`). Reload uses the same retained-editor pattern (`Sources/greendot/AppDelegate+Config.swift:33`, `Sources/greendot/AppDelegate+Config.swift:38`), and panel replacement also retains its prior panel (`Sources/greendot/StatusPageEditor.swift:31`, `Sources/greendot/StatusPageEditor.swift:65`). A panel replacement test exists (`Tests/greendotTests/PanelLifecycleTests.swift:9`), but it constructs panels directly, not the `AppDelegate.openEditor` menu path (`Tests/greendotTests/PanelLifecycleTests.swift:12`, `Sources/greendot/AppDelegate.swift:169`). Keep the workaround unless an exact-path macOS test and a supported-version check prove it unnecessary. Estimated safe reduction: 0 LOC.

### legacy-005 — Previous picker rule for repeated component IDs

**Class: NEEDS-VERIFICATION. Recommendation: KEEP.** `ComponentSelectionIndex` explicitly preserves the previous picker's last-preorder rule when two components share an ID (`Sources/greendot/ComponentSelectionIndex.swift:60`, `Sources/greendot/ComponentSelectionIndex.swift:61`). The current picker indexes checkboxes by component ID (`Sources/greendot/ComponentPicker.swift:90`, `Sources/greendot/ComponentPicker.swift:93`), and tests assert the repeated-ID result in the index and visible picker (`Tests/greendotTests/ComponentSelectionIndexTests.swift:48`, `Tests/greendotTests/ComponentPickerStateTests.swift:102`). This is active behavior for ambiguous provider data, not an unused old path. Change it only with a new repeated-ID rule and picker tests. Estimated safe reduction: 0 LOC.

## Recommendations

1. Keep the version-1 reader while the published upgrade path remains supported (`docs/settings-files.md:191`, `Sources/StatusCore/PageStore.swift:149`). If support ends, first define what happens to an unsaved version-1 file and to copied version-2 files with stale inline fields (`docs/settings-files.md:204`, `docs/settings-files.md:210`).
2. Keep missing-field defaults while incomplete config files and older cached snapshots can be loaded (`docs/settings-files.md:65`, `Sources/StatusCore/Models.swift:56`, `Sources/StatusCore/Models.swift:170`).
3. Keep the UI compatibility behavior until tests cover the actual menu replacement and repeated-ID picker paths on macOS (`Sources/greendot/AppDelegate.swift:169`, `Sources/greendot/ComponentPicker.swift:90`, `Tests/greendotTests/ComponentPickerStateTests.swift:102`).

## Out of Scope / Flagged for Review

- No concluded old/new feature flag was identified. `GREENDOT_UI_TEST`, `GREENDOT_SKIP_LOGIN_ITEM`, and `GREENDOT_SKIP_SEED` are used by the current UI test launch (`Sources/greendot/AppDelegate.swift:208`, `UITests/GreenDotUITests/GreenDotUITests.swift:35`, `UITests/GreenDotUITests/GreenDotUITests.swift:40`). `GREENDOT_BENCH` gates the current benchmark (`Makefile:15`, `Tests/greendotTests/PerformanceHarnessTests.swift:26`). The poll and config directory overrides remain documented (`README.md:55`). These are current controls, not known dead flags.
- Statuspal `.eu` support and provider fallback attempts are live probe behavior, with no evidence that the domain or fallback is obsolete (`Sources/StatusCore/ProviderProbe.swift:183`, `Sources/StatusCore/ProviderProbe.swift:203`, `Sources/StatusCore/ProviderProbe.swift:205`). The format-version guard protects the persisted-file boundary (`Sources/StatusCore/PageStore.swift:97`, `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:234`). Do not treat these as legacy removals.
- The directly marked legacy fields are the launch flag and inline snapshot (`Sources/StatusCore/StateFile.swift:52`, `Sources/StatusCore/Models.swift:176`). Static review cannot establish whether external users still hold version-1 files (`docs/settings-files.md:204`).

## Machine-Readable Findings

```json
{"findings":[
  {"id":"legacy-001","file":"Sources/StatusCore/PageStore.swift","line":149,"severity":"MEDIUM","confidence":"CERTAIN","recommendation":"KEEP","detail":"Version-1 inline state still loads and migrates on the next save; removal needs a supported-format policy.","verified":false},
  {"id":"legacy-002","file":"Sources/StatusCore/Models.swift","line":170,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Missing watched-page fields are accepted for older and hand-edited config files.","verified":false},
  {"id":"legacy-003","file":"Sources/StatusCore/Models.swift","line":56,"severity":"LOW","confidence":"LIKELY","recommendation":"KEEP","detail":"Missing component fields are defaulted while cached and version-1 snapshots can still load.","verified":false},
  {"id":"legacy-004","file":"Sources/greendot/AppDelegate.swift","line":196,"severity":"LOW","confidence":"LIKELY","recommendation":"REVIEW","detail":"The retained editor works around an AppKit deallocation crash; the exact menu path needs a macOS test before removal.","verified":false},
  {"id":"legacy-005","file":"Sources/greendot/ComponentSelectionIndex.swift","line":60,"severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"The last-preorder repeated-ID rule is active picker behavior with regression tests.","verified":false}
]}
```
