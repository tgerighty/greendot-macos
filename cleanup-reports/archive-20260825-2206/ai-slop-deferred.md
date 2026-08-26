# AI Slop Deferred and Skipped Items

Date: 2026-08-21
Branch: `cleanup/ai-slop`
Apply commit (for applied items only): `fa9273c2bd91a0e561a31addb23450229182d12c`

This apply considered only `verified: true` findings in the authorized apply
list whose files were inside the allowlist. It did not edit files outside that
scope. `Models.swift`, `Monitor.swift`, `PagePanelController.swift`, and
`UITestDriver.swift` were out of scope.

## Deferred

### slop-005 — Unused name-only enable check

- **File:** `Sources/StatusCore/Models.swift` (line 121)
- **Severity:** MEDIUM, CERTAIN, REMOVE
- **Why deferred:** File is outside this apply allowlist. Instruction: DEFER slop-005.
- **Overlap:** Also dead-001 / legacy-006. A later apply with `Models.swift` on the allowlist can delete `isComponentEnabled(_ name: String)` and keep the `ComponentStatus` overload.

### slop-006 — No-op copy of `isUnreachable`

- **File:** `Sources/StatusCore/Monitor.swift` (line 139)
- **Severity:** LOW, CERTAIN, REMOVE
- **Why deferred:** File is outside this apply allowlist. Instruction: DEFER slop-006.
- **Follow-up:** Keep the `overall` write. Remove only `copy.isUnreachable = snapshot.isUnreachable` after `var copy = snapshot`.

## Skipped

### slop-004 — No-op picker callbacks

- **File:** `Sources/greendot/PagePanelController.swift` (line 29)
- **Severity:** LOW, LIKELY, REVIEW
- **Why skipped:** Instruction: SKIP slop-004. The empty `{ _ in }` defaults are a test seam for panels that pass only `onSave`.

### slop-007 — One-line type wrappers

- **File:** `Sources/greendot/UITestDriver.swift` (line 34)
- **Severity:** LOW, POSSIBLE, INLINE
- **Why skipped:** Instruction: SKIP slop-007. `findButton` / `findField` were not inlined.

## Out of scope (kept)

These were already marked KEEP in the assessment. This apply did not touch them.

- `AppDelegate.swift` `_ = previous` + SIGSEGV comment
- `AppDelegate.swift` `_ = alert.runModal()`
- `URLOpener.swift` `_ = try? handle.seekToEnd()`
