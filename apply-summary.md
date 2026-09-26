# Greendot CBA nine-domain apply summary

Base: `9320756a8a8bfdacbc4d45aad53ed1591513a12e` (`origin/main`). Branch: `rig/cba-apply-9domain-20260926`.

Applied safe findings from five domains: dead code, AI slop, deduplication, weak typing, and defensive programming. The other four domains were considered and had only KEEP, REVIEW, EXEMPT, or conditional work. The [per-finding apply log](cleanup-reports/rig-cba-9domain-apply-log.md) records every applied item and skip reason.

Commits: `38d5574` subtractive cleanup; `9acbb11` structural reuse; `4349f6a`, `ab4b257`, and `5fd4336` failing parser boundary tests; `72c394e`, `e933c51`, and `7f9475f` parser fixes; `3c6c678` source assessments.

Tests: 494 passed at baseline. Eight new parser tests reproduced 17 assertion failures on the old behavior. The final macOS `swift test --parallel` run passed all 502 tests and compiled every target. `git diff --check` passed. An independent review found no remaining concrete issue in changed paths. SwiftLint was unavailable on the test hosts; Sonar PR analysis will check it.

Known remaining work: the deliberate Icinga TLS exception needs a compatibility plan; rollback and permission failure reporting need testable fault paths; optional file splits and shared fixtures can wait for related maintenance. No merge or deployment was done.
