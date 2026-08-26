# Deduplication Apply Log

Date: 2026-08-21
Branch: `cleanup/deduplication`
Base: `930daa9693a0712cfbdcc78dae5a647d78d4172f` (`cleanup/apply`, phase 1 merged)

Applied **2/2** verified `CONSOLIDATE` items (`dedup-001`, `dedup-002`).
Skipped / deferred **14/14** KEEP SEPARATE, REVIEW, parser, and file-owned items (`dedup-003` … `dedup-016`). See `deduplication-deferred.md`.

## Result

| Item | Verdict | Commit |
|---|---|---|
| dedup-001 | APPLIED | `9afaaeb2e8847d63bd67e2c6f70790aac976229e` |
| dedup-002 | APPLIED | `bbb094829f94660d9cc01c1f22df49c06e3f5a47` |
| dedup-003 | DEFERRED (unverified; needs `Models.swift`) | — |
| dedup-004 | DEFERRED (unverified REVIEW) | — |
| dedup-005 | DEFERRED (`MenuBuilder.swift` / `ToastPolicy.swift` / `Severity.swift`) | — |
| dedup-006 | SKIPPED (parser consolidation) | — |
| dedup-007 | SKIPPED (parser consolidation) | — |
| dedup-008 | DEFERRED (`MenuBuilder.swift`; unverified) | — |
| dedup-009 | DEFERRED (unverified REVIEW) | — |
| dedup-010 | SKIPPED (unverified LIKELY; broader than GitHub paste) | — |
| dedup-011 | SKIPPED (parser consolidation) | — |
| dedup-012 | SKIPPED (KEEP SEPARATE) | — |
| dedup-013 | SKIPPED (KEEP SEPARATE) | — |
| dedup-014 | SKIPPED (KEEP SEPARATE) | — |
| dedup-015 | SKIPPED (KEEP SEPARATE) | — |
| dedup-016 | SKIPPED (KEEP SEPARATE) | — |

No revert. No files outside the allowlist.

## Commits

| SHA | Message |
|---|---|
| `81466e073a0723c7ee4de536513c8f4c014e2618` | `[REFACTOR] Lock component tree find/collect/keys characterisation` |
| `9afaaeb2e8847d63bd67e2c6f70790aac976229e` | `[REFACTOR] Extract shared component tree walk into ComponentTree` |
| `bbb094829f94660d9cc01c1f22df49c06e3f5a47` | `[REFACTOR] Share GitHub monitor fixture in ComponentToggleTests` |

HEAD: `bbb094829f94660d9cc01c1f22df49c06e3f5a47`

## TDD

### RED — characterisation (dedup-001)

Baseline at `930daa9`: `swift test` **62 passed**. `swiftlint lint --strict` **0 violations in 37 files**.

Added Monitor-path lock-in tests in `Tests/StatusCoreTests/ComponentToggleTests.swift`:

- `testToggleComponentByNameDisablesIdAndDescendantKeys` — find by name, collect descendants, disable id+name keys
- `testSetAllComponentsRecordsEveryIdAndName` — `componentKeys` records every id and name

`swift test`: **64 passed**. SwiftLint clean. Commit `81466e0`.

Then added public `ComponentTree` tests (`testComponentTreeFindMatchesIdOrNameAndWalksChildren`, `testComponentTreeCollectIncludesSelfAndDescendants`, `testComponentTreeKeysIncludeIdAndName`). Compile failed with `cannot find 'ComponentTree' in scope` (RED).

### GREEN — dedup-001

Created public `Sources/StatusCore/ComponentTree.swift` with `find`, `collect`, and `componentKeys`. Pointed `Monitor` and `ComponentPicker` at it. Removed the private copies.

`swift test`: **67 passed**. `swiftlint lint --strict`: **0 violations in 38 files**.

Commit `9afaaeb`.

### GREEN — dedup-002

Covering tests already existed (`testToggleComponentPersists`, `testSetAllComponentsOffThenOn`). Extracted `monitorWithGitHubOutage()` for GitHub JSON + `MapHTTPClient` + `add`. Each test still owns its assertions. Reload uses a new `MapHTTPClient()` because `load()` reads the store only (avoids SwiftLint `large_tuple`).

`swift test`: **67 passed**. `swiftlint lint --strict`: **0 violations in 38 files**.

Commit `bbb0948`.

## Files touched (allowlist)

- `Sources/StatusCore/ComponentTree.swift` (created)
- `Sources/StatusCore/Monitor.swift`
- `Sources/greendot/ComponentPicker.swift`
- `Tests/StatusCoreTests/ComponentToggleTests.swift`

Not changed: `Tests/StatusCoreTests/ProbeAndMonitorTests.swift`, `Tests/StatusCoreTests/ToastPolicyTests.swift`.

Not changed (owned elsewhere / deferred): `Sources/StatusCore/Models.swift`, `Sources/StatusCore/Severity.swift`, `Sources/greendot/MenuBuilder.swift`, `Sources/StatusCore/ToastPolicy.swift`.

## Test status

GREEN. `swift test` 67/67 pass. `swiftlint lint --strict` clean (38 files).
