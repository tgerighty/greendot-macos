# Circular Deps Apply Log

Date: 2026-08-21
Worktree: `/Users/terry.gerighty/coding/greendot-circular-deps`
Branch: `cleanup/circular-deps`
Base: `930daa9693a0712cfbdcc78dae5a647d78d4172f` (`cleanup/apply`, phase 1 merged)

Applied **1/1** authorized item (`cycle-001`).
Skipped optional / out-of-scope report notes (see `circular-deps-deferred.md`).

## Result

| Item | Verdict | Commit |
|---|---|---|
| cycle-001 | APPLIED | `84715d98a54d97485cc364f0b5e7fa8ad1cb58a3` |

No UNSAFE. No revert.

## Commits

| SHA | Message |
|---|---|
| `e115a104ee6004a96e10ae84502bd5bb250e488a` | `[REFACTOR] Lock Aggregator ranking overloads before cycle-001 extract` |
| `84715d98a54d97485cc364f0b5e7fa8ad1cb58a3` | `[REFACTOR] Move Aggregator model overloads out of Severity.swift` |

HEAD after this cycle: `84715d98a54d97485cc364f0b5e7fa8ad1cb58a3`

## TDD

### RED

Baseline at `930daa9` (untouched): `swift test` → **62 passed**.

`AggregatorTests` already locked `barSeverity(from: [PageSnapshot])`. Added characterization tests for the other cycle-closing overload and for the ranking that stays in `Severity.swift`:

- `testEmptyComponentsAreGreen`
- `testComponentRedBeatsYellowAndGreen`
- `testComponentYellowBeatsGreen`
- `testGreyDoesNotDriveComponentsWhenARealStatusExists`
- `testComponentsAreGreyWhenEveryComponentIsGrey`
- `testFromSeveritiesEmptyIsGreen`
- `testFromSeveritiesRedBeatsYellowAndGreen`
- `testFromSeveritiesGreyDoesNotBeatGreen`
- `testFromSeveritiesAllGreyIsGrey`

`swift test`: **71 tests, 0 failures.** Commit `e115a10`.

### GREEN

Moved the two `Aggregator` overloads that take model types out of `Severity.swift` into `extension Aggregator` in `Models.swift`:

- `barSeverity(from: [PageSnapshot])`
- `severity(from: [ComponentStatus])`

Left `enum Severity` and `Aggregator.fromSeverities(_ severities: [Severity])` in `Severity.swift`. Same Swift module. No signature change. `WatchedPage.displaySeverity` still calls `Aggregator.severity(from:)`.

Grep after the change: `Severity.swift` has no `PageSnapshot` and no `ComponentStatus`.

`swift test`: **71 tests, 0 failures.**
`swiftlint lint --strict`: **0 violations, 0 serious in 37 files.**

Commit `84715d9`.

## Files touched (allowlist)

- `Sources/StatusCore/Severity.swift`
- `Sources/StatusCore/Models.swift`
- `Tests/StatusCoreTests/AggregatorTests.swift`

Not changed: `Tests/StatusCoreTests/GreyPulseTests.swift` (allowlisted; no cycle-001 edit required).

`git diff --name-only 930daa9..HEAD` lists only those three allowlisted files.

## Test status

GREEN. `swift test` 71/71 pass. `swiftlint lint --strict` clean.

Overloads gone from `Severity.swift`: **yes**.
