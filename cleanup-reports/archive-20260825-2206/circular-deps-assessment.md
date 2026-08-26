# Circular Dependency Analysis Assessment

_Fresh read-only audit performed 2026-08-21 against commit `50df55e4`._

The initial assessment was a static source read. It did not use a compiler
dump, SCC tool, or import-order experiment. Independent verification later
confirmed `cycle-001`; the final JSON `verified` flag records that later gate.

## Executive Summary

- Total issues found: **1** file-level cycle. Severity breakdown:
  **HIGH=0, MEDIUM=1, LOW=0**. The cycle is **STRUCTURAL**. It compiles.
  Swift same-module files are one compilation unit, so it cannot cause an
  import deadlock.
- Module result: **zero BREAKING cycles**. `Package.swift` is a DAG:
  `greendot` depends on `StatusCore`; `StatusCore` has no package
  dependencies. No `StatusCore` file imports `greendot`. SwiftPM would
  reject a target cycle.
- File-level result: **one strongly connected component (SCC)** of size 2
  inside `StatusCore`: `Models.swift` / `Severity.swift`. The `greendot`
  app module has **zero** file-level SCCs.
- Scope: **28 production files** (13 `StatusCore`, 15 `greendot`) plus
  **9 test files** (6 `StatusCoreTests`, 3 `greendotTests`) and
  **1 UITest file** for graph context. Tests add no extra SCC.
- Import forms covered: Swift `import` of modules and system frameworks;
  same-module type-name edges (Swift files in one target do not import
  each other); `@testable import` in tests. No `#if canImport`, no
  `@_exported`, no dynamic `dlopen`.
- Top three priorities:
  1. **Extract the `Aggregator` overloads that take model types out of
     `Severity.swift`.** That is the only cycle-closing pair.
  2. **Keep `StatusCore` free of AppKit and of `greendot` types.** The
     module DAG is correct today.
  3. **Optionally move `TargetAction` out of `MenuBuilder.swift`.** That
     file is a hub, not a cycle.
- Estimated remediation impact: **about 15–30 LOC in 2 files**
  (`Severity.swift` and `Models.swift`, or a new `Aggregator.swift` plus
  a move of `WatchedPage.displaySeverity`). No behaviour change is
  required.

## Method and Evidence

Swift has two graphs. They are not equivalent:

| Graph | Included edges | Production SCCs |
|---|---|---:|
| Module / SwiftPM | `Package.swift` target deps plus `import StatusCore` / `import greendot` | 0 |
| File-level type graph | Same-module type, protocol, and extension references across files | 1 |
| Test-inclusive module graph | Production plus `@testable import` test targets | 0 extra |

Corroborating checks (static only):

- Every file under `Sources/` was read. `StatusCore` imports `Foundation`
  only. Eight `greendot` files import `StatusCore`. Zero `StatusCore`
  files import `greendot` or AppKit.
- Type-name edges were traced for every public and internal type in
  `Sources/StatusCore` and `Sources/greendot`. The only mutual pair is
  `Models.swift` ↔ `Severity.swift`.
- `Package.swift` targets: `StatusCore` (no deps), `greendot` →
  `StatusCore`, `StatusCoreTests` → `StatusCore`, `greendotTests` →
  `greendot` + `StatusCore`.
- Tests do not import each other. UITests import `AppKit` and `XCTest`
  only.

### Module import graph

```
StatusCore          (Foundation only)
    ^
    | import StatusCore  (8 app files)
greendot            (AppKit, UserNotifications, ServiceManagement)
    ^
    | @testable import greendot
    | import StatusCore
greendotTests

StatusCore
    ^
    | @testable import StatusCore
StatusCoreTests
```

`greendot` files that import `StatusCore`:
`AppDelegate.swift`, `ComponentPicker.swift`, `main.swift`,
`MenuBarController.swift`, `MenuBuilder.swift`, `Notifier.swift`,
`PagePanelController.swift`, `StatusDot.swift`.

`greendot` files that do not import `StatusCore`:
`AppEditMenu.swift`, `LaunchAtLogin.swift`, `MenuClickOpener.swift`,
`MenuCommands.swift`, `UITestDriver.swift`, `URLOpener.swift`.

`main.swift` imports `StatusCore` but names no `StatusCore` type. That is
an unused import, not a cycle.

### StatusCore file graph

Edges are type references, not `import` lines.

```
PathSafety.swift
HTTPClient.swift
Severity.swift  <──────────────────────────────┐
    ^                                          │
    │ Severity                                 │ PageSnapshot,
    │ Aggregator                               │ ComponentStatus
Models.swift  ─────────────────────────────────┘
    ^
    │
PageStore.swift     ToastPolicy.swift     StatusMapping.swift
    ^                     ^                     ^
Monitor.swift             │                     │
    │                     │               StatuspageParser.swift  (ParserError)
    │                     │                     ^
    │                     │               InstatusParser.swift
    │                     │               StatuspalParser.swift
ProviderProbe.swift ──────┘───────────────┘
DirectoryHTTPClient.swift → HTTPClient.swift, PathSafety.swift
GreyPulse.swift → Severity.swift
```

`Monitor.swift` is a sink: many files feed it; no StatusCore file names
`Monitor`.

### greendot file graph

```
main.swift → AppDelegate.swift
                │
                ├── AppEditMenu.swift
                ├── LaunchAtLogin.swift
                ├── Notifier.swift
                ├── URLOpener.swift
                ├── UITestDriver.swift
                ├── PagePanelController.swift → ComponentPicker.swift
                ├── MenuBuilder.swift → StatusDot.swift
                │         ▲
                │         │ TargetAction
                │         │
                └── MenuBarController.swift
                          ├── MenuClickOpener.swift ──┘
                          ├── MenuCommands.swift ─────┘
                          └── StatusDot.swift
```

No file pair points both ways.

## Critical Findings

None. There are no HIGH / BREAKING import cycles. A `StatusCore` →
`greendot` import would be BREAKING (SwiftPM cycle). It does not exist.

## Medium Findings

### cycle-001: `Models.swift` -> `Severity.swift` -> `Models.swift`

**Classification:** STRUCTURAL / MEDIUM. **Confidence:** CERTAIN.

Type chain:

    Sources/StatusCore/Models.swift:12
      ComponentStatus.severity: Severity
    Sources/StatusCore/Models.swift:64
      PageSnapshot.overall: Severity
    Sources/StatusCore/Models.swift:118
      WatchedPage.displaySeverity → Aggregator.severity(from:)
          -> Sources/StatusCore/Severity.swift:12
             Aggregator.barSeverity(from snapshots: [PageSnapshot])
          -> Sources/StatusCore/Severity.swift:24
             Aggregator.severity(from components: [ComponentStatus])
                 -> Models.swift

Why it exists: `Severity` is the primitive colour enum. `Aggregator` was
placed in the same file. `Aggregator` then takes `PageSnapshot` and
`ComponentStatus`, which live in `Models.swift`. `WatchedPage` also calls
`Aggregator` to compute `displaySeverity`. The domain model and the
severity primitive therefore depend on each other.

Why it is not BREAKING: both files are in `StatusCore`. The Swift
compiler sees one module. There is no import-time cycle and no runtime
init deadlock.

Why it is STRUCTURAL: `Severity` cannot stay a leaf while `Aggregator`
in the same file names model types. You cannot compile `Severity.swift`
as a lower layer than `Models.swift`. Any later split of StatusCore into
a types package and a policy package would fail on this pair.

Weakest link and resolution: the cycle-closing edges are
`Severity.swift:12` and `Severity.swift:24`. **EXTRACT** those two
`Aggregator` overloads (or the whole `Aggregator` enum) so
`Severity.swift` names only `Severity`.

Smallest break that keeps `WatchedPage.displaySeverity`:

1. Leave `enum Severity` and `Aggregator.fromSeverities` in
   `Severity.swift`.
2. Move `barSeverity(from: [PageSnapshot])` and
   `severity(from: [ComponentStatus])` to `Models.swift` as
   `extension Aggregator`.

After that, `Models.swift` depends on `Severity.swift` one way.
`Severity.swift` names no model type.

Do not move `Aggregator` to a new file **and** keep
`WatchedPage.displaySeverity` as a call into it. That would replace
`Models ↔ Severity` with `Models ↔ Aggregator`.

Blast radius: `Severity.swift`, `Models.swift`, and
`Tests/StatusCoreTests/AggregatorTests.swift` (imports stay
`StatusCore`). Call sites in `Monitor.swift` and tests do not need
signature changes.

## Low / Debatable Findings

None. There are no COSMETIC file-level or module-level cycles.

Same-module ownership closures (`AppDelegate` holds `MenuBarController`,
whose `menuProvider` captures `AppDelegate` weakly) are Cocoa wiring.
`MenuBarController.swift` does not name `AppDelegate`. They are not a
type-level cycle.

## Recommendations

1. Extract the two `Aggregator` overloads that take `PageSnapshot` and
   `ComponentStatus` out of `Severity.swift` (cycle-001). Prefer an
   `extension Aggregator` in `Models.swift` so `WatchedPage.displaySeverity`
   can stay.
2. Do not add `import greendot` or AppKit types to `StatusCore`. That
   would be a BREAKING module cycle or a layering break.
3. Keep `ParserError` as a one-way share from `StatuspageParser.swift`
   into the other parsers, or move it to its own file. It is not a cycle
   today.
4. Optional: move `TargetAction` from `MenuBuilder.swift` into its own
   file. `MenuCommands.swift` and `MenuClickOpener.swift` depend on that
   type only. This is a hub cleanup, not a cycle fix.
5. No import-cycle test exists. A cheap gate is: fail CI if any
   `Sources/StatusCore` file contains `import greendot` or `import AppKit`.
   That protects the module DAG. It will not see cycle-001.

## Out of Scope / Flagged for Review

- **Hub, not a cycle:** `TargetAction` is defined at
  `MenuBuilder.swift:176` and used by `MenuCommands.swift:41` and
  `MenuClickOpener.swift:62`. Edges are one way.
- **Hub, not a cycle:** `ParserError` is defined in
  `StatuspageParser.swift` and used by `InstatusParser.swift` and
  `StatuspalParser.swift`.
- **Unused import:** `Sources/greendot/main.swift:2` imports `StatusCore`
  and names no type from it.
- **String, not an import:** `PageStore.defaultDirectory` uses the path
  component `"greendot"`. That is not a module edge.
- External-framework internal cycles (Foundation, AppKit) are excluded.
- No code, dependency, or configuration was changed by this analysis.

## Machine-Readable Findings

```json
{
  "findings": [
    {
      "id": "cycle-001",
      "file": "Sources/StatusCore/Severity.swift",
      "line": 12,
      "severity": "MEDIUM",
      "confidence": "CERTAIN",
      "recommendation": "EXTRACT",
      "detail": "StatusCore file-level SCC: Models.swift names Severity and Aggregator; Severity.swift Aggregator.barSeverity and Aggregator.severity take PageSnapshot and ComponentStatus. Same-module, so it compiles; it blocks treating Severity as a leaf. Weakest link: Severity.swift:12 and :24. Move those overloads to extension Aggregator in Models.swift. Do not extract Aggregator to a new file while WatchedPage.displaySeverity still calls it.",
      "verified": true
    }
  ]
}
```
