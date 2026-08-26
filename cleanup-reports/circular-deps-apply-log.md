# Circular Dependency Apply Log

Date: 2026-08-26
Branch: `cleanup/apply-20260826-circular`
Base: `7347b965d278856b63660ae8f3f33931c1b17d34`

Applied **0/4** report items. No source or test file was changed.

## Item dispositions

| Item | Report recommendation | Disposition | Reason |
|---|---|---|---|
| `circular-001` | `EXTRACT` | **SKIPPED** | The machine-readable finding is `verified: false`. The cleanup gate permits automatic application only for verified findings, so the proposed model-aware `Aggregator` extraction was not applied. |
| `circular-002` | `KEEP` | **RETAINED** | The finding is `verified: true`. The application/menu callback loop is intentional, and the report confirms weak captures and event-monitor cleanup. There is no safe cycle-removal change to apply. |
| `circular-003` | `KEEP` | **RETAINED** | The finding is `verified: true`. The editor and panel callbacks are intentional, weak-backed, generation-gated, and covered by the panel release tests. There is no safe cycle-removal change to apply. |
| `circular-004` | `KEEP` | **RETAINED** | The finding is `verified: false` and recommends `KEEP`. The AppKit delegate edge is framework-managed, `PagePanelController.close()` clears the delegate, and the release test covers deallocation. No ownership change was applied. |

The unverified `circular-001` and `circular-004` records were logged and skipped/retained; they were not treated as confirmed defects. No deferred log was created because no file-ownership deferral occurred.

## Target graph check

Command:

```text
swift package describe --type json
```

The JSON target graph reported these edges:

```text
greendotTests -> greendot
greendotTests -> StatusCore
greendotTests -> TestSupport
greendot -> StatusCore
TestSupport -> StatusCore
StatusCoreTests -> StatusCore
StatusCoreTests -> TestSupport
```

`StatusCore` has no target dependencies. The edge list was passed to `tsort`; it returned exit code 0 and produced a topological order. Therefore the target graph remains acyclic.

## Verification

| Check | Result |
|---|---|
| `swift package describe --type json` | PASS; target graph described successfully |
| Target graph `tsort` check | PASS; exit code 0, no cycle reported |
| `swift build` | PASS; build completed successfully |
| `swift test` | PASS; 150 tests passed, 1 benchmark test skipped, 0 failures |

No RED/GREEN TDD commits were required because no report item was authorized for a source or test change.

## Commit

This documentation-only record is committed as:

`[DOCS] Record retained dependency boundaries`
