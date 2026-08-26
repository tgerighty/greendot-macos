# Legacy Code Apply Log — 2026-08-21

Applying `cleanup-reports/legacy-code-assessment.md` (legacy-001, legacy-003,
legacy-005, legacy-007). Skip legacy-002, 004, 006, 008 as instructed.

Branch: `cleanup/legacy-code`
Worktree: `/Users/terry.gerighty/coding/greendot-legacy-code`
HEAD before this cycle: `50df55e43f489d4e1daf701b8a08522b0c23ce42`
HEAD after this cycle: `f0a3ed7c877a896b4dd05b4da29afa7ac1737736`

File allowlist (only these files were changed):

- `.swiftlint.yml`
- `.gitignore`
- `docs/superpowers/specs/2026-08-21-status-menu-design.md`
- `Sources/greendot/StatusDot.swift`
- `Sources/greendot/MenuBarController.swift`
- `Tests/greendotTests/PanelLifecycleTests.swift`

Baseline (before any change): `swift test` → 58 passed. `swiftlint lint --strict` → 0 violations.

Final: `swift test` → 60 passed (2 new characterization tests). `swiftlint lint --strict` → 0 violations. No revert.

Result: **4/4** authorized items applied. 4 items skipped (see `legacy-code-deferred.md`).

---

## legacy-005 — `StatusDot` `lockFocus` → drawing handler — APPLIED

- **Commit:** `45af7cb256589c7b679370b72ac84c650e3f95c0`
- **TDD:** characterization tests first in `PanelLifecycleTests.swift`:
  - `testStatusDotImageIsNonNilAndHasSize`
  - `testStatusDotImageUsesRequestedSize`
- Tests passed against the old `lockFocus` path (image non-nil, size 12 and 14).
- Then `StatusDot.image` used `NSImage(size:flipped:drawingHandler:)`. Same inset oval and `NSColor.systemGreen` / `systemYellow` / `systemRed` / `systemGray`. `isTemplate` stays false. Accessibility description stays `severity.rawValue`.
- Tests passed after the change. Full suite 60 passed. SwiftLint clean.
- **Files:** `Sources/greendot/StatusDot.swift`, `Tests/greendotTests/PanelLifecycleTests.swift`.

---

## legacy-001 — leftover `Status Menu.app` — APPLIED

- **Commit:** `06dc8c09077ff16179a44fbac2012095d8331deb`
- Removed `Status Menu.app` from `.swiftlint.yml` `excluded` and from `.gitignore`.
- Kept `greendot.app` in both lists.
- Grep after the change: no `Status Menu.app` in the worktree source.

---

## legacy-003 — spec HTTP server sentence — APPLIED

- **Commit:** `974d1061bb92b67d65699304b51d7c8eadc8febf`
- Replaced the sentence that said `make uitest` starts a local fixture HTTP server.
- New text: tests set `GREENDOT_FIXTURE_DIR`; the app uses `DirectoryHTTPClient`; tests do not start an HTTP server.
- **File:** `docs/superpowers/specs/2026-08-21-status-menu-design.md`.

---

## legacy-007 — “menu-bar extra” comment — APPLIED (allowlisted comment only)

- **Commit:** `f0a3ed7c877a896b4dd05b4da29afa7ac1737736`
- `MenuBarController.popMenuOnScreen` comment now says `NSStatusItem`, not “extra”.
- Comment only. No behaviour change.
- UITests still says “off-screen extra frames”. That file is outside the allowlist. See deferred.

---

## Verification

1. **Baseline at `50df55e`:** `swift test` 58 passed; `swiftlint lint --strict` 0 violations.
2. **After all four commits at `f0a3ed7`:** `swift test` 60 passed; `swiftlint lint --strict` 0 violations in 37 files.
3. `git diff --name-only 50df55e..HEAD` lists only the six allowlisted files.
4. No `lockFocus` / `unlockFocus` remains. No `Status Menu.app` remains.
