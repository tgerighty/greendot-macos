# Cleanup apply summary

Branch: `cleanup/apply` (not pushed). Base: `50df55e` (main). HEAD: `a58e8de`.

Unit tests **58 → 87**, all pass. `swiftlint lint --strict`: **0**. No items reverted as UNSAFE.

## Applied

| Phase | Items | Evidence |
|---|---|---|
| 1 dead-code | dead-001…004 | RED `146f0e3`, GREEN `a70563d` |
| 1 legacy | legacy-001, 003, 005, 007 | `45af7cb`…`f0a3ed7` |
| 1 ai-slop | slop-001, 002, 003 | `fa9273c` |
| 2 circular-deps | cycle-001 | RED `e115a10`, GREEN `84715d9` |
| 2 dedup | dedup-001, 002 | RED `81466e0`, GREEN `9afaaeb` `bbb0948` |
| 3 defensive | def-001, def-003 | RED `f7d513d`, GREEN `8fd764a` |
| Review follow-up | skip poll after failed load; save-then-assign; StoreError text | `a58e8de` |

## Skipped

| Agent | Why |
|---|---|
| type-consolidation | KEEP / optional |
| loc-limits | no files/functions over limit |
| weak-typing | weak-001 is LOW (skip per agent rule) |
| def-002 remainder, def-004 | not `verified: true` (def-004 hole closed by skipping poll after failed load) |
| dead-005/006/007, legacy-002/004/008, slop-004/007 | REVIEW / LIKELY |
| slop-005 | RESOLVED-UPSTREAM (dead-001 removed the method) |
| slop-006 | deferred; no-op `isUnreachable` copy still in `pollAll` |
| CodeRabbit: restore `MapHTTPClient(byURL:)` init | contradicts verified dead-004 |
| CodeRabbit: move StatusDot tests to XCUITest | characterization tests belong with the unit target |

## Machine evidence

- `swift test`: 87 passed (merged tree after `a58e8de`)
- `swiftlint lint --strict`: 0 violations
- Cluster SonarQube: not scanned for this unpushed branch (`sonar analyze --base` would hit SonarCloud; this repo uses the cluster fleet after a PR)
- CodeRabbit `--agent` on `50df55e..cleanup/apply`: 4 majors; 2 addressed (rollback + corrupt poll); 2 skipped with reasons above
- Independent review: first **REQUEST_CHANGES** (corrupt file still overwritten by poll; no rollback). Those two are fixed in `a58e8de`. StatusDot / ComponentTree / unused-API deletes were faithful.

## Follow-up (human)

- weak-001 `groupID!` → `if let`
- NSUserNotificationAlertStyle in Info.plist
- AppIcon.png keep/delete
- slop-006 no-op copy in `pollAll`
- Optional `Severity` label helper (dedup-005)
- `pollAll` still `try? store.save` on a healthy load (def-004)

## User decision

Not pushed. Say if you want a PR and `/pr-review`.
