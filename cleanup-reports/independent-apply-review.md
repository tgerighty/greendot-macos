APPROVE

## Findings

No actionable P0-P3 findings were found in the applied implementation. The
fresh review did not identify a runtime regression, an unsafe provider fallback,
an invalid Monitor transaction, an AppKit lifetime failure, or an accidental
application of a skipped finding.

The main residual coverage gap is the private `AppDelegate.openEditor` path
(`Sources/greendot/AppDelegate.swift:190-214`). The retained-editor and
next-run-loop workaround is supported by history and by the direct
`StatusPageEditor` replacement tests, but it is not called through the
AppDelegate menu wiring in a test. This is the explicitly unverified
`legacy-001` item and was not changed as a behavior change. A future UI or
AppDelegate-level lifecycle test should exercise repeated Add/Edit replacement
through the real menu action before changing that workaround.

## Scope and method

I reviewed the complete implementation range
`310032baadea24dd7ea32a97ddc5af8df9a52845..9c5b4f2d97c062f602f09c3f9654578c1711ae49`,
including all intermediate cleanup merges. I inspected the source and test
diff, the commit history, the assessment records, RED/GREEN evidence, and all
apply logs. I also compared the final changed paths with the verified and
approved allowlists. The review was read-only except for this report.

## Checks

- `swift test`: PASS, 163 tests executed, 1 intentional benchmark test skipped,
  0 failures.
- `swift build -Xswiftc -swift-version -Xswiftc 6`: PASS.
- `swift build -Xswiftc -warn-concurrency`: PASS.
- `make bench`: PASS. The run confirmed three-page polling overlap, three
  requests for known providers, zero parses on an unchanged second poll, zero
  unchanged config rewrites, one cached menu object, one regex compilation,
  and no reachable-page pulse refreshes.
- `git diff --check -- Sources Tests`: PASS.
- `swiftlint lint --strict --reporter json`: exit 2 because strict mode promotes
  warnings. The JSON contained 8 Warning findings and 0 serious findings, all
  in test or benchmark files (`MonitorRefreshTransactionTests` and
  `PerformanceHarnessTests`); no production-source lint finding was reported.
  These were outside the cleanup scope.
- UI tests were not run. `UITests/GreenDotUITests.xcodeproj` is not present in
  this worktree; generating it with `xcodegen` would create an artifact during
  this read-only review. AppKit lifecycle unit tests did run in `swift test`.

## Applied and skipped gate

The source and test changes match the verified/approved records:

- `dead-001`: only the unused `BuildInfo.gitHash` property was removed.
- `types-001`, `types-002`, `types-004`, `types-005`, `types-006`, and
  `types-007`: parser error placement, test-double placement, severity text,
  probe result typing, scheduler typing, and the non-NSObject menu controller
  cleanup were applied without production behavior drift.
- `dedup-002`, `dedup-003`, `dedup-005`, and `dedup-008` were test-support
  moves; `dedup-001` was already resolved by the severity change.
- `loc-001`, `loc-002`, and `loc-004` split Monitor, ProviderProbe, and the
  benchmark helper while preserving their behavior.
- `defensive-001`, `defensive-006`, `defensive-010`, and serial
  `defensive-015` are the applied behavior fixes. Their direct regression
  tests pass.
- `typing-001`, `typing-003`, `typing-005`, `typing-006`, `typing-007`, and
  `typing-008` are the applied parser/AppKit isolation changes. The strict
  Swift 6 build passes.

The skipped or review-only records were not accidentally changed. In
particular, parser missing-status defaults (`defensive-002`), PageStore atomic
write handling (`defensive-003`), broad poll-error policy (`defensive-004`),
stale-component policy (`defensive-005`), launch-at-login failure reporting
(`defensive-007`), notification completion handling (`defensive-009`), URL
scheme validation (`defensive-011`), parser diagnostics (`defensive-013`),
regex initialization review (`defensive-014`), and `legacy-001` remain
unchanged. The unverified type, deduplication, circular-dependency, and
AI-slop records also remain unchanged.

## Important invariants that held

- `Monitor` still takes the transition lock before state access and persistence.
  Poll identity and per-page input revisions reject stale overlapping results;
  cancellation is checked before the commit boundary; failed saves leave the
  in-memory and persisted configuration unchanged. The transaction tests cover
  overlapping polls, cancellation while waiting for the lock, toggles during a
  request, edit/remove races, and late completions
  (`Tests/StatusCoreTests/MonitorRefreshTransactionTests.swift:70-312`).
- Polling still probes pages concurrently, retains preferred-provider fallback,
  reuses an unchanged body only for a reachable prior snapshot, and propagates
  cancellation. HTTP status 0, 429, and 500-599 now classify as unreachable;
  404 remains an unsupported/provider miss. The provider and performance tests
  exercise these paths (`Sources/StatusCore/ProviderProbe.swift:34-228`,
  `Tests/StatusCoreTests/ProbeAndMonitorTests.swift:263-309`).
- Missing snapshots and unreachable snapshots stay grey; empty component lists
  use the page-level overall status; a non-empty all-disabled selection remains
  green by user choice (`Sources/StatusCore/Models.swift:123-132`). Toast
  severity is calculated from the same display policy and the persistence/error
  gate resets only for the latest successful refresh
  (`Sources/StatusCore/Monitor+Polling.swift:87-180`,
  `Sources/greendot/AppDelegate.swift:278-303`).
- MainActor isolation covers AppKit state, StatusDot caching, notification
  presentation, timer hops, and NSObject initializers. Weak callback captures,
  generation checks, delegate clearing, event-monitor cleanup, and panel
  release tests remain in place.
- Parser grouping keeps input order while removing the force unwrap; provider
  parser errors remain shared and internal. Test HTTP clients and benchmark
  helpers are in `Tests/TestSupport`, not the production `StatusCore` target.

## Conclusion

The cleanup implementation is approved for this gate. The approval is for the
reviewed development/readiness change set, not formal product validation. The
AppDelegate editor wiring and generated UI test project should be covered in a
later UI validation pass before release claims depend on them.
