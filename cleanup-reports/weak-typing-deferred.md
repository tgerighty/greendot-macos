# Weak Typing Deferred Serial Catch-up

Date: 2026-08-26
Branch: `cleanup/apply-20260826-weak-typing`
Worktree: `/Users/terry.gerighty/coding/greendot.cleanup-apply-20260826-weak-typing`
Merged weak-typing phase base: `ed38cde` (weak-typing phase merged into `main`)

Serial catch-up branch: `cleanup/apply-20260826-typing-catchup`
Serial catch-up worktree: `/Users/terry.gerighty/coding/greendot.cleanup-apply-20260826-typing-catchup`
Serial catch-up base: `7154506` (merged `main` before this catch-up)

Status: **CLOSED** after serial catch-up GREEN `336dd91`.

## Historical deferred item

`typing-006` was deferred during the original weak-typing phase because the
defensive-programming owner controlled `Sources/greendot/AppDelegate.swift`.
The remaining `AboutPanel.show` portion of `typing-008` was deferred with it.
The serial catch-up below now closes both items.

## Serial catch-up plan and completion

1. **Complete.** The defensive owner result and all approved earlier phase
   results were merged at `7154506`; the serial catch-up worktree started
   clean.
2. **Complete.** Baseline `swift build` and `swift test` passed; strict Swift 6
   was captured RED in `14a513f`.
3. **Complete.** `AppDelegate` is `@MainActor`. `presentError` and
   `seedFailureDiagnostic` are actor-aware callbacks over generic `Error`.
   Both timer callbacks enter MainActor explicitly with weak captures.
   Monitor network work, cancellation, weak ownership, and the poll generation
   gate remain unchanged.
4. **Complete.** `AboutPanel.show` is directly `@MainActor`; its AppDelegate
   call path remains synchronous with no AboutPanel `assumeIsolated` bridge or
   async wrapper.
5. **Complete.** Focused tests, normal build, and full tests passed:
   `swift test --filter AppDelegateRefreshErrorTests`,
   `swift test --filter PanelLifecycleTests`,
   `swift test --filter StatusMenuControllerTests`,
   `swift test --filter StatusPageEditorTests`,
   `swift test --filter SystemToastDeliveryTests`,
   `swift test --filter AboutTests`, and
   `swift test --filter CopyrightTests`; full `swift test` passed 163 tests
   with 1 intentional skip.
6. **Complete.** Strict Swift 6 passed with exit 0 and no source actor
   warnings/errors. GREEN commit: `336dd91` (`[GREEN] Isolate AppDelegate on
   MainActor`).

## Historical pre-catch-up evidence

After the helper actor group and BuildInfo restoration, the strict probe
reports the known BuildInfo warnings and AppDelegate diagnostics. The exact
source messages are:

```text
Sources/greendot/BuildInfo.swift:23:15: warning: call to main actor-isolated instance method 'activate(ignoringOtherApps:)' in a synchronous nonisolated context [#ActorIsolatedCall]
Sources/greendot/BuildInfo.swift:23:9: warning: main actor-isolated var 'NSApp' can not be referenced from a nonisolated context
Sources/greendot/BuildInfo.swift:24:15: warning: call to main actor-isolated instance method 'orderFrontStandardAboutPanel(options:)' in a synchronous nonisolated context [#ActorIsolatedCall]
Sources/greendot/BuildInfo.swift:24:9: warning: main actor-isolated var 'NSApp' can not be referenced from a nonisolated context
Sources/greendot/AppDelegate.swift:12:9: error: main actor-isolated default value in a nonisolated context
Sources/greendot/AppDelegate.swift:60:30: warning: capture of 'self' with non-Sendable type 'AppDelegate?' in a '@Sendable' closure [#SendableClosureCaptures]
Sources/greendot/AppDelegate.swift:60:30: warning: capture of 'self' with non-Sendable type 'AppDelegate?' in an isolated closure
Sources/greendot/AppDelegate.swift:65:27: warning: capture of 'self' with non-Sendable type 'AppDelegate?' in a '@Sendable' closure [#SendableClosureCaptures]
```

The compiler prints the same module diagnostics more than once. No error is
reported in StatusDot, PagePanelController, ComponentPicker, UITestDriver,
AppEditMenu, MenuClickOpener, or SystemToastDelivery. The four BuildInfo
warnings are the known deferred `AboutPanel.show` boundary.

The post-correction strict command returned exit code 1 before the serial
catch-up. This historical RED is superseded by the closed GREEN result below.

## Serial catch-up RED evidence

Fresh checks at merged base `7154506`, before any serial source edit:

- `swift build`: PASS.
- `swift test`: PASS, 163 tests passed, 1 intentional skip, 0 failures.
- `swift build -Xswiftc -swift-version -Xswiftc 6`: RED, exit 1.
- RED evidence commit: `14a513f` (`[TEST] Capture serial strict Swift 6 RED`).

The fresh strict output reported the known `AppDelegate.swift` default-value
error and weak `AppDelegate` captures in the poll and pulse timer closures,
plus the four `BuildInfo.swift` warnings caused by the deferred
`AboutPanel.show` boundary. The compiler emitted duplicate module diagnostics;
no error was reported in the already-isolated helper or panel sources.

## Closed disposition

- `typing-006`: **APPLIED** in GREEN `336dd91`.
- `typing-008` remaining AboutPanel portion: **APPLIED** in GREEN `336dd91`.
- No weak-typing deferred items remain from this serial catch-up.
- Stable merged weak-typing evidence commits are `c9d6465`, `6fb3b0e`,
  `e0544f8`, `e59ddaa`, `75b569b`, `461c2e7`, `ab52557`, `1b3a0d7`, and
  `4ce9453`; the serial RED/GREEN commits are `14a513f` and `336dd91`.
