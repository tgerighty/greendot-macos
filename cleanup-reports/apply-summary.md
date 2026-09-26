# Cleanup apply summary

- Date: 2026-08-26
- Branch: `cleanup/apply-20260826`
- Assessment base: `310032baadea24dd7ea32a97ddc5af8df9a52845`
- Assessment report commit: `9141e8b`
- Last cleanup product-code merge: `9c5b4f2`
- Independent-review merge: `2dfa293`
- PR review product fix: `70b8ec0`
- Final local test cleanup: `7a38b01`
- Delivery: GitHub pull request #15

## Decision

**APPROVE for the cleanup development/readiness gate.**

The approved and verified cleanup work is applied. The independent verifier
found no actionable P0-P3 issue in the original apply range. The PR review
later found one concurrency race; a deterministic RED test reproduced it and
the GREEN fix passed independent review. The normal build, full Swift test
suite, strict Swift 6 build, concurrency-warning build, benchmark suite, and
strict lint gate pass on the final local branch. The release app is rebuilt
after this report commit so its embedded revision matches the submitted head.

This is not formal product validation or a release approval. The macOS UI test
runner initially met a system authentication block, but a fresh final run
executed all 17 UI tests with no failure. PR service results and their limits
are recorded below; the live status on PR #15 is authoritative for the latest
pushed head.

## Outcome

The assessment contained 93 rows:

| Disposition | Count | Meaning |
|---|---:|---|
| APPLIED | 24 | Verified and approved change implemented |
| RESOLVED-UPSTREAM | 1 | Same action completed by an applied overlapping item |
| SKIPPED | 36 | Not approved, not verified, manual review, or no safe change |
| KEEP | 32 | Existing code is justified and retained |
| Open DEFERRED | 0 | No approved implementation remains deferred |

Overlapping records normalize to 89 unique actions: 24 applied, 33
skipped/manual actions, and 32 kept actions. The overlaps are `dedup-001` with
`types-004`, and `types-002` with `dead-002` to `dead-004`.

Thirty-nine assessment records retain a provisional or non-verified state.
They were not treated as approved work. `defensive-014` is verified but still
requires a manual decision, so it was not changed. `legacy-001` also retains
its exact AppDelegate editor-wiring test gap.

## Disposition matrix

| Area | Applied | Resolved upstream | Skipped | Keep |
|---|---|---|---|---|
| AI slop | — | — | `slop-001` to `slop-003` | — |
| Circular dependencies | — | — | `circular-001` | `circular-002` to `circular-004` |
| Dead code | `dead-001` | — | `dead-002` to `dead-006` | — |
| Deduplication | `dedup-002`, `dedup-003`, `dedup-005`, `dedup-008` | `dedup-001` | `dedup-004`, `dedup-006`, `dedup-011` | `dedup-007`, `dedup-009`, `dedup-010` |
| Defensive programming | `defensive-001`, `defensive-006`, `defensive-010`, `defensive-015` | — | `defensive-002` to `defensive-005`, `defensive-007` to `defensive-009`, `defensive-011` to `defensive-014`, `defensive-022` | `defensive-016` to `defensive-021`, `defensive-023` to `defensive-027` |
| Legacy code | — | — | `legacy-001`, `legacy-005` | `legacy-002` to `legacy-004` |
| LOC limits | `loc-001`, `loc-002`, `loc-004` | — | — | `loc-003`, `loc-005`, `loc-006` |
| Type consolidation | `types-001`, `types-002`, `types-004` to `types-007` | — | `types-003`, `types-008`, `types-009` | — |
| Weak typing | `typing-001`, `typing-003`, `typing-005` to `typing-008` | — | `typing-002`, `typing-004`, `typing-009` to `typing-013` | `typing-014` to `typing-022` |

## Applied changes

- Removed only the unused `BuildInfo.gitHash` property.
- Moved parser errors, test doubles, benchmark fixtures, and persistence test
  support to shared, typed locations.
- Added typed severity display text and typed provider probe results.
- Split `Monitor`, `ProviderProbe`, and the benchmark helper into focused files
  without changing their public behavior.
- Preserved Monitor locking, stale-result rejection, cancellation, save
  rollback, provider fallback, and unchanged-response reuse.
- Classified HTTP status 0, 429, and 500 to 599 as unreachable while keeping
  404 as an unsupported provider result. A final reachability failure now wins
  over later provider misses.
- Removed unsafe parser and AppKit weak-typing paths. AppKit state and callbacks
  now use explicit MainActor boundaries that pass strict Swift 6 checking.

No production behavior was changed to hide an assessment mismatch. All
unapproved or unverified behavior findings remain visible in their assessment
records.

## RED and GREEN evidence

| Work | RED evidence | GREEN evidence |
|---|---|---|
| Dead code | `4657aaa` | `b2698a8` |
| Type consolidation | `b5ea6db` | `f81e062`, `e1a8e7f`, `1fedc1a`, `516c2d2`, `cd80e39` |
| Deduplication | `65f43d8` | `9bcc849`, `f0e0a7d`, `3f07ee0`; overlap completed by `1fedc1a` |
| LOC decomposition | `8736bbd` | `49b293f`, `de280fe`, `1c901ce`, `e95fe20` |
| Defensive 001 | `f43cdd2` | `5c28959` |
| Defensive 006 | `2637421` | `d3d4580` |
| Defensive 010 | `c408a6c` | `0f3c31c` |
| Defensive 015 | `9bb3bd0` | `4ffc364` |
| Weak typing, initial | `c9d6465` | `6fb3b0e`, `e0544f8`, `e59ddaa`, `75b569b`, `461c2e7` |
| Weak typing, serial catch-up | `14a513f` | `336dd91` |
| Concurrent first-run launch-at-login | `b80b782` | `c02efef` |

AI-slop, circular-dependency, and legacy-code review did not produce an
approved implementation, so no implementation RED/GREEN pair was created for
those areas.

## Machine evidence

| Check | Baseline | Final local branch | Result |
|---|---:|---:|---|
| `swift build` | PASS | PASS | PASS |
| `swift test` | 150 tests, 1 skip, 0 failures | 164 tests, 1 intentional skip, 0 failures | PASS |
| Strict Swift 6 build | FAIL with AppKit/MainActor diagnostics | PASS with no warning or error output | Improved |
| Concurrency-warning build | PASS with warnings | PASS with no warning or error output | Improved |
| `swiftlint lint --strict` | 11 findings: 10 Warning, 1 Error | 0 findings | PASS |
| Swift source files | 59 | 68 | +9 |
| Swift code LOC | 6,606 | 6,919 | +313 |
| `make bench` | Not used for comparison | 1 test passed | PASS |
| `make uitest` | Not used for comparison | 17 tests, 0 failures | PASS |
| `git diff --check` | — | No whitespace error | PASS |
| Release app and signing | — | `make app`, strict codesign, and plist lint pass | PASS |

The source, tests, resources, package, Makefile, README, and CodeRabbit
configuration range contains 40 changed files, 1,072 insertions, and 712
deletions. The LOC increase is mainly
the new regression tests, shared test support, and decomposition files. It is
not hidden as a net reduction.

Final benchmark observations:

- Statuspage parse: 39.348 ms.
- Instatus parse: 2.108 ms.
- Statuspal parse: 3.857 ms.
- Three delayed pages completed in 85.413 ms against a 240 ms sequential
  reference.
- Three known-provider requests were made.
- Unchanged configuration rewrites: 0.
- Cached menu objects: 1.
- Regex compilations: 1.
- Second unchanged parse count: 0.
- Reachable-page pulse refreshes: 0.

The eight previous test and benchmark lint warnings were resolved without rule
suppressions. Small result types replaced three-value tuples, long test bodies
were split into focused extensions, and the remaining loop, name, and line
findings were corrected.

## Independent review

The independent verifier returned **APPROVE** with no actionable P0-P3
finding in the original apply range. It independently ran the 163-test suite,
strict Swift 6 compilation, concurrency-warning compilation, benchmarks, diff
checks, and a source/test scope review. A later independent PR review confirmed
the first-run race, reproduced the RED failure, and approved the GREEN locking
fix. The final main gate ran 164 package tests and 17 UI tests. See
`cleanup-reports/independent-apply-review.md`.

The reviewer retained two limits:

- The private `AppDelegate.openEditor` path is not exercised through exact menu
  wiring. This is the unchanged `legacy-001` gap.
- The reviewer did not run the generated UI test project. The main gate later
  attempted it and recorded the system authentication block below.

## External and environment gates

### macOS UI tests: PASS

The earlier environment block cleared without changing application permissions.
A fresh `make uitest` built and signed the application and UI test runner, then
executed all 17 UI tests. All 17 passed with no failure in 112.278 seconds.

### Pull request services

Sonar analysed PR #15 at `18af455`: the quality gate passed with 0 bugs, 0
vulnerabilities, 0 code smells, 0 security hotspots, and 0.0% duplicated new
lines. Earlier Sonar URL-literal findings were reduced from eight to zero by
`c237837` and `18af455`. The final pushed head must retain those zero values.

CodeRabbit completed its full review at `18af455` and posted 12 actionable
comments. The report-integrity items are corrected by `b4eb6a8`; the real
first-run race has RED `b80b782` and GREEN `c02efef`. Its generic 80% docstring
warning did not match this Swift codebase's policy, so `.coderabbit.yaml`
disables that pre-merge check instead of adding low-value comments to internal
and test functions. Gitar approved the reviewed head, and both Socket checks
passed.

Dependabot returned no open alerts. GitHub CodeQL is not enabled for this
repository, so its API returned 403; this is recorded as not configured, not
as a clean CodeQL scan. No GitHub Actions workflow is configured for this
branch.

## Open human decisions

There is no open approved cleanup implementation. The remaining human items
are review or validation work:

- Decide `defensive-014` after manual regex-initialization review.
- Add exact AppDelegate menu-wiring coverage for `legacy-001` before changing
  the retained-editor workaround.

## Delivery

All cleanup branches used for this apply run were merged through Worktrunk.
The delivery branch is submitted as GitHub PR #15. The rebuilt `greendot.app`
records the final short commit in `GitCommitHash`. The remote PR checks and
review threads determine merge readiness; this report does not merge the PR.
