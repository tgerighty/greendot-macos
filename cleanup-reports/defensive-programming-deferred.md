# Defensive programming deferred work

Branch: `cleanup/apply-20260826-defensive`

## defensive-015

Status: DEFERRED.

`Sources/StatusCore/ProviderProbe.swift` is fully owned by the LOC-limits agent in this phase. The defensive agent did not edit that file or its tests. This is a file-ownership deferral, not a finding rejection.

Catch-up action after the LOC-limits branch is merged:

1. Start a fresh serial worktree from the merged branch.
2. Add RED tests in `Tests/StatusCoreTests/ProbeAndMonitorTests.swift` for HTTP 429 and a representative 5xx response. Assert that provider probing reports `ProbeError.unreachable`, not `ProbeError.unsupported`, while 404 remains a provider miss.
3. Commit the failing tests as `[TEST]` and record the targeted failures.
4. Update `Sources/StatusCore/ProviderProbe.swift` so 429 and 5xx are reachability failures, while 404 and other provider-mismatch responses remain misses.
5. Run the focused tests, `swift build`, and full `swift test`; commit the implementation as `[FIX]` only when all pass.
6. Add the RED/GREEN SHAs and the evidence to the next defensive-programming apply log.

No part of defensive-015 was implemented on this branch.
