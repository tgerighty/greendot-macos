# Defensive programming deferred work

Branch: `cleanup/apply-20260826-defensive-catchup`

## defensive-015

Status: APPLIED and closed in the serial catch-up.

The original phase deferred this verified item because
`Sources/StatusCore/ProviderProbe.swift` was owned by the LOC-limits agent. The
catch-up started from merged base `ed38cde` and used the allowlist:

- `Sources/StatusCore/ProviderProbe.swift`
- `Tests/StatusCoreTests/ProbeAndMonitorTests.swift`
- `cleanup-reports/defensive-programming-apply-log.md`
- `cleanup-reports/defensive-programming-deferred.md`

RED commit: `9bb3bd08f5d07f941c25716e0cc08cd05ae9ae0e`
(`[TEST] RED classify HTTP reachability failures`).

The RED tests cover HTTP 429, representative 5xx (503), status 0, a Statuspal
discovery 503, and a 404 unsupported control. The focused RED run executed 5
tests: the 404 control passed and the four reachability tests failed because
the pre-fix implementation returned `ProbeError.unsupported`.

GREEN commit: `4ffc3649b745c5d1fb91a874bdd236b1696ea61e`
(`[GREEN] classify HTTP reachability failures`).

`ProviderProbe` now classifies status 0, 429, and 500...599 as
`.networkError` for standard requests and Statuspal discovery. A reachability
failure wins over provider misses; 404 remains unsupported. Provider order,
fallback parsing, cancellation propagation, known-provider optimization, and
the LOC decomposition are unchanged.

Verification:

- Focused probe/performance tests: 33 passed.
- `swift build`: passed.
- Full `swift test`: 163 passed, 1 intentional skip, 0 failures.
- `swiftlint lint --reporter json`: exit 0; 8 warnings and 0 serious findings.
- `git diff --check`: passed.

No further deferred defensive-programming catch-up remains.
