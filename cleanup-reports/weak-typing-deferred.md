# Weak Typing Deferred Serial Catch-up

Date: 2026-08-26
Branch: `cleanup/apply-20260826-weak-typing`
Worktree: `/Users/terry.gerighty/coding/greendot.cleanup-apply-20260826-weak-typing`

## Deferred item

`typing-006` is deferred. It owns `Sources/greendot/AppDelegate.swift`, and
the defensive-programming owner controls that file in this phase. This pass
did not edit `AppDelegate.swift`.

## Exact serial catch-up plan

1. Merge the defensive owner result and all approved earlier phase results.
   Start a fresh serial catch-up worktree from that merged branch. Confirm a
   clean tree and record the merge commit.
2. Re-run `swift build`, `swift test`, and
   `swift build -Xswiftc -swift-version -Xswiftc 6`. Confirm that the only
   remaining diagnostics are the AppDelegate diagnostics listed below.
3. Apply one AppDelegate change set. Add `@MainActor` to `AppDelegate`.
   Make `presentError` an actor-aware callback, preserving its synchronous
   `NSAlert` behaviour and generic `Error` boundary. Enter the main actor
   explicitly in both timer `Task` closures while retaining `[weak self]`.
   Keep Monitor network work outside the UI actor and return its typed result
   to AppDelegate. Do not remove cancellation, weak ownership, or the poll
   generation gate.
4. In the same serial catch-up, add a direct `@MainActor` boundary to
   `AboutPanel.show` and update its AppDelegate call site after AppDelegate is
   isolated. Keep the synchronous AppKit behaviour. Do not use
   `MainActor.assumeIsolated`, an async wrapper, or a changed dynamic boundary.
5. Run `swift test --filter AppDelegateRefreshErrorTests`,
   `swift test --filter PanelLifecycleTests`,
   `swift test --filter StatusMenuControllerTests`,
   `swift test --filter StatusPageEditorTests`,
   `swift test --filter SystemToastDeliveryTests`,
   `swift test --filter AboutTests`, and
   `swift test --filter CopyrightTests`. Then run normal build and full tests.
6. Run the strict Swift 6 probe again. It must have no error or warning in an
   owned file. Record the exact output and commit the catch-up separately as
   `[GREEN] Isolate AppDelegate on MainActor`.

## Current evidence for the catch-up

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

The post-correction strict command returned exit code 1, as expected until the
serial AppDelegate catch-up is complete.
