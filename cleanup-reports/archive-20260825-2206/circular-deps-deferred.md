# Circular Deps Deferred

Date: 2026-08-21
Source: `cleanup-reports/circular-deps-assessment.md`
Branch: `cleanup/circular-deps`

Authorized apply set was **cycle-001 only**. That item is in `circular-deps-apply-log.md`. No cycle-001 work was deferred.

The report listed no other SCCs. These notes are out of scope for this pass.

## Skipped (user instruction: cycle-001 only)

1. **Keep StatusCore free of AppKit and of greendot types**
   - Classification: module-DAG guard, not a cycle.
   - No StatusCore file imports `greendot` or AppKit today. No code change.

2. **ParserError share from StatuspageParser.swift**
   - Classification: one-way hub, not a cycle.
   - Report: keep as-is or move to its own file later. Not cycle-001.

3. **Optional: move TargetAction out of MenuBuilder.swift**
   - Classification: hub cleanup, not a cycle.
   - `MenuCommands.swift` and `MenuClickOpener.swift` depend one way. File is outside the allowlist.

4. **CI gate for `import greendot` / `import AppKit` in StatusCore**
   - Classification: optional new test, not a cycle fix.
   - Report says it protects the module DAG and will not see cycle-001.

## Out of scope (kept)

- Unused `import StatusCore` in `main.swift` — already removed by dead-code (dead-002).
- Path component `"greendot"` in `PageStore.defaultDirectory` — string, not a module edge.
- Same-module Cocoa wiring (`AppDelegate` / `MenuBarController`) — not a type-level cycle.
