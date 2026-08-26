# Deduplication Deferred

Date: 2026-08-21
Worktree: `/Users/terry.gerighty/coding/greendot-deduplication`
Branch: `cleanup/deduplication`
Source: `cleanup-reports/deduplication-assessment.md`

This apply only consolidates items with `verified: true` and `recommendation: CONSOLIDATE` that stay on the file allowlist. KEEP SEPARATE, REVIEW, parser consolidations, and items that need `Models.swift`, `MenuBuilder.swift`, or `ToastPolicy.swift` stay.

| ID | File | Confidence | Recommendation | Why deferred / skipped |
|---|---|---|---|---|
| dedup-003 | `Sources/StatusCore/Monitor.swift:60` | LIKELY | CONSOLIDATE | Unverified. Move of `toggleComponent` / `setAllComponents` onto `WatchedPage` needs `Models.swift` (circular-deps owns that file). |
| dedup-004 | `Sources/greendot/ComponentPicker.swift:133` | CERTAIN | CONSOLIDATE | Unverified REVIEW. `isOff` is the inverse of `WatchedPage.isComponentEnabled`. Could change the picker only, but the apply list said skip REVIEW. |
| dedup-005 | `Sources/StatusCore/ToastPolicy.swift:32` | CERTAIN | CONSOLIDATE | Needs `ToastPolicy.swift`, `MenuBuilder.swift`, and `Severity.swift`. Instruction: defer. `Severity.swift` is owned by circular-deps. |
| dedup-006 | `Sources/StatusCore/InstatusParser.swift:13` | CERTAIN | CONSOLIDATE | Parser consolidation. Instruction: skip. |
| dedup-007 | `Sources/StatusCore/StatuspageParser.swift:92` | LIKELY | CONSOLIDATE | Parser consolidation. Instruction: skip. |
| dedup-008 | `Sources/greendot/MenuBuilder.swift:136` | LIKELY | CONSOLIDATE | Unverified. Group-vs-leaf title condition is also in `MenuBuilder.swift`, which this apply must not edit. |
| dedup-009 | `Sources/StatusCore/Monitor.swift:41` | LIKELY | CONSOLIDATE | Unverified REVIEW. `mutatePage` helper could live in `Monitor.swift` alone, but the report ties it to dedup-003 / `WatchedPage`. |
| dedup-010 | `Tests/StatusCoreTests/ComponentToggleTests.swift:35` | LIKELY | CONSOLIDATE | Unverified. Broader temp-dir + `MapHTTPClient` sharing across `ComponentToggleTests` and `ProbeAndMonitorTests`. GitHub paste only is dedup-002 (applied). |
| dedup-011 | `Sources/StatusCore/InstatusParser.swift:26` | LIKELY | CONSOLIDATE | Parser consolidation. Instruction: skip. |
| dedup-012 | `UITests/GreenDotUITests/GreenDotUITests.swift:236` | LIKELY | KEEP SEPARATE | Instruction: skip KEEP SEPARATE. Timeouts and success checks differ. |
| dedup-013 | `Sources/StatusCore/Monitor.swift:28` | LIKELY | KEEP SEPARATE | Instruction: skip KEEP SEPARATE. `add` vs `edit` share probe lines; remaining work diverges. |
| dedup-014 | `Tests/StatusCoreTests/AggregatorTests.swift:39` | POSSIBLE | KEEP SEPARATE | Instruction: skip KEEP SEPARATE. Small `PageSnapshot` factories with different defaults. |
| dedup-015 | `Sources/greendot/UITestDriver.swift:49` | POSSIBLE | KEEP SEPARATE | Instruction: skip KEEP SEPARATE. NSView walk is not the component tree walk. |
| dedup-016 | `Tests/greendotTests/MenuBuilderTests.swift:103` | POSSIBLE | KEEP SEPARATE | Instruction: skip KEEP SEPARATE. Same Box names, different child counts. |

## Follow-up (after circular-deps / allowlist merge)

1. **dedup-003 + 004 + 009** — put toggle/set-all on `WatchedPage`, delete `ComponentPicker.isOff`, optional `mutatePage`. Needs `Models.swift`.
2. **dedup-005** — `Severity.displayText` for toast body and empty-page menu row. Needs `Severity.swift`, `ToastPolicy.swift`, `MenuBuilder.swift`. Keep Statuspal `"Maintenance"`.
3. **dedup-008** — `ComponentStatus.showsStatusText` / `isLeaf`. Needs `Models.swift` and `MenuBuilder.swift`. Do not unify the title strings.
4. **Parsers (006, 007, 011)** — `pageIdentity`, `decodeJSON`, `StatusMapping.instatusComponent`. Separate pass.
5. **dedup-010** — optional `tempStore()` / `makeMonitor(json:)` in each test file. Do not share fixtures across test targets.
