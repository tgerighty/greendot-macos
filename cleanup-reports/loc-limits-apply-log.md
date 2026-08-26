# LOC limits apply log

Date: 2026-08-26
Branch: `cleanup/apply-20260826-loc`
Starting commit: `b7769c73d6f5c7018aa7c37bef1a26d8a488b22e`

## Scope and RED baseline

The worktree was clean before the baseline checks. The six records in
`loc-limits-assessment.md` were independently verified. Three records were
applied and three records were kept unchanged as approved exemptions:

- Applied: `loc-001`, `loc-002`, and `loc-004`.
- Unchanged exemptions: `loc-003`, `loc-005`, and `loc-006`.
- Deferred items: none. No deferred file was created.
- Characterisation tests: none added. Existing tests directly cover Monitor
  mutations and polling, provider probing, and the benchmark harness.

The required empty RED commit is:

`8736bbd30b182a12020bbb56f1146a6cc54785b9` — `[TEST] Confirm LOC cleanup baseline`

Fresh baseline commands and results:

| Command | Result |
|---|---|
| `swift build` | Pass. |
| `swift test` | Pass. 150 tests, 1 skipped, 0 failures. |
| `make bench` | Pass. The harness emitted all expected `BENCH` metrics. |
| `swiftlint lint --quiet --config .swiftlint.yml --reporter json` | Exit 0. 11 existing warnings. Function diagnostics included `ProviderProbe.probeHit` body 57 lines, `probeStatuspal` 6 parameters, and `measureRemaining` body 51 lines. |
| `cloc --by-file --include-lang=Swift --exclude-dir=.git,.build,greendot.app,cleanup-reports . --csv` | Pass. 6,591 code lines, 750 blank lines, and 41 comment lines. |

The physical-line baseline was measured from the clean RED commit with the
Swift files under `Sources`, `Tests`, and `UITests`, plus `Package.swift`:
7,383 physical lines.

## Applied items

### loc-001 — split `Monitor`

Files changed:

- `Sources/StatusCore/Monitor.swift` retains stored state, initialisers,
  `pages`, `withStateLock`, and lock primitives.
- `Sources/StatusCore/Monitor+Mutations.swift` contains page loading and
  mutation methods.
- `Sources/StatusCore/Monitor+Polling.swift` contains polling, stale-result
  reconciliation, persistence, and toast handling.
- `Sources/StatusCore/Monitor+Presentation.swift` contains severity methods.

The public API, lock order, cancellation checks, persistence order, poll
identity and revision checks, previous-body reuse, toast rules, and callback
behaviour were retained. No actor or new behaviour was introduced. State
members used by same-type extensions are module-internal only; no new public
member was added.

GREEN commits and checks:

- `49b293f1089d0c7a1cf4753aa1d4555f9bb3bb8a` — `[CLEANUP] Apply loc-001 Monitor split`.
- `de280febfc8ac07f9f2778435f42a6ddc7c693a7` — `[CLEANUP] Keep Monitor lock helper with state` (correction to keep `withStateLock` in `Monitor.swift`).
- After the split and correction: `git diff --check`, `swift build`, and
  `swift test` passed. The full test result was 150 tests, 1 skipped, and 0
  failures.

### loc-002 — decompose `ProviderProbe.probeHit`

`Sources/StatusCore/ProviderProbe.swift` now uses `ProbeContext`,
`ProbeFlags`, `standardAttempt`, and result recording helpers. Provider order,
URL paths, parser attempts, cancellation, previous-body reuse, Statuspal HTML
discovery, HTTP status classification, and final error precedence are
unchanged. Defensive finding `defensive-015` was not implemented in this
branch.

GREEN commit and checks:

- `1c901ce430352114d32904dd1d760abb14f45f50` — `[CLEANUP] Apply loc-002 probe decomposition`.
- After the change: `git diff --check`, `swift build`, and `swift test`
  passed. The full test result was 150 tests, 1 skipped, and 0 failures.

### loc-004 — split `measureRemaining`

`Tests/greendotTests/PerformanceHarnessTests.swift` now calls four focused
helpers equivalent to the report: `measureStatuspalProbe`,
`measureRegexCompilation`, `measureSecondPollParseCount`, and
`measureReachablePulseRefresh`. The measurement order, count resets, fixture
data, metric names, and returned values were retained.

GREEN commit and checks:

- `e95fe20095bf3de1a5a06863dae17f8bbd2ba798` — `[CLEANUP] Apply loc-004 benchmark helper split`.
- `GREENDOT_BENCH=1 swift test --filter PerformanceHarnessTests` passed.
- `swift build` passed.
- `swift test` passed: 150 tests, 1 skipped, and 0 failures.
- `make bench` passed. Observed output values were:

  ```text
  BENCH parse_statuspage_ms=39.554
  BENCH parse_instatus_ms=2.109
  BENCH parse_statuspal_ms=3.934
  BENCH pollAll_3page_delay_ms=87.250
  BENCH pollAll_3page_delay_expected_sequential_ms=240.000
  BENCH pollAll_3page_get_count=3
  BENCH pollAll_mixed_get_count=3
  BENCH menu_build_ms=25.544
  BENCH menu_build_cached_ms=0.204
  BENCH status_dot_ms=0.383
  BENCH status_dot_unique_images=4
  BENCH store_save_ms=50.837
  BENCH pollAll_unchanged_config_rewrites=0
  BENCH statuspal_first_probe_gets=3
  BENCH menu_unique_objects=1
  BENCH statuspal_regex_compiles=1
  BENCH poll_second_parse_count=0
  BENCH pulse_refresh_when_reachable=0
  ```

## LOC and function diagnostics

Code LOC is from `cloc` 2.10. Physical LOC is `wc -l`. For the split
`Monitor`, the after value is the sum of its four same-type extension files.

| Scope | Before code / physical | After code / physical | Change |
|---|---:|---:|---:|
| `Monitor` plus three extension files | 352 / 384 | 359 / 390 | +7 / +6 |
| `ProviderProbe.swift` | 245 / 270 | 247 / 272 | +2 / +2 |
| `PerformanceHarnessTests.swift` | 348 / 375 | 358 / 385 | +10 / +10 |
| Exempt `StatusPageEditorTests.swift` | 313 / 357 | 313 / 357 | 0 / 0 |
| Exempt `MonitorRefreshTransactionTests.swift` | 306 / 353 | 306 / 353 | 0 / 0 |
| Full audited scope, including `Package.swift` | 6,591 / 7,383 | 6,610 / 7,401 | +19 / +18 |

Final `cloc --by-file` values for the changed files:

```text
Sources/StatusCore/Monitor.swift                29 code
Sources/StatusCore/Monitor+Mutations.swift     134 code
Sources/StatusCore/Monitor+Polling.swift       179 code
Sources/StatusCore/Monitor+Presentation.swift   17 code
Sources/StatusCore/ProviderProbe.swift         247 code
Tests/greendotTests/PerformanceHarnessTests.swift 358 code
```

The final SwiftLint JSON command exited 0 with 8 existing warnings. The
remaining warnings are the exempt monitor transaction type body, benchmark
`for_where`, benchmark identifier `ms`, three benchmark large tuples, one
benchmark line-length warning, and the benchmark type body. There are no
remaining `function_body_length` or `function_parameter_count` diagnostics.
Therefore the baseline diagnostics for `probeHit` (57 body lines),
`probeStatuspal` (6 parameters), and `measureRemaining` (51 body lines) are
resolved without changing the exempt records.

## Final controls

- Final SwiftLint JSON: pass, 8 warnings, no function-body or parameter-count
  diagnostics.
- Final cloc by file: pass; totals recorded above.
- Final `git diff --check`: pass.
- Applied count: 3.
- Skipped/exempt count: 3 (`loc-003`, `loc-005`, `loc-006`).
- Deferred count: 0.
- The branch contains no changes outside the strict allowlist.
