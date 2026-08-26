# LOC Limits Assessment

## Executive Summary

This is a read-only size audit at commit `310032b`. The audit measured every Swift file under `Package.swift`, `Sources`, `Tests`, and `UITests`. `cloc` code counts exclude blank lines and comments; `wc -l` is the physical-line baseline.

- Six findings: one HIGH, one MEDIUM, and four LOW. All six were
  `verified: false` in the initial assessment; independent verification later
  confirmed all six, as recorded below.
- Four files exceed 300 code LOC. The production offender is `Sources/StatusCore/Monitor.swift`; the other three are tests and are LOW by policy.
- Two functions exceed 50 logical body lines: `ProviderProbe.probeHit` (57) and `PerformanceHarnessTests.measureRemaining` (51).
- The affected files contain 1,342 code LOC and 1,493 physical lines. This is 142 code LOC above the file threshold in total; the two function bodies exceed their threshold by eight logical lines in total.

Top priorities:

1. `loc-001`: split `Monitor` by its existing mutation, polling, and presentation boundaries while retaining its locking and persistence behavior.
2. `loc-002`: decompose provider dispatch from attempt/result accounting in `ProviderProbe.probeHit`.
3. `loc-004`: optionally extract the four independent measurements from the 51-line performance helper. This is a LOW test-only cleanup, not a release blocker.

### Measurement baseline

Commands used:

- `cloc --by-file --include-lang=Swift --exclude-dir=.git,.build,greendot.app,cleanup-reports . --csv` (`cloc` 2.10).
- `find ... -name '*.swift' ... | xargs wc -l` for physical lines.
- `swiftlint lint --quiet --config .swiftlint.yml --reporter json` (`SwiftLint` 0.65.1), followed by manual brace/signature inspection. The configured `included` paths are `Sources` and `Tests`; `UITests` was manually inspected because the config excludes it.

`Resources/*`, `greendot.app`, `.build`, `cleanup-reports`, and the generated UI project (`UITests/project.yml`) were excluded. No excluded directory contained a Swift source file included in these totals.

| Scope | Swift files | Physical lines | Blank | Comments | Code LOC |
|---|---:|---:|---:|---:|---:|
| `Sources` | 34 | 3,131 | 314 | 27 | 2,790 |
| `Tests` | 23 | 3,911 | 399 | 10 | 3,502 |
| `UITests` | 1 | 329 | 37 | 3 | 289 |
| `Package.swift` | 1 | 27 | 1 | 1 | 25 |
| **Total** | **59** | **7,398** | **751** | **41** | **6,606** |

### Files above 300 code LOC

| File | Code LOC | Physical lines | Concern count | Severity | Recommendation |
|---|---:|---:|---:|---|---|
| `Sources/StatusCore/Monitor.swift` | 352 | 384 | 4 | HIGH | SPLIT |
| `Tests/greendotTests/PerformanceHarnessTests.swift` | 368 | 397 | 5 | LOW | EXEMPT |
| `Tests/greendotTests/StatusPageEditorTests.swift` | 316 | 359 | 3 | LOW | EXEMPT |
| `Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift` | 306 | 353 | 3 | LOW | EXEMPT |

The four files account for 1,342 code LOC and 1,493 physical lines. Test files are retained as LOW even where they contain several scenario groups because they are cohesive test subjects or intentionally aggregated benchmarks.

## Critical Findings

### loc-001 — `Monitor` is a multi-concern production type

`Sources/StatusCore/Monitor.swift:3` contains 352 code LOC (384 physical lines), exceeding the 300-code-LOC limit. Four concerns are interleaved:

1. State and transition synchronization (`stateLock`, `transitionLock`, revisions, and poll identity).
2. Persistent page mutations (`load`, first-run handling, add/edit/remove, notification and component changes, and `commitWatchedPageMutation`).
3. Asynchronous provider polling and stale-result reconciliation (`pollAll`, `pollResult`, `startPoll`, `applyPollResults`, `mergePollResults`, and `expectedPagesByID`).
4. User-facing status and toast policy (`barSeverity`, `displayedSeverity`, and `pollToast`).

This is a true production maintainability risk because the same type owns file persistence, concurrent transitions, network fan-out, and result merging. The existing private extension already exposes natural boundaries, so the recommended action is `SPLIT`, not an arbitrary line-count cut.

Proposed structure:

- `Monitor.swift`: stored state, initialisers, `pages`, and the lock primitives.
- `Monitor+Mutations.swift`: `load`, `enableLaunchAtLoginOnFirstRun`, `add`, `edit`, `remove`, `toggleNotifications`, `toggleComponent`, `setAllComponents`, `commitWatchedPageMutation`, and `trimmed`.
- `Monitor+Polling.swift`: `pollAll`, `pollResult`, `startPoll`, `applyPollResults`, `mergePollResults`, `pollToast`, and `expectedPagesByID`.
- `Monitor+Presentation.swift`: `barSeverity` and `displayedSeverity`.

Keep the lock and persistence fields in the main type during the first split. A later `MonitorState`/actor refactor should be considered only after the overlapping-poll, cancellation, and mutation tests continue to pass; moving synchronization while splitting files would increase behavioral risk.

## Medium Findings

### Functions above 50 logical body lines

| File | Function (declaration line) | Logical body LOC | Body lines inspected | Concern count | Severity | Recommendation |
|---|---|---:|---|---:|---|---|
| `Sources/StatusCore/ProviderProbe.swift` | `probeHit` (34) | 57 | 41–102 | 3 | MEDIUM | DECOMPOSE |
| `Tests/greendotTests/PerformanceHarnessTests.swift` | `measureRemaining` (189) | 51 | 190–244 | 4 | LOW | DECOMPOSE |

### loc-002 — `ProviderProbe.probeHit` combines dispatch, attempts, and failure policy

`Sources/StatusCore/ProviderProbe.swift:34` has a body of 57 logical lines (non-blank, non-comment lines 41–102), confirmed by SwiftLint and manual brace inspection. Three concerns are in one function:

1. Provider ordering and early-success dispatch.
2. Standard Statuspage/Instatus request construction and parsing.
3. Statuspal handling plus `sawHTTP`/`sawNetworkError` aggregation and final error selection.

Use `DECOMPOSE` around result values rather than copying the three local closures. A suitable shape is a small `ProbeContext(base:client:previousBody:previousSnapshot:)`, a `ProbeFlags` value, and helpers with roles equivalent to `standardAttempt(for:context:) async throws -> AttemptResult`, `record(_:flags:) -> ProbeHit?`, and `probeStatuspal(context:flags:) async throws -> ProbeHit?`. `probeHit` should then only order providers, return the first hit, and map the final flags to `ProbeError`. This also gives the existing six-parameter `probeStatuspal` a coherent context without changing provider semantics.

## Low / Debatable

The following findings are real threshold measurements but are test-only. They are LOW unless a future change makes the test fixtures cross responsibility boundaries.

### loc-003 — Performance benchmark harness file

`Tests/greendotTests/PerformanceHarnessTests.swift:9` has 368 code LOC and 397 physical lines. SwiftLint reports a 355-code-line class body. Its five concerns are parser timings, poll timings, menu build/cache timings, status-dot rendering, and persistence/provider-cache/pulse metrics. These are intentionally grouped behind the `make bench` harness and share benchmark fixtures/output, so splitting solely to meet 300 LOC would add navigation cost. Recommendation: `EXEMPT` for now. If benchmark domains grow, split into `ParserPerformanceTests`, `PollPerformanceTests`, and `MenuAndIconPerformanceTests` with shared `BenchmarkFixtures`.

### loc-004 — `measureRemaining` is one logical line over the function limit

`Tests/greendotTests/PerformanceHarnessTests.swift:189` spans 51 logical body lines (190–244). It measures four independent metrics: Statuspal request count, regex compilation reuse, unchanged-poll parse reuse, and reachable pulse refresh calls. Recommendation: `DECOMPOSE` when this harness is next edited into helpers equivalent to `measureStatuspalProbe() async throws -> Int`, `measureRegexCompilation() -> Int`, `measureSecondPollParseCount() async throws -> Int`, and `measureReachablePulseRefresh() -> Int`; otherwise this one-line test-only overflow is LOW.

### loc-005 — Status page editor integration test suite

`Tests/greendotTests/StatusPageEditorTests.swift:7` has 316 code LOC and 359 physical lines. Three related test concerns account for the size: persistence-failure add/edit flows (lines 17–127), stale/replacement/pending/cancel panel lifecycle (129–248 and 291–320), and view-tree helpers plus `PendingSaveGate` test support (250–288 and 330–359). All tests target the same editor/panel behavior and no individual function exceeds 50 logical lines. Recommendation: `EXEMPT`; if the suite grows, split `StatusPageEditorPersistenceTests`, `StatusPageEditorLifecycleTests`, and `StatusPageEditorTestSupport` rather than cutting by line number.

### loc-006 — Monitor refresh transaction test suite

`Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift:5` has 306 code LOC and 353 physical lines. SwiftLint reports a 301-code-line class body. Three related concerns are covered: persistence/error boundaries (42–68 and 295–312), overlapping/cancelled poll ordering (70–160 and 251–293), and edit/toggle conflict protection plus shared fixtures (162–249 and 314–352). The suite is cohesive around refresh transactions and has no function over 50 logical lines. Recommendation: `EXEMPT`; if it becomes harder to navigate, use `MonitorPollConcurrencyTests`, `MonitorPollMutationTests`, and a shared fixture file.

### Files close to the limit

These files are below 300 code LOC and are not findings. They are listed to prevent premature splitting: `Tests/greendotTests/PanelLifecycleTests.swift` (297), `UITests/GreenDotUITests/GreenDotUITests.swift` (289), `Tests/StatusCoreTests/ProbeAndMonitorTests.swift` (270), and `Tests/StatusCoreTests/PollPerformanceTests.swift` (262). Manual inspection of the UI test found no function over 50 logical lines.

## Recommendations

1. Apply `SPLIT` to `Monitor` using same-type extensions/files first. Preserve the current public API and keep lock ownership in one place; validate persistence failure, cancellation, overlapping poll, and mutation-preservation tests after each move.
2. Apply `DECOMPOSE` to `ProviderProbe.probeHit` with a context/flags value and one standard-provider attempt helper. Keep Statuspal's special discovery path explicit.
3. Treat the three oversized test files as threshold exemptions. Their size comes from cohesive scenario coverage, fixtures, or benchmark aggregation, not a production god object.
4. On the next performance-harness change, apply the optional `measureRemaining` helper extraction. Do not split benchmark files solely to remove one logical line.
5. Keep using cloc code LOC as the audit measure. SwiftLint's default `file_length` metric is not the 300 code-LOC rule, so SwiftLint output alone does not detect `Monitor.swift`.

### Priority ranking

| Rank | Finding | Severity | Action | Reason |
|---:|---|---|---|---|
| 1 | loc-001 | HIGH | SPLIT | Central production type mixes four stateful concerns. |
| 2 | loc-002 | MEDIUM | DECOMPOSE | Provider dispatch and error policy are coupled in a 57-line function. |
| 3 | loc-004 | LOW | DECOMPOSE | Four independent benchmark measurements in a 51-line helper. |
| 4 | loc-003 | LOW | EXEMPT | Intentional multi-metric benchmark harness. |
| 5 | loc-006 | LOW | EXEMPT | Cohesive monitor transaction scenarios and fixtures. |
| 6 | loc-005 | LOW | EXEMPT | Cohesive editor/panel integration scenarios and support. |

## Out of Scope

- No source, test, dependency, configuration, Git, archive, generated-project, resource, or binary files were modified.
- This report does not assess runtime correctness, dead code, duplication, type quality, security, performance results, or formal test validity.
- No lizard-based measurement was possible because lizard is not installed; SwiftLint plus manual boundary inspection was used for function bodies.
- The initial threshold findings were not independent verification or release
  approval. The later independent disposition and final JSON flags below
  supersede that initial state.

## Independent Verification Disposition

The mandatory gate selected 6 of 6 records. Independent verifiers confirmed 6; those records now have `verified: true`. 0 lower-confidence records remain provisional.

Verification evidence: [verification-batch-1.md](verification-batch-1.md), [verification-batch-3.md](verification-batch-3.md).

Final machine-readable severity counts: HIGH 0, MEDIUM 2, LOW 4. The original prose above records the specialist's pre-verification assessment; this disposition and the JSON block below are authoritative after verification.

## Machine-Readable Findings

```json
{"findings":[{"id":"loc-001","file":"Sources/StatusCore/Monitor.swift","line":3,"severity":"MEDIUM","confidence":"CERTAIN","recommendation":"SPLIT","detail":"Monitor combines four stated production concerns in 352 code lines.","verified":true},{"id":"loc-002","file":"Sources/StatusCore/ProviderProbe.swift","line":34,"severity":"MEDIUM","confidence":"CERTAIN","recommendation":"DECOMPOSE","detail":"probeHit is a 57-code-line orchestration/error-selection function with the stated responsibilities.","verified":true},{"id":"loc-003","file":"Tests/greendotTests/PerformanceHarnessTests.swift","line":9,"severity":"LOW","confidence":"CERTAIN","recommendation":"EXEMPT","detail":"Benchmark harness is intentionally grouped; do not split solely for the file threshold.","verified":true},{"id":"loc-004","file":"Tests/greendotTests/PerformanceHarnessTests.swift","line":189,"severity":"LOW","confidence":"CERTAIN","recommendation":"DECOMPOSE","detail":"Optional helper extraction is suitable on the next benchmark edit.","verified":true},{"id":"loc-005","file":"Tests/greendotTests/StatusPageEditorTests.swift","line":7,"severity":"LOW","confidence":"CERTAIN","recommendation":"EXEMPT","detail":"Related editor integration tests may remain together below a future navigation threshold.","verified":true},{"id":"loc-006","file":"Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift","line":5,"severity":"LOW","confidence":"CERTAIN","recommendation":"EXEMPT","detail":"Cohesive monitor transaction tests may remain together as a low-risk exception.","verified":true}]}
```
