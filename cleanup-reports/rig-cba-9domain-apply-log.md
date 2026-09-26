# Rig CBA nine-domain apply log — 2026-09-26

Source: the nine current `*-assessment.md` files at base `9320756a8a8bfdacbc4d45aad53ed1591513a12e`. All findings were checked against that tip. The source reports had uncommitted edits when work began; commit `3c6c678` records them without alteration.

## Applied

| Finding | Change | RED / GREEN evidence |
| --- | --- | --- |
| dead-001 | Removed unread toast start counter. | Baseline 494 tests pass; `38d5574` passes 494 tests. |
| ai-slop-001–004 | Removed scalar aliases, XML decoder wrapper, needless Foundation bridge, and repeated snapshot assignment. | Existing parser, probe, and monitor tests pass; `38d5574` passes 494 tests. |
| dedup-001 | Reused `probeJSON` for AWS, Salesforce, and Okta. | Existing probe cache, URL, and failure tests pass; `9acbb11` passes 494 tests. |
| dedup-002 | Reused one `ProbeContext.cachedHit` check for JSON, Icinga, and RSS. | Existing cache tests pass; `9acbb11` passes 494 tests. |
| dedup-003 | Reused `JSONScalar.nonempty` in Salesforce. | Existing Salesforce parser tests pass; `9acbb11` passes 494 tests. |
| dedup-011 | Reused `BenchmarkFixtures.greenPage` in menu tests. | Existing menu tests pass; `9acbb11` passes 494 tests. |
| weak-typing-001–006 | Invalid component statuses are yellow; invalid required Okta JSON and incident roots throw; numeric status conversion requires an exact integer. | `4349f6a` adds seven boundary tests (15 observed failures before fix); `72c394e` passes 501 tests. Final suite: 502 tests passed. |
| weak-typing-008 | Removed the Statuspal collection bridge. | Same change as ai-slop-003; `38d5574` passes 494 tests. |
| defensive-002–004 | Same parser boundary fixes as weak-typing-001–003, 006, plus present malformed incident collections in incident.io, Apple, and Heroku. Okta rejects malformed planned outages; Heroku rejects malformed scheduled data. | `4349f6a`, `ab4b257`, and `5fd4336` reproduce failures; `72c394e`, `e933c51`, and `7f9475f` pass 502 tests. |

## Skipped, by report

| Domain | Findings | Reason |
| --- | --- | --- |
| Dead code | dead-002, dead-003 | REVIEW: public initializer may have external users; probe counters have live benchmark readers. |
| Dead code | dead-004 | UNCERTAIN: PNG may be the source of the shipped icon. |
| AI slop | None | All four source-level findings applied. Retained explanatory comments, security checks, and accessibility code as directed. |
| Deduplication | dedup-004, dedup-006–009, dedup-012 | KEEP SEPARATE: small copies or distinct behavior; sharing would add code or blur rules. |
| Deduplication | dedup-005 | REVIEW: view lookup helpers need a deliberate test-support decision. |
| Deduplication | dedup-010 | Conditional: the cited payload suites were not otherwise changed; a shared fixture now adds files without a needed behavior change. |
| Type consolidation | type-consolidation-001, type-consolidation-002 | KEEP SEPARATE: local test doubles have distinct purposes. |
| Circular dependencies | circular-deps-001, circular-deps-002 | REVIEW: file-level cycles do not prove a runtime cycle; changing public boundaries needs separate design and coverage. |
| Circular dependencies | circular-deps-003, circular-deps-004 | KEEP: same-module type references are intentional. |
| Legacy code | legacy-001–003, legacy-005 | KEEP: live version-one and persisted-field compatibility or tested picker behavior. |
| Legacy code | legacy-004 | REVIEW: AppKit lifetime workaround has no safe removal proof. |
| Weak typing | weak-typing-007 | REVIEW: callback race is inferred; changing the public concurrency contract needs actor and caller proof. |
| Defensive programming | defensive-001 | High-risk deliberate TLS exception. Existing tests require it; safe migration and deployment compatibility were not proved. No trust check was removed. |
| Defensive programming | defensive-005, defensive-006 | NO-TEST-COVERAGE for rollback or permission-change failure paths; both are side-effectful and current tests cover only successful recovery. Existing protection remains. |
| Defensive programming | defensive-007 | Native notification completion failure has no runnable failure-path test or confirmed macOS recovery contract. |
| Defensive programming | defensive-008, defensive-009 | Low-priority diagnostic and conditional invariant simplifications; no related change warrants them. |
| LOC limits | loc-001 | Conditional on nearby AppDelegate polling work; a split now moves concurrency-sensitive code only to meet a size signal. |
| LOC limits | loc-005, loc-006 | Conditional test-file splits; cited suites were not maintained here. |
| LOC limits | loc-002–004, loc-007–011 | EXEMPT: cohesive suites or method counts at the threshold edge. |

No item was marked RESOLVED-UPSTREAM or MISSING-ON-TIP: the cited paths existed at the supplied tip. `weak-typing-008` and `defensive-002–004` overlap changes recorded in another domain and were applied once.

## Verification

- macOS isolated test copy: baseline 494 tests passed; after subtractive and structural phases 494 passed; after parser fixes 502 passed.
- `swift test --parallel` compiled every package target, with no new type errors.
- `git diff --check` passed. SwiftLint was unavailable on the Linux worker and macOS test host; the PR Sonar extras lane supplies its gate result.
- An independent read-only review found the Heroku scheduled-data gap. The focused red test reproduced it, the fix passed the full suite, and the reviewer reported no remaining concrete findings in changed paths.
- No Vitest project exists, so the cluster Vitest runner does not apply.
