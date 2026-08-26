# Dead Code Apply Log

Date: 2026-08-21
Branch: `cleanup/apply`
Base: `50df55e`

Applied **4/4** verified `REMOVE` items (`dead-001` … `dead-004`).
Skipped **5/5** LIKELY / REVIEW / KEEP items (`dead-005` … `dead-009`). See `dead-code-deferred.md`.

## Result

| Item | Verdict | Commit |
|---|---|---|
| dead-001 | APPLIED | `a70563d` |
| dead-002 | APPLIED | `a70563d` |
| dead-003 | APPLIED | `a70563d` |
| dead-004 | APPLIED | `a70563d` |
| dead-005 | SKIPPED (LIKELY / REVIEW, verified:false) | — |
| dead-006 | SKIPPED (LIKELY / REVIEW, verified:false) | — |
| dead-007 | SKIPPED (LIKELY / REVIEW, verified:false) | — |
| dead-008 | SKIPPED (UNCERTAIN / KEEP, verified:false) | — |
| dead-009 | SKIPPED (LIKELY, verified:false; allowlist excludes config files) | — |

No UNSAFE-REMOVAL. No revert.

## Commits

| SHA | Message |
|---|---|
| `146f0e3b2719b253975d46946f63e5765d8dac70` | `[REFACTOR] Lock remaining component-enable and MapHTTPClient byURL tests` |
| `a70563d33b6a2485ef82e2829d03e1eb9d55ba8e` | `[REFACTOR] Remove unused component-enable overload, imports, and MapHTTPClient byURL init` |

## TDD

### RED

Added lock-in tests for KEEP APIs, then ran `swift test`.

- `Tests/StatusCoreTests/ComponentToggleTests.swift`: `testIsComponentEnabledChecksIdAndName` covers `isComponentEnabled(_ component:)` for id and name.
- `Tests/StatusCoreTests/ProbeAndMonitorTests.swift`: `testMapHTTPClientUsesMutatedByURLProperty` mutates `byURL` after `MapHTTPClient()` with no `byURL:` argument.

`swift test`: **60 tests, 0 failures.** Commit `146f0e3`.

### GREEN

Applied only verified `REMOVE` items in allowlisted files:

- **dead-001** — removed `WatchedPage.isComponentEnabled(_ name: String)` from `Sources/StatusCore/Models.swift`. Kept `isComponentEnabled(_ component:)`.
- **dead-002** — removed unused `import StatusCore` from `Sources/greendot/main.swift`.
- **dead-003** — removed unused `import Foundation` from `Severity.swift`, `StatusMapping.swift`, and `ToastPolicy.swift`.
- **dead-004** — removed unused `byURL:` parameter and String-to-Data mapping from `MapHTTPClient.init`. Kept `public var byURL`. Init now sets `byURL` to `[:]`. Tests still assign Data tuples to the property.

`swift test`: **60 tests, 0 failures.**
`swiftlint lint --strict`: **0 violations, 0 serious in 37 files.**

Commit `a70563d`.

## Files touched (allowlist)

- `Sources/StatusCore/Models.swift`
- `Sources/greendot/main.swift`
- `Sources/StatusCore/Severity.swift`
- `Sources/StatusCore/StatusMapping.swift`
- `Sources/StatusCore/ToastPolicy.swift`
- `Sources/StatusCore/HTTPClient.swift`
- `Tests/StatusCoreTests/ProbeAndMonitorTests.swift`
- `Tests/StatusCoreTests/ComponentToggleTests.swift`

Not changed: `Tests/StatusCoreTests/ToastPolicyTests.swift`, `Tests/StatusCoreTests/AggregatorTests.swift`.

## Test status

GREEN. `swift test` 60/60 pass. `swiftlint lint --strict` clean.
