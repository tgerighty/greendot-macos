# AI Slop Assessment

Scope: Swift sources and tests, plus relevant Markdown/configuration, at main `310032b` for the greendot macOS/AppKit package. The review covered `Sources/StatusCore`, `Sources/greendot`, `Tests`, and `UITests` (excluding the generated UI project), with caller tracing and reachable Git history. `.git`, `.build`, `greendot.app`, and all other `cleanup-reports` content were excluded. This is a read-only assessment; no production or test files were changed.

## Executive Summary

- Total findings: **3**, all LOW. HIGH: 0; MEDIUM: 0; LOW: 3.
- Category counts: WRAPPER-LARP 3; COMMENT-SLOP 0; STUB 0; LARP 0; DEAD-COMMENT 0; OVER-DOCUMENTED 0; COMMENTED-OUT-CODE 0.
- The three candidates are small identity/pass-through methods in `Sources/greendot/AppDelegate.swift`. They have no identified runtime defect. The main impact is minor indirection and a decision about whether named test seams are worth keeping.
- Top three:
  1. `shouldPoll(loadSucceeded:)` returns its input unchanged and can be inlined after confirming the launch-path test strategy.
  2. `showAbout()` only forwards to `AboutPanel.show()` and has one production caller.
  3. `shouldRefreshIconOnPulse(hasUnreachable:)` returns its input unchanged, but its name records a real pulse/performance rule and it has direct test and benchmark coverage.
- `swift test` passed: 150 tests executed, 1 skipped by the performance-harness environment gate, 0 failures.

Heat map by file and severity:

| File | HIGH | MEDIUM | LOW | Total |
| --- | ---: | ---: | ---: | ---: |
| `Sources/greendot/AppDelegate.swift` | 0 | 0 | 3 | 3 |
| **Total** | **0** | **0** | **3** | **3** |

## Critical

None. No HIGH findings were identified.

## Medium

None. No MEDIUM findings were identified.

## Low / Debatable

### `slop-001` — `shouldPoll` identity wrapper

`Sources/greendot/AppDelegate.swift:87-89` returns `loadSucceeded` without transformation. Its two callers could use the value directly. History confirms that the surrounding guard is intentional: polling and seeding must not proceed after a failed store load. The helper is tested as an identity, so removal should be paired with a test of the launch decision rather than simply deleting coverage. Recommendation: REVIEW, then inline `if loadSucceeded` if the named seam is not needed.

### `slop-002` — `showAbout` pass-through wrapper

`Sources/greendot/AppDelegate.swift:97-99` has one production caller and only forwards to `AboutPanel.show()`. Recommendation: REMOVE the wrapper and use `AboutPanel.show()` directly in the About action (or pass the method directly where the closure type permits). Keep `AboutPanel.show()` as the behaviour-bearing entry point.

### `slop-003` — `shouldRefreshIconOnPulse` identity wrapper

`Sources/greendot/AppDelegate.swift:93-95` also returns its Boolean input unchanged. Unlike a generic no-op, its name and adjacent comments capture the non-obvious rule that the grey pulse is only refreshed while a page is unreachable; callers and a performance test exercise that policy. Recommendation: REVIEW. Keep it if the named policy/test seam is useful; otherwise inline the guard and move the test to the timer/icon-refresh behaviour.

## Recommendations

1. Remove `showAbout()` and route the one About action directly to `AboutPanel.show()`.
2. Decide whether `shouldPoll` is a deliberate test seam. If not, inline it and test the launch decision after a failed load.
3. Treat `shouldRefreshIconOnPulse` as debatable rather than automatic cleanup because it names a real UI performance policy. Inline only if equivalent caller-level coverage is retained.
4. Keep the existing comments that explain AppKit lifetime/over-release constraints, notification concurrency and stale-toast behaviour, persistence compatibility, and the grey-pulse rule. No comment edit is recommended.
5. Keep intentional test-double no-op closures and empty initialisers; they configure fixtures or document test-double semantics and are not dead production paths.

## Out of Scope / Retained Context

- No current TODO/FIXME/XXX/HACK, `not implemented`, stub, fatal placeholder, AI/meta reference, commented-out code, or signature-restating documentation was found in the in-scope material.
- Adapter and controller types were traced to real callers or test seams. They were not classified as wrappers merely because they forward work.
- The README and design specification explicitly describe HTML scraping as a later planned slice, outside v1. This is planned work, not an unimplemented stub or an in-motion changelog comment.
- `CHANGELOG.md` is intentional release history. Framework, concurrency, persistence, and non-obvious business-rule comments were retained under the review rule.
- Generated UI project files, `greendot.app`, `.build`, `.git`, and all existing cleanup reports were excluded as requested.

## Independent Verification Disposition

No finding in this assessment met the mandatory HIGH-or-CERTAIN verification gate. All 3 records remain provisional with `verified: false`.

Final machine-readable severity counts: HIGH 0, MEDIUM 0, LOW 3. The original prose above records the specialist's pre-verification assessment; this disposition and the JSON block below are authoritative after verification.

## Machine-Readable Findings

```json
{"findings":[{"id":"slop-001","file":"Sources/greendot/AppDelegate.swift","line":87,"severity":"LOW","confidence":"LIKELY","recommendation":"REVIEW","category":"WRAPPER-LARP","detail":"shouldPoll(loadSucceeded:) returns its Boolean input unchanged; the launch path can likely use loadSucceeded directly, but history and tests show the surrounding failed-load guard is intentional.","verified":false},{"id":"slop-002","file":"Sources/greendot/AppDelegate.swift","line":97,"severity":"LOW","confidence":"LIKELY","recommendation":"REMOVE","category":"WRAPPER-LARP","detail":"showAbout() has one production caller and only forwards to AboutPanel.show(); route the About action directly to the behaviour-bearing method.","verified":false},{"id":"slop-003","file":"Sources/greendot/AppDelegate.swift","line":93,"severity":"LOW","confidence":"UNCERTAIN","recommendation":"REVIEW","category":"WRAPPER-LARP","detail":"shouldRefreshIconOnPulse(hasUnreachable:) returns its input unchanged, but its name records the grey-pulse performance rule and it has caller, test, and benchmark coverage.","verified":false}]}
```
