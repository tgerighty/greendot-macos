# greendot cleanup summary

Date: 2026-08-21. Scope: `Sources/`, `Tests/`, config, spec. No product code was changed.

Independent verifiers read the live tree and tried to refute every **HIGH** finding and every **CERTAIN** finding that could drive an automated delete. All of those **survived**. `verified: true` below means that gate, not a second product review.

## Totals (analysis agents)

| Agent | Issues | HIGH | MEDIUM | LOW |
|---|---:|---:|---:|---:|
| Deduplication | 16 | 2 | 8 | 6 |
| Type consolidation | 3 actionable | 0 | 1 | 2 |
| Dead code | 9 | 0 | 1 | 8 |
| Circular deps | 1 | 0 | 1 | 0 |
| Weak typing | 12 (8 KEEP) | 0 | 0 | 3 to strengthen |
| Defensive programming | 25 (15 LEGITIMATE) | 1 | 6 | 3 actionable |
| Legacy | 8 | 0 | 0 | 8 |
| AI slop | 7 | 0 | 2 | 5 |
| LOC limits | 0 breaches | 0 | 0 | 0 |

Rough unique work items after overlap merge: **~35**. Safe mechanical deletes: **~15–20 LOC**. Behaviour fixes (error-hiding) add a little code, they do not shrink the tree.

## Verified (survived adversarial read)

| ID | Verdict |
|---|---|
| dedup-001 | SURVIVES — `Monitor.find`/`collect` matches `ComponentPicker.find`/`collect` |
| dedup-002 | SURVIVES — two ComponentToggle tests share the same GitHub fixture setup |
| def-001 | SURVIVES — `try? monitor.load()` plus seed/save can replace a corrupt `config.json` |
| def-003 | SURVIVES — menu `try?` after in-memory mutate; save failure still shows success |
| dead-001 / legacy-006 | SURVIVES — `isComponentEnabled(_ name: String)` has no callers |
| dead-002 | SURVIVES — unused `import StatusCore` in `main.swift` |
| dead-003 | SURVIVES — unused `import Foundation` in Severity/StatusMapping/ToastPolicy |
| dead-004 | SURVIVES — `MapHTTPClient` init `byURL:` parameter unused |
| cycle-001 | SURVIVES — Models.swift ↔ Severity.swift via Aggregator overloads (same module, compiles) |
| weak-001 | SURVIVES — only production `!` is `groupID!` after a nil filter |
| legacy-001 | SURVIVES — `Status Menu.app` still in SwiftLint/gitignore |
| legacy-003 | SURVIVES — spec still says `make uitest` starts an HTTP server |
| legacy-005 | SURVIVES — `NSImage.lockFocus` is used and deprecated |
| slop `_ = menu.title` / `_ = sender` / `_ =` on `@discardableResult` | SURVIVES as noise |

**KEEP (do not delete):** `_ = previous` in `AppDelegate.openPanel` (SIGSEGV keep-alive), `_ = alert.runModal()`, JSON `[String: Any]` in parsers, DNC/`GREENDOT_*` test seams, `popMenuOnScreen`/`showMenu`.

## Overlaps

- **Unused `isComponentEnabled(String)`:** dead-001, legacy-006, and slop unused-API. One delete.
- **Severity copy strings:** dedup-005 and type-002. Optional `Severity` label helper.
- **NSUserNotificationAlertStyle:** dead-005 and legacy-004. Review together; do not auto-delete.
- **Toggle tree walk:** dedup-001 (exact helper copy) and dedup-003 (same enable/disable rules in Monitor vs ComponentPicker). Extract walk first; do not merge UI checkboxes into StatusCore.
- **Corrupt config:** def-001 and def-002 are one user-visible failure (load swallow then seed overwrite).

## Top 10 (impact × low risk)

1. **def-001** — Catch `monitor.load()`; show an alert; skip OpenAI seed if load threw.
2. **def-003 / def-004** — Do not hide `store.save` after menu/panel/poll mutate.
3. **dead-001** — Remove unused `isComponentEnabled(_ name: String)`.
4. **dedup-001** — Put `find`/`collect`/`componentKeys` on `ComponentStatus` in StatusCore; use them from Monitor and ComponentPicker.
5. **dead-002 / dead-003 / dead-004** — Drop unused imports and the unused `byURL:` init mapping.
6. **legacy-001** — Drop `Status Menu.app` from `.swiftlint.yml` and `.gitignore`.
7. **legacy-005** — Draw the status dot with `NSImage(size:flipped:drawingHandler:)`.
8. **legacy-003** — Fix the spec line about the UI-test HTTP server.
9. **weak-001** — Replace `groupID!` with `if let` / `compactMap`.
10. **slop** — Stop `_ = menu.title` / `_ = sender` / `_ =` on discardable results.

## Suggested order

1. Dead code and leftover names (items 3, 5, 6, 8, 10) — small, safe.
2. Error-hiding on load/save (items 1, 2) — user-visible correctness.
3. `groupID!` and `lockFocus` (items 7, 9).
4. Shared tree-walk helper (item 4) only if you want less duplication; it is not required for correctness.
5. Skip: parser Codable rewrite, merging the three parsers, splitting AppDelegate (at the 50-line tripwire, not over).

## LOC limits

No production file is over 300 lines. No function is over 50. `AppDelegate.applicationDidFinishLaunching` and `openPanel` sit on 50. Do not split them without a new phase of work.

## What this analysis did not do

- Did not run `jscpd` (Swift).
- Did not change any product code.
- Did not scan `.build/` or the installed `.app`.
- Cluster SonarQube extras (SwiftLint / opengrep-swift) are a separate gate; this pass is structural.

Reports:

- `cleanup-reports/deduplication-assessment.md`
- `cleanup-reports/type-consolidation-assessment.md`
- `cleanup-reports/dead-code-assessment.md`
- `cleanup-reports/circular-deps-assessment.md`
- `cleanup-reports/weak-typing-assessment.md`
- `cleanup-reports/defensive-programming-assessment.md`
- `cleanup-reports/legacy-code-assessment.md`
- `cleanup-reports/ai-slop-assessment.md`
- `cleanup-reports/loc-limits-assessment.md`
- `cleanup-reports/summary.md`
