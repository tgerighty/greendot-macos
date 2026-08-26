# Legacy Code Assessment

## Executive Summary

- Findings: 5 total; HIGH 0, MEDIUM 4, LOW 1.
- Classifications: SAFE-TO-REMOVE 0, NEEDS-VERIFICATION 5, ACTIVE-DEPRECATED 0.
- Safe removal estimate: 0 LOC. The only conditional removal is the Statuspal `.eu` branch, estimated at 4-8 LOC, and it must not be removed without checking user pages and provider support.
- The current tree has no deprecated annotation, TODO removal marker, old provider implementation, migration already run, re-export shim, or concluded feature flag that can be safely deleted.
- Build evidence: `swift build` passed. `swift test` passed 150 tests with 1 benchmark test skipped because `GREENDOT_BENCH` was not set.

Top priorities:

1. Keep the AppKit panel retention and next-run-loop handoff. Git history identifies it as a crash fix, and current lifecycle tests exercise replacement and close paths.
2. Keep the `Codable` defaults and version guard until the supported `config.json` population is known. They protect persisted data from earlier schema revisions.
3. Decide whether Statuspal `.eu` remains a supported user path. The repository has implementation support but no `.eu` regression test or documented support decision.

## Critical

None found.

## Medium Findings

### legacy-001 - AppKit panel keep-alive workaround is active

`Sources/greendot/AppDelegate.swift:182-188` and `Sources/greendot/StatusPageEditor.swift:24-70` retain the previous editor through a replacement and defer `show()` to the next main-run-loop turn. The comments call out an AppKit `SIGSEGV` when the previous dialog is released during a status-item menu action. Commit `889a31d` introduced this workaround after the second-page Edit crash; `9a721e6` separately fixed the released-when-closed window crash. Current `PanelLifecycleTests` and `StatusPageEditorTests` cover repeated replacement and close behavior.

This is a live platform compatibility workaround, not obsolete code. Removing or simplifying it can reintroduce a crash on the macOS 13+ deployment range. Keep it; only revisit after a deliberate AppKit lifecycle replacement and a macOS-version test matrix. No removable LOC is counted.

### legacy-002 - WatchedPage decoder preserves earlier config fields

`Sources/StatusCore/Models.swift:154-166` uses `decodeIfPresent` defaults for `notificationsEnabled`, `disabledComponentNames`, and `snapshot`. `disabledComponentNames` was added by commit `0931789`, while the initial `b18e16f` config format did not contain that field. The current `testOldConfigWithoutDisabledNamesStillLoads` fixture confirms the top-level old shape, although it does not yet include a populated old page snapshot.

This is persisted-user-data compatibility. Removing the defaults would turn an older `config.json` into a corrupt-store error or lose the intended defaults. Keep it. If a future controlled migration proves that old files cannot exist, replace this shim only with an explicit migration and a tested backup/rollback plan. No removable LOC is counted.

### legacy-003 - ComponentStatus decoder preserves pre-nesting snapshots

`Sources/StatusCore/Models.swift:34-46` accepts missing `id`, `children`, and `isGroup` values. Commit `0588846` changed `ComponentStatus` from three fields with synthesized `Codable` to nested component groups and added these defaults. Existing snapshots written before that change can therefore still decode.

This is an active persisted-snapshot compatibility path. It has no external API deprecation marker, but deleting it can make a previously saved page unloadable. Keep it and add a fixture containing a pre-`0588846` populated snapshot before considering any schema migration. No removable LOC is counted.

### legacy-004 - AppConfig version gate is an active format boundary

`Sources/StatusCore/PageStore.swift:3-12,44-62,73-76` persists `version`, sets `currentVersion` to `1`, and rejects versions newer than the current version. The field has existed since the initial `b18e16f` format; commit `ce7eea9` made validation apply on load and save. There is no old migration implementation to remove.

Do not remove the version field or change the guard based only on the current repository. Existing users can have persisted files, and the public `AppConfig` type exposes this format. Keep it; if version 2 is introduced, add an explicit migration before changing the accepted range. No removable LOC is counted.

## Low / Debatable

### legacy-005 - Statuspal `.eu` support may be an unverified alternate-domain fallback

`Sources/StatusCore/ProviderProbe.swift:171-196,222-226` recognizes `*.statuspal.eu`, scrapes the same host form, and tries both `statuspal.io` and `statuspal.eu` API prefixes. This support is present from the initial `b18e16f` implementation, but the current tests and changelog exercise/document `.statuspal.io` only. The repository does not establish that `.eu` is retired, nor that no user has such a watched page.

Classify as NEEDS-VERIFICATION and review provider/user support before changing it. If `.eu` is intentionally unsupported, remove the host check, API prefix, and regex alternative together and add a migration/error path for affected saved pages; otherwise add a `.eu` regression fixture. Conditional reduction is approximately 4-8 LOC, not a safe current removal.

## Recommendations

1. Make no legacy-code deletion in this pass; all five findings are either active compatibility behavior or need external evidence.
2. Add one realistic old `config.json` fixture with a populated pre-nesting snapshot and missing component-toggle fields. This will protect the two decoder shims from accidental cleanup.
3. Document the supported config version and migration policy next to `AppConfig.currentVersion`; preserve forward-version rejection.
4. Add an explicit Statuspal `.eu` test if the domain remains supported. If product policy retires it, perform a user-config inventory and controlled migration before removing it.
5. Keep the UI-test environment paths and benchmark gate (`GREENDOT_*` variables), `DirectoryHTTPClient` host-specific/hostless fixture lookup, and preferred-provider fallback. They are all referenced by current tests or the Makefile and have no evidence of being concluded experiments.

## Out of Scope / Retained Active Paths

- `Sources/StatusCore/DirectoryHTTPClient.swift:16-24` has host-specific lookup followed by a hostless lookup. Both are current contracts: `testDirectoryClientPrefersHostFolder` covers the first and `testDirectoryClientReadsSummaryPath` covers the second. It is not safe-to-remove legacy code.
- `Sources/StatusCore/ProviderProbe.swift:89-113` tries a preferred provider first and falls back to the other providers. `testPreferredProviderMissFallsBackToOthers` covers this current behavior; no provider implementation is obsolete in the current tree.
- `GREENDOT_CONFIG_DIR`, `GREENDOT_FIXTURE_DIR`, `GREENDOT_SKIP_LOGIN_ITEM`, `GREENDOT_SKIP_SEED`, `GREENDOT_POLL_SECONDS`, `GREENDOT_UI_TEST`, dump/log variables, and `GREENDOT_BENCH` are set by current UI tests or `Makefile`. No flag is always-on, always-off, or concluded in repository history.
- `Sources/greendot/MenuBarController.swift` and `Sources/greendot/Notifier.swift` were deleted in current history (`16d3c75` and `1f9e871`) and have no current references; they are not remaining legacy code.
- Generated `.build`, `greendot.app`, generated UI project files, and existing cleanup reports were excluded as requested. Rejected design alternatives in `docs/superpowers/specs/2026-08-21-status-menu-design.md` are decision records, not runtime legacy paths.

## Independent Verification Disposition

The mandatory gate selected 4 of 5 records. Independent verifiers confirmed 3; those records now have `verified: true`. 1 lower-confidence record remains provisional.

The verifier found `legacy-001` only partial. It has been narrowed to `UNCERTAIN` / `REVIEW`, with the counterevidence recorded in the machine-readable detail.

Verification evidence: [verification-batch-1.md](verification-batch-1.md), [verification-batch-2.md](verification-batch-2.md).

Final machine-readable severity counts: HIGH 0, MEDIUM 4, LOW 1. The original prose above records the specialist's pre-verification assessment; this disposition and the JSON block below are authoritative after verification.

## Machine-Readable Findings

```json
{"findings":[{"id":"legacy-001","file":"Sources/greendot/AppDelegate.swift","line":182,"severity":"MEDIUM","confidence":"UNCERTAIN","recommendation":"REVIEW","classification":"NEEDS-VERIFICATION","detail":"History and analogous lifecycle tests support the workaround, but exact AppDelegate wiring is not directly tested. Independent verifier disposition: PARTIAL. AppDelegate.swift:169-188 retains previous and defers show; git commit 889a31d records the SIGSEGV rationale. Current tests cover analogous replacements but not private AppDelegate.openEditor and its identity guard.","verified":false},{"id":"legacy-002","file":"Sources/StatusCore/Models.swift","line":164,"severity":"MEDIUM","confidence":"CERTAIN","recommendation":"KEEP","classification":"NEEDS-VERIFICATION","detail":"The decoder preserves missing later component-toggle keys; notifications were already present in the initial repository schema.","verified":true},{"id":"legacy-003","file":"Sources/StatusCore/Models.swift","line":44,"severity":"MEDIUM","confidence":"CERTAIN","recommendation":"KEEP","classification":"NEEDS-VERIFICATION","detail":"The custom decoder is active compatibility for pre-nesting snapshots.","verified":true},{"id":"legacy-004","file":"Sources/StatusCore/PageStore.swift","line":74,"severity":"MEDIUM","confidence":"CERTAIN","recommendation":"KEEP","classification":"NEEDS-VERIFICATION","detail":"The version guard is an active forward-compatibility boundary until explicit migration exists.","verified":true},{"id":"legacy-005","file":"Sources/StatusCore/ProviderProbe.swift","line":193,"severity":"LOW","confidence":"UNCERTAIN","recommendation":"REVIEW","classification":"NEEDS-VERIFICATION","detail":"Statuspal .eu host and API fallback support is current but untested and undocumented beyond code, so external user/provider support must be checked before any removal.","verified":false}]}
```
