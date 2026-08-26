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
4. Keep `AboutPanel.show()` as a direct `@MainActor` call. After AppDelegate
   is isolated, check whether its call site can use the actor method directly;
   remove no dynamic AppKit boundary unless the compiler and focused tests
   prove that the synchronous behaviour is unchanged.
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

After the helper actor group, the strict probe reports only AppDelegate source
diagnostics. The exact source messages are:

```text
Sources/greendot/AppDelegate.swift:12:9: error: main actor-isolated default value in a nonisolated context
Sources/greendot/AppDelegate.swift:60:30: warning: capture of 'self' with non-Sendable type 'AppDelegate?' in a '@Sendable' closure [#SendableClosureCaptures]
Sources/greendot/AppDelegate.swift:60:30: warning: capture of 'self' with non-Sendable type 'AppDelegate?' in an isolated closure
Sources/greendot/AppDelegate.swift:65:27: warning: capture of 'self' with non-Sendable type 'AppDelegate?' in a '@Sendable' closure [#SendableClosureCaptures]
Sources/greendot/AppDelegate.swift:98:20: error: call to main actor-isolated static method 'show()' in a synchronous nonisolated context [#ActorIsolatedCall]
```

The compiler prints the same module diagnostics more than once. No error is
reported in StatusDot, PagePanelController, ComponentPicker, UITestDriver,
AppEditMenu, BuildInfo, MenuClickOpener, or SystemToastDelivery.

The post-correction strict command returned exit code 1, as expected until the
serial AppDelegate catch-up is complete.
