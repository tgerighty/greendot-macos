# Codebase Cleanup Analysis — Verified Summary

Audit date: 2026-08-25  
Repository state: `main` at `310032b`  
Scope: read-only architecture and cleanup analysis

## Outcome

The audit found 93 candidate records across nine specialist assessments. The mandatory gate selected every HIGH or CERTAIN record for a fresh-context adversarial review.

- Final severity: 5 HIGH, 26 MEDIUM, 62 LOW.
- Verification: 54 verified and 39 provisional.
- Gate result: 57 reviewed, 54 survived, and 3 were partial.
- The three partial claims were narrowed to `UNCERTAIN` / `REVIEW`: `legacy-001`, `defensive-022`, and `typing-002`.
- No unverified HIGH or CERTAIN record remains.
- No source, test, dependency, or configuration file was changed.

The specialist reports first proposed 5 HIGH, 31 MEDIUM, and 57 LOW records. Verification corrected the severity. Three duplication findings moved from HIGH to LOW, the `Monitor` size finding moved from HIGH to MEDIUM, and four strict Swift 6 isolation findings moved from MEDIUM to HIGH.

The current Swift 5.9 build and test suite pass. The four Swift concurrency HIGH findings are forward-compatibility blockers found by a strict Swift 6 build; they are not failures in the current Swift 5.9 build.

## Top 10 Verified Actions

| Rank | Finding | Severity | Why it matters | Recommended action |
|---:|---|---|---|---|
| 1 | `defensive-001` | HIGH | Missing data and all-disabled components become green; page-level red can be hidden and a toast can be suppressed. | Define explicit absent-data, all-disabled, and page-overall rules. Add red-page regression tests first. |
| 2 | `defensive-015` | MEDIUM | HTTP 5xx and 429 can be reported as an unsupported provider instead of an unreachable service. | Separate provider misses from server and rate-limit failures. |
| 3 | `typing-006` | HIGH | `AppDelegate` has strict Swift 6 actor and sendability errors. | Add a consistent `@MainActor` boundary and actor-aware callback types. |
| 4 | `typing-007` | HIGH | `PagePanelController` creates and uses AppKit state without explicit main-actor isolation. | Isolate the controller and its UI callbacks on `MainActor`. |
| 5 | `typing-008` | HIGH | Several AppKit helpers have missing actor boundaries; some are strict-build errors. | Isolate the listed helpers as one reviewed UI-concurrency change. |
| 6 | `typing-005` | HIGH | The locked global `NSImage` cache is still rejected by strict Swift 6 checking. | Put cache access on `MainActor` or use another compiler-checkable design. |
| 7 | `loc-001` | MEDIUM | The 352-code-line `Monitor` combines synchronization, persistence, polling, merge, and presentation policy. | Split behavior behind focused boundaries after correctness tests are in place. |
| 8 | `loc-002` | MEDIUM | The 57-code-line `probeHit` mixes provider ordering, attempts, discovery, and final error selection. | Separate attempt results and HTTP/error classification from orchestration. |
| 9 | `defensive-010` | MEDIUM | Zero, negative, NaN, and infinite poll intervals bypass the 60-second fallback. | Accept finite positive values only. |
| 10 | `defensive-006` | MEDIUM | First-run seed probe and persistence errors are fully discarded. | Keep startup non-blocking, but log or show a non-fatal failure. |

`defensive-014` is the next verified medium action. Keep regex compilation fail-closed, but add an explicit diagnostic for a source-pattern error. Do not replace it with an unchecked force unwrap.

## Assessment Roll-up

| Assessment | Total | HIGH | MEDIUM | LOW | Verified | Provisional |
|---|---:|---:|---:|---:|---:|---:|
| [AI slop](ai-slop-assessment.md) | 3 | 0 | 0 | 3 | 0 | 3 |
| [Circular dependencies](circular-deps-assessment.md) | 4 | 0 | 1 | 3 | 2 | 2 |
| [Dead code](dead-code-assessment.md) | 6 | 0 | 3 | 3 | 1 | 5 |
| [Deduplication](deduplication-assessment.md) | 11 | 0 | 3 | 8 | 5 | 6 |
| [Defensive programming](defensive-programming-assessment.md) | 27 | 1 | 10 | 16 | 16 | 11 |
| [Legacy code](legacy-code-assessment.md) | 5 | 0 | 4 | 1 | 3 | 2 |
| [LOC limits](loc-limits-assessment.md) | 6 | 0 | 2 | 4 | 6 | 0 |
| [Type consolidation](type-consolidation-assessment.md) | 9 | 0 | 1 | 8 | 6 | 3 |
| [Weak typing](weak-typing-assessment.md) | 22 | 4 | 2 | 16 | 15 | 7 |
| **Total** | **93** | **5** | **26** | **62** | **54** | **39** |

The 39 provisional records did not pass through the mandatory gate because they were neither HIGH nor CERTAIN after specialist assessment, or because an independent verifier found the original claim partial. They are candidates for later review, not confirmed cleanup work.

## Overlaps and Conflict Dispositions

- `dedup-001` and `types-004` are one change: centralize baseline `Severity` display text and keep unreachable and Statuspal maintenance exceptions outside that mapping.
- `types-002` overlaps `dead-002` to `dead-004`. Treat it as one move of test-only HTTP clients from `StatusCore` to `TestSupport`. The verified type-boundary record is authoritative; do not count four removals.
- `defensive-001` overlaps `types-003` and `defensive-005`. Make one explicit page-display state decision before changing persistence or unreachable behavior.
- `typing-005` to `typing-008` form one AppKit isolation programme. Preserve the verified weak callback edges in `circular-002` and `circular-003`, and preserve the deferred editor replacement described by `legacy-001` until its exact AppDelegate path has direct coverage.
- `loc-001` overlaps `circular-001`, `dedup-004`, `defensive-004`, `defensive-007`, `defensive-019`, and `typing-009`. Fix and test behavior first; then split `Monitor` without moving lock ownership in the same step.
- `typing-001` and `defensive-025` are compatible. The current `groupID!` is proven safe by the preceding filter; `compactMap` is an optional readability and invariant-strengthening cleanup, not a current crash fix.
- `defensive-014` and `typing-017` express two sides of one regex policy. Keep optional fail-closed behavior, add a diagnostic or explicit checked initialization, and avoid a startup force failure.
- `defensive-006` overlaps `typing-012`; `defensive-021` overlaps `typing-021`; `defensive-023` overlaps `typing-022` and `legacy-002`/`legacy-003`. Apply each cluster once and retain compatibility defaults and best-effort diagnostic boundaries.

## Estimated LOC Effect

These are planning estimates, not implementation commitments.

| Change class | Estimated repository effect | Notes |
|---|---:|---|
| Verified mechanical cleanup | 35–55 fewer code lines | Shared labels and test helpers, unused property removal, smaller type wrappers, and typed test invocation. |
| Move test HTTP clients to `TestSupport` | About 51 fewer production code lines; near-zero repository net | This improves the shipped target boundary but mostly moves code. |
| `Monitor` and `ProviderProbe` decomposition | About -10 to +30 code lines | The goal is separation, not line deletion. New boundary types may add small overhead. |
| Runtime and Swift 6 fixes with regression tests | About 60–120 added code lines | Most added lines should be tests and explicit state/error handling. |

The likely net repository change is small or positive after tests. The useful outcome is lower production coupling and clearer failure states, not a large line-count reduction.

## Recommended Remediation Order

1. Add characterization tests and fix `defensive-001` and `defensive-015`. These affect displayed health and provider error meaning.
2. Validate poll configuration and report optional seed/regex failures (`defensive-010`, `defensive-006`, `defensive-014`).
3. Apply the AppKit `MainActor` boundary (`typing-005` to `typing-008`). Require both the current build and a strict Swift 6 build to pass before completion.
4. Decompose `ProviderProbe.probeHit`, then split `Monitor` along mutation, polling, and presentation boundaries. Preserve locks, poll identity, revision checks, and the deferred editor lifetime workaround.
5. Move test-only HTTP clients to `TestSupport`; centralize benchmark helpers and severity display text.
6. Apply the remaining verified low-risk cleanups: the unused `BuildInfo.gitHash` property, shared parser error location, `ProbeHit` payload consolidation, duplicate type alias, unnecessary `NSObject` inheritance, and typed test invocation.
7. Review provisional records only when their owning area is already changing. Do not present them as confirmed debt.

## Verification Evidence

- [Verification batch 1](verification-batch-1.md): 17 survived, 1 partial.
- [Verification batch 2](verification-batch-2.md): 18 survived, 1 partial.
- [Verification batch 3](verification-batch-3.md): 19 survived, 1 partial.
- Fresh final `swift build`: passed.
- Fresh final `swift test`: 150 tests passed, 1 benchmark test skipped by its environment gate, and 0 failed.
- Fresh strict Swift 6 build: failed with the actor-isolation and shared-state diagnostics recorded by `typing-005` to `typing-008`. This is a confirmed migration gap, not a current Swift 5.9 build failure.
- Fresh SwiftLint baseline: 11 findings, comprising 10 warnings and 1 error. The production findings include the 57-line `probeHit` function and its six-parameter helper; the remaining size/style findings are in tests. This audit does not claim a clean lint baseline.
- Current code baseline: 6,581 Swift code lines under `Sources`, `Tests`, and `UITests`; `Package.swift` adds 25 code lines, for 6,606 in the audited Swift/package scope.
- The generated UI project, `.build`, `.git`, `greendot.app`, and report material were excluded from source metrics.

## Boundaries

This is a cleanup and architecture assessment. It is not a release approval or formal validation result. It does not change runtime behavior. The earlier report pack was preserved under `cleanup-reports/archive-20260825-2206/`.
