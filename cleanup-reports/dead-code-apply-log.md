# Dead-code cleanup apply log

Scope: `dead-code-assessment.md` on branch `cleanup/apply-20260826-dead-code`.
The worktree started clean at base commit `9141e8b`. The explicit file allowlist
was `Sources/greendot/BuildInfo.swift`, this apply log, and the optional deferred
log. No deferred log was needed because no item was deferred by file ownership.

Result: 1 item applied, 5 items skipped, 0 items deferred.

## RED baseline

The untouched baseline passed:

- `swift build` — PASS; `Build complete! (29.82s)`.
- `swift test` — PASS; 150 tests executed, 1 intentional benchmark test skipped,
  0 failures.

The final pre-change reference gate used these searches:

- `rg --hidden --glob '!.git' --glob '!.build' -n -S 'BuildInfo\.gitHash|gitHash|shortHash' .`
- `rg --hidden --glob '!.git' --glob '!.build' -n -S 'BuildInfo\.gitHash|\.gitHash' .`
- `git grep -n -I -E 'BuildInfo\.gitHash|gitHash|shortHash' -- . ':!.build'`
- `git log --all --full-history --oneline -G 'BuildInfo\.gitHash|\.gitHash' --`
- `git log --all --full-history --oneline -S 'static var gitHash' -- Sources/greendot/BuildInfo.swift`

The executable source and test matches were only `gitHash(from:)` and
`shortHash(from:)`. There was no zero-argument computed-property use, selector,
reflection use, plist/configuration reference, or other live reference. Git
history showed only the property's introduction and the later About-panel
change. The empty RED commit is `4657aaa356c2ab35b77d3df14fd987583ce1191d`:

`[TEST] Confirm dead-code removal baseline`

## GREEN changes

### dead-001 — APPLIED

Finding: the verified `REMOVE` finding for the internal computed property in
`Sources/greendot/BuildInfo.swift`.

Change: removed only `BuildInfo.gitHash`, retaining `gitHash(from:)` and
`shortHash(from:)`. The file change is 4 physical lines deleted (3 code lines
and the following separator blank line); the assessment estimates 3 code LOC.

Post-change verification:

- `swift build` — PASS; `Build complete! (4.83s)`.
- `swift test` — PASS; 150 tests executed, 1 intentional benchmark test
  skipped, 0 failures.
- `git diff --check` — PASS.
- Post-change search found no computed-property declaration or live access;
  the retained helper calls remain in the application and About tests.

The GREEN commit is `b2698a8d1b94baf41198cae0f9593acae87098a0`:

`[CLEANUP] Remove unused BuildInfo gitHash property`

## Skipped findings

- `dead-002` — SKIPPED. `REVIEW` and `verified:false`; `MapHTTPClient` is a
  public test double. Moving HTTP clients is phase 2 work and is outside this
  removal.
- `dead-003` — SKIPPED. `REVIEW` and `verified:false`; `DelayHTTPClient` is a
  public benchmark helper. Moving HTTP clients is phase 2 work.
- `dead-004` — SKIPPED. `REVIEW` and `verified:false`; the public recording
  wrapper remains part of the same phase 2 HTTP-client decision.
- `dead-005` — SKIPPED. `REVIEW` and `verified:false`; performance counters
  require a separate test-support or compile-time seam decision.
- `dead-006` — SKIPPED. `REVIEW` and `verified:false`; the PNG may be the
  maintained editable source for the packaged ICNS.
