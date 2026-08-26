# LOC Limits Assessment

_Measured 2026-08-21 at commit `50df55e4` on branch `main`._

## Executive Summary

- Total threshold breaches: **0** — **0 files** above 300 code LOC and **0 functions/methods** above 50 physical lines.
- Severity breakdown: **HIGH=0, MEDIUM=0, LOW=0**. Watch items at the 50-line function line are recorded below as KEEP, not as breaches.
- Scope: all **37 Swift files** under `Sources/` (28) and `Tests/` (9). `.build` and `greendot.app` are outside those trees and were excluded. `UITests/` is out of scope and is noted only as a review flag.
- File impact: **2,877 code LOC** / **3,186 physical** (295 blank, 14 comment). Largest production file is `Sources/greendot/AppDelegate.swift` at **195 code / 213 physical** (65% of the 300-line signal). Largest test file is `Tests/StatusCoreTests/ProbeAndMonitorTests.swift` at **182 code / 200 physical**.
- Function impact: **218** `func` / `init` declarations parsed (including nested functions and protocol requirements). Longest spans are `AppDelegate.applicationDidFinishLaunching` and `AppDelegate.openPanel`, both **exactly 50 physical lines** (44 and 48 code). The threshold is `> 50`, so they are not breaches.
- Top priorities:
  1. Do not split any current module. No file is near a logical multi-concern split that would pay for itself.
  2. Watch `AppDelegate.applicationDidFinishLaunching` and `AppDelegate.openPanel`. One added phase in either function should extract a named helper, not grow past 50.
  3. Keep test files whole. They are under the file signal today; if one later exceeds 300, treat it as LOW and split only on scenario families.
- Expected net LOC reduction: **none**. There is no oversized file or function to redistribute.
- 300/50 are signals, not hard rules. This tree is already split along provider, menu, panel, and store boundaries.

## Method

- File code LOC: cloc-equivalent Swift classification on every `*.swift` file under `Sources/` and `Tests/`. Blank = whitespace-only. Comment = `//` / `///` lines with no code. Mixed code+comment counts as code. Physical LOC = blank + comment + code. Repository total in scope: **2,877 code, 14 comment, 295 blank**.
- Function span: Swift `func` and `init` from the signature line through the matching closing brace, inclusive. Nested functions are measured independently. Protocol requirements with no body are counted as 1-line declarations. `deinit` and computed properties are not functions for this audit.
- Function code LOC: nonblank, non-comment lines inside that span. The violation predicate is physical span **> 50**, as requested; code LOC is shown to separate statement density from blank lines and comments.
- A recommendation of KEEP means the threshold is a useful signal but extraction would make a cohesive composition root, widget, or linear test harder to read. Test files may legitimately exceed 300 lines and remain LOW; none do in this scope.
- Machine-readable findings omit KEEP/EXEMPT rows: they are human-judgment signals, not safe automated edit instructions.

## Critical Findings

None. No production file is above 300 code LOC. No function is above 50 physical lines.

## Medium Findings

### Non-test files above 300 code LOC — exhaustive

| File | Code LOC | Physical | Concerns | Recommendation | Logical boundary / rationale |
|---|---:|---:|---:|---|---|
| — | — | — | — | — | No production Swift file in `Sources/` exceeds 300 code or physical LOC. |

### Functions and methods above 50 physical lines — exhaustive

| Location | Qualified function | Physical span | Code LOC | Recommendation |
|---|---|---:|---:|---|
| — | — | — | — | No `func` / `init` in `Sources/` or `Tests/` exceeds 50 physical lines. |

## Low / Debatable Findings

### Test files above 300 code LOC — exhaustive

Tests are file-level exempt by the requested policy. None currently exceed the signal.

| File | Code LOC | Physical | Concerns | Recommendation | Logical rationale / boundary |
|---|---:|---:|---:|---|---|
| — | — | — | — | — | Largest test file is `Tests/StatusCoreTests/ProbeAndMonitorTests.swift` at 182 code / 200 physical. |

### Watch list — largest files (all under 300)

These are **not** splits. They are the files that would be re-checked first if the tree grows.

| File | Code LOC | Physical | Concerns | Recommendation | Logical boundary / rationale |
|---|---:|---:|---:|---|---|
| `Sources/greendot/AppDelegate.swift` | 195 | 213 | 5 | KEEP | Composition root: launch wiring, poll/rebuild, menu actions, add/edit panel, UI-test hooks. Collaborators already live in `MenuBuilder`, `PagePanelController`, `UITestDriver`. |
| `Tests/StatusCoreTests/ProbeAndMonitorTests.swift` | 182 | 200 | 4 | KEEP (LOW) | Probe, directory fixture client, store round-trip, poll/grey-bar. Split later only if a new provider family lands. |
| `Sources/greendot/MenuBuilder.swift` | 173 | 193 | 3 | KEEP | `MenuActions` + menu construction + `TargetAction`. `TargetAction` is 18 lines; extracting it would not change cohesion. |
| `Tests/StatusCoreTests/ComponentToggleTests.swift` | 173 | 190 | 2 | KEEP (LOW) | Display-severity filtering vs monitor persist/toggle. One feature surface. |
| `Sources/greendot/ComponentPicker.swift` | 155 | 174 | 1 | KEEP | One checkbox tree widget; `install` is 46 physical / 41 code. |
| `Sources/StatusCore/Monitor.swift` | 149 | 167 | 2 | KEEP | CRUD + poll/toast. `pollAll` is dense (44/44) but one linear poll loop. |
| `Sources/StatusCore/ProviderProbe.swift` | 146 | 156 | 3 | KEEP | Ordered Statuspage / Instatus / Statuspal attempts; parsers are already separate files. |
| `Sources/greendot/PagePanelController.swift` | 145 | 159 | 2 | KEEP | Window chrome + field layout; component list is already `ComponentPicker`. |
| `Sources/StatusCore/Models.swift` | 142 | 161 | 4 | KEEP | `ComponentStatus`, `Incident`, `PageSnapshot`, `WatchedPage`. Split on type boundaries only if this file crosses 300. |
| `Tests/greendotTests/PanelLifecycleTests.swift` | 125 | 132 | 2 | KEEP (LOW) | Panel replace/close plus checkbox-click crash tests. |
| `Tests/StatusCoreTests/ParserTests.swift` | 124 | 132 | 3 | KEEP (LOW) | Statuspage / Instatus / Statuspal fixtures in one parser suite. |
| `Tests/greendotTests/MenuBuilderTests.swift` | 120 | 130 | 1 | KEEP (LOW) | One menu-open contract. |

Remaining 25 in-scope Swift files are under 100 code LOC.

### Watch list — longest functions (all ≤ 50 physical)

| Location | Qualified function | Physical span | Code LOC | Recommendation |
|---|---|---:|---:|---|
| `Sources/greendot/AppDelegate.swift:12` | `applicationDidFinishLaunching` | 50 | 44 | KEEP — at the line. Sequential launch wiring (store, client, notifier, login item, menu bar, seed, timers). Extract a helper only when a new launch phase is added. |
| `Sources/greendot/AppDelegate.swift:114` | `openPanel` | 50 | 48 | KEEP — at the line. Size is the save/toggle/setAll/remove closures passed into `PagePanelController`. Do not grow those closures in place. |
| `Sources/greendot/ComponentPicker.swift:28` | `install(in:below:listHeight:)` | 46 | 41 | KEEP — one Auto Layout assembly. |
| `Sources/greendot/MenuBuilder.swift:66` | `pageSubmenu` | 45 | 42 | KEEP — one page submenu: unreachable row, components, incidents, actions. |
| `Sources/StatusCore/ProviderProbe.swift:18` | `probe(pageURL:client:)` | 45 | 43 | KEEP — ordered provider attempts; nested `take` is 12 lines. |
| `Sources/StatusCore/Monitor.swift:107` | `pollAll` | 44 | 44 | KEEP — linear per-page fetch, grey fallback, toast. Dense but one phase. |
| `Sources/StatusCore/ProviderProbe.swift:101` | `probeStatuspal` | 42 | 42 | KEEP — HTML subdomain extract then API hosts. |
| `Sources/greendot/AppDelegate.swift:83` | `buildMenu` | 30 | 30 | KEEP — `MenuActions` wiring only. |
| `Sources/greendot/PagePanelController.swift:17` | `init` | 35 | 34 | KEEP — window construction. |
| `Sources/greendot/AppDelegate.swift:165` | `installUITestHooks` | 28 | 27 | KEEP — already delegated to `UITestDriver` for the click/field work. |

## Worst Offenders and Proposed Structure

1. `Sources/greendot/AppDelegate.swift` — largest production file, still 105 code lines under the file signal. Keep it as the NSApplication composition root. If launch or panel closures grow, extract `makeHTTPClient()` / `startTimers()` or named panel callbacks inside the same type; do not create a second AppDelegate module.
2. `Tests/StatusCoreTests/ProbeAndMonitorTests.swift` — largest test file, 118 code lines under the file signal. Optional future split: probe+directory client vs monitor store/poll. LOW only.
3. `Sources/greendot/MenuBuilder.swift` and `Sources/greendot/ComponentPicker.swift` — already sit on menu vs picker boundaries. No further file split.
4. `Sources/StatusCore/Models.swift` — four value types. A later split would be `ComponentStatus.swift` / `PageSnapshot.swift` / `WatchedPage.swift`, not an arbitrary 300-line shard.

## Recommendations

1. Do not apply file splits or function decompositions from this cycle. The 300/50 signals are unused.
2. Treat the two 50-line `AppDelegate` methods as tripwires: the next launch-time concern or panel callback should be a named helper in the same file.
3. If a test file later exceeds 300 code LOC, split by behavior family (parser provider, probe vs store, panel vs menu), never into arbitrary 300-line shards. Flag those splits LOW.
4. Preserve current public types. `Monitor`, `ProviderProbe`, `MenuBuilder`, and `PagePanelController` are already the facades a split would have produced.
5. Re-run this assessment after any AppDelegate or ProbeAndMonitorTests growth of more than ~20 lines.

## Out of Scope / Flagged for Review

- No source, test, dependency, configuration, or application bundle file was modified. This file is the only write.
- `greendot.app/` and `.build/` were excluded as requested. They are not Swift source.
- `UITests/GreenDotUITests/GreenDotUITests.swift` is outside `Sources/` and `Tests/`. It measures **283 code / 321 physical** (35 blank, 3 comment). Code LOC is under 300; `wc -l` would report 321. Longest function is `setUpWithError` at 32 physical. If UI tests are brought into a later cycle, EXEMPT (LOW) unless a new scenario family makes a split useful.
- `Package.swift` is not under `Sources/` or `Tests/` and was not inventoried (21 physical lines).
- No `cloc` binary was executed in this subagent environment. Counts follow cloc's Swift blank/comment/code rules applied to the 37 in-scope files by full-file read.

## Machine-Readable Findings

```json
{
  "findings": []
}
```
