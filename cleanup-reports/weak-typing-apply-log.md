# Weak Typing Apply Log

Date: 2026-08-26
Branch: `cleanup/apply-20260826-weak-typing`
Merged weak-typing phase base: `ed38cde` (weak-typing phase merged into `main`)

Serial catch-up branch: `cleanup/apply-20260826-typing-catchup`
Serial catch-up base: `7154506` (merged `main` before this catch-up)

## Scope and gate

The verified weak-typing assessment and the cleanup summary were the change
authority. Verified `STRENGTHEN` and `ISOLATE` records were applied. Review,
unverified, and `KEEP` records were not changed. The circular apply log was
read; its verified weak callback edges remain weak, generation-gated, and
cleanup-backed. The initial weak-typing phase left `AppDelegate.swift` for the
serial catch-up; the serial catch-up changed only the allowlisted AppDelegate,
BuildInfo, and AppDelegate test files. `PerformanceHarnessTests.swift` was not
edited.

The initial tree was clean. Baseline checks passed:

- `swift build`: PASS.
- `swift test`: PASS, 150 tests passed, 1 benchmark test skipped, 0 failed.
- `swift build -Xswiftc -swift-version -Xswiftc 6`: RED as required.
- RED commit: `c9d6465` (`[TEST] Capture strict Swift 6 isolation failures`).

The initial strict Swift 6 RED had these source diagnostic counts (the
compiler printed duplicate module diagnostics): AppDelegate 2 errors and 3
warnings; PagePanelController 4 errors and 79 warnings; StatusDot 2 errors;
ComponentPicker 2 errors and 60 warnings; UITestDriver 2 errors and 18
warnings; AppEditMenu 2 warnings. The unique error messages were:

```text
AppDelegate.swift:12:9: error: main actor-isolated default value in a nonisolated context
PagePanelController.swift:11:17: error: main actor-isolated default value in a nonisolated context
PagePanelController.swift:12:17: error: main actor-isolated default value in a nonisolated context
StatusDot.swift:11:24: error: static property 'cache' is not concurrency-safe because it is nonisolated global shared mutable state [#MutableGlobalVariable]
ComponentPicker.swift:36:19: error: sending value of non-Sendable type 'ComponentPicker' risks causing data races [#SendingRisksDataRace]
ComponentPicker.swift:84:26: error: sending value of non-Sendable type 'ComponentPicker' risks causing data races [#SendingRisksDataRace]
UITestDriver.swift:51:17: error: non-Sendable 'String'-typed result can not be returned from main actor-isolated instance method 'accessibilityIdentifier()' to nonisolated context
UITestDriver.swift:63:31: error: non-Sendable 'String'-typed result can not be returned from main actor-isolated instance method 'accessibilityIdentifier()' to nonisolated context
```

## Serial catch-up RED baseline

At merged catch-up base `7154506`, fresh baseline checks were run before any
serial catch-up source edit:

- `swift build`: PASS.
- `swift test`: PASS, 163 tests passed, 1 intentional skip, 0 failures.
- `swift build -Xswiftc -swift-version -Xswiftc 6`: RED, exit 1.
- RED evidence commit: `14a513f` (`[TEST] Capture serial strict Swift 6 RED`).

The strict command's source-owned diagnostics were unchanged in kind from the
deferred plan: `AppDelegate.swift` had the `presentError` main-actor default
value error, `Task` captures of weak `AppDelegate` warnings in both poll and
pulse timer callbacks, and the `MainActor.assumeIsolated` pulse callback;
`BuildInfo.swift` had four `AboutPanel.show` AppKit actor warnings. No strict
diagnostic was reported in the already-isolated helper or panel sources.

## Item dispositions and commits

| Item | Recommendation | Disposition | Evidence / reason |
|---|---|---|---|
| `typing-001` | STRENGTHEN | **APPLIED** | `compactMap` creates `(groupID: String, row: Row)` pairs; dictionary grouping keeps input row order. GREEN `6fb3b0e`. |
| `typing-002` | REVIEW | **SKIPPED** | Verification was partial and `verified: false`; no `ProviderProbe.swift` edit. |
| `typing-003` | STRENGTHEN | **APPLIED** | Menu test casts `representedObject as? TargetAction` and calls `invoke()`. GREEN `6fb3b0e`. |
| `typing-004` | STRENGTHEN | **SKIPPED** | Likely, `verified: false`; no PageStore type redesign. |
| `typing-005` | ISOLATE | **APPLIED** | `StatusDot` is `@MainActor`; cache reuse and rendering stay unchanged. Toast attachment/content paths use the actor boundary. GREEN `e0544f8`. |
| `typing-006` | ISOLATE | **APPLIED** | `AppDelegate` is `@MainActor`; error and seed diagnostics are actor-aware generic `Error` callbacks; timer hops retain weak captures and polling behavior. GREEN `336dd91`. |
| `typing-007` | ISOLATE | **APPLIED** | `PagePanelController` is `@MainActor`; weak task capture, cancellation, generation gating, delegate clearing, and panel lifecycle remain. GREEN `e59ddaa`. |
| `typing-008` | ISOLATE | **APPLIED** | ComponentPicker, UITestDriver, AppEditMenu, MenuClickOpener, and the deferred `AboutPanel.show` surface are actor-isolated. The AppDelegate call path is actor-correct. Helper GREEN `75b569b`; correction `461c2e7`; catch-up GREEN `336dd91`. |
| `typing-009` | REVIEW | **SKIPPED** | Likely, `verified: false`; Monitor lock/sendability design was not changed. |
| `typing-010` | STRENGTHEN | **SKIPPED** | Likely, `verified: false`; callback defaults were not changed. |
| `typing-011` | STRENGTHEN | **SKIPPED** | Likely, `verified: false`; poll outcome was not redesigned. |
| `typing-012` | REVIEW | **SKIPPED** | Likely, `verified: false`; seed error policy was not changed. |
| `typing-013` | REVIEW | **SKIPPED** | Uncertain, `verified: false`; HTTP tuple API was not changed. |
| `typing-014` | KEEP | **RETAINED** | Provider JSON `Any` remains local to the external boundary. |
| `typing-015` | KEEP | **RETAINED** | AppKit represented-object and event-monitor dynamic edges remain intact. |
| `typing-016` | KEEP | **RETAINED** | Foundation and AppKit bridge types remain at their API boundaries. |
| `typing-017` | KEEP | **RETAINED** | Fail-closed regex compilation remains unchanged. |
| `typing-018` | KEEP | **RETAINED** | Lock-backed synchronization adapters remain unchanged. |
| `typing-019` | KEEP | **RETAINED** | XCTest lifecycle IUOs and known fixture URLs remain unchanged. |
| `typing-020` | KEEP | **RETAINED** | Generic error existential boundaries remain unchanged. |
| `typing-021` | KEEP | **RETAINED** | Non-fatal diagnostic and cleanup `try?` calls remain unchanged. |
| `typing-022` | KEEP | **RETAINED** | Domain optionals and migration defaults remain unchanged. |

RED commit for the original weak-typing pass: `c9d6465`.

Serial catch-up RED commit: `14a513f`.

GREEN commits:

- `6fb3b0e` — direct typing cleanup (`typing-001`, `typing-003`).
- `e0544f8` — StatusDot actor group (`typing-005`).
- `e59ddaa` — PagePanelController actor group (`typing-007`).
- `75b569b` — AppKit helper actor group (`typing-008`, partial).
- `461c2e7` — restore BuildInfo and defer AboutPanel actor propagation.
- `ab52557` — record weak-typing apply and deferred plan.
- `1b3a0d7` — mark AboutPanel isolation deferred.
- `4ce9453` — correct rebased weak-typing evidence.
- `336dd91` — serial AppDelegate and AboutPanel actor catch-up (`typing-006`, remaining `typing-008`).

## Actor boundary notes

`AboutPanel.options`, `BuildInfo.gitHash`, and `BuildInfo.shortHash` remain
pure helpers. `AboutPanel.show` is now directly `@MainActor`, and both the
AppEditMenu action and AppDelegate call path invoke it synchronously on the
actor. No `MainActor.assumeIsolated` or async wrapper is used for AboutPanel.
The UI-test notification bridge keeps its synchronous queue-main behavior by
extracting the String before its existing `MainActor.assumeIsolated` bridge.

`AppDelegate` is `@MainActor`. Its default `override nonisolated init()` keeps
the existing executable entry point synchronous while the injected delivery
initializer remains actor-isolated. The actor-aware `presentError` and
`seedFailureDiagnostic` callbacks preserve the generic `Error` boundary,
synchronous alert/log behavior, and test injection.

The simpler single initializer with its default argument was not sufficient:
the strict build reported
`Sources/greendot/main.swift:4:16: error: call to main actor-isolated
initializer 'init(toastDelivery:)' in a synchronous nonisolated context
[#ActorIsolatedCall]`. A private mutable delivery property with a
`SystemToastDelivery()` default lets the nonisolated NSObject initializer use
the same production default, while the separate actor-isolated injected
initializer assigns the test adapter. `PanelLifecycleTests` exercises
`AppDelegate()` and `AppDelegateRefreshErrorTests` exercises
`AppDelegate(toastDelivery:)`.

`MenuClickOpener` needs `override nonisolated init()` because
`StatusMenuController` has a default `MenuClickOpener()` argument whose
default expression is evaluated outside the actor. The initializer only calls
`NSObject.init()` and does not access mutable UI state. Swift 6.3 accepts
`isolated deinit`; it now calls `removeMonitor()` in the actor-correct
cleanup context. This preserves event-monitor removal and does not weaken
captures or change the AppKit monitor boundary.

## Verification after each group

### Direct typing group (`6fb3b0e`)

- `swift test --filter ParserTests`: PASS, 8 tests.
- `swift test --filter MenuBuilderTests`: PASS, 9 tests.
- `swift build`: PASS.
- `swift test`: PASS, 150 passed, 1 skipped, 0 failed.

### StatusDot group (`e0544f8`)

- `swift test --filter PanelLifecycleTests`: PASS, 15 tests.
- `swift test --filter SystemToastDeliveryTests`: PASS, 4 tests.
- `swift build`: PASS.
- `swift test`: PASS, 150 passed, 1 skipped, 0 failed.

### Page panel group (`e59ddaa`)

- `swift test --filter PanelLifecycleTests`: PASS, 15 tests.
- `swift test --filter StatusPageEditorTests`: PASS, 7 tests.
- `swift build`: PASS.
- `swift test`: PASS, 150 passed, 1 skipped, 0 failed.

### AppKit helper group (`75b569b`, corrected by `461c2e7`)

Focused helper tests passed:

- PanelLifecycleTests: 15; StatusMenuControllerTests: 7;
  CopyrightTests: 4; AboutTests: 4.
- Normal build and full tests passed 150/1 skipped before rebase, then 158/1
  skipped after rebase onto the defensive-programming and LOC results.

The strict probe after the correction reported only the then-deferred BuildInfo
warning and AppDelegate diagnostics:

```text
BuildInfo.swift:23:15: warning: call to main actor-isolated instance method 'activate(ignoringOtherApps:)' in a synchronous nonisolated context [#ActorIsolatedCall]
BuildInfo.swift:23:9: warning: main actor-isolated var 'NSApp' can not be referenced from a nonisolated context
BuildInfo.swift:24:15: warning: call to main actor-isolated instance method 'orderFrontStandardAboutPanel(options:)' in a synchronous nonisolated context [#ActorIsolatedCall]
BuildInfo.swift:24:9: warning: main actor-isolated var 'NSApp' can not be referenced from a nonisolated context
AppDelegate.swift:12:9: error: main actor-isolated default value in a nonisolated context
AppDelegate.swift:60:30: warning: capture of 'self' with non-Sendable type 'AppDelegate?' in a '@Sendable' closure [#SendableClosureCaptures]
AppDelegate.swift:60:30: warning: capture of 'self' with non-Sendable type 'AppDelegate?' in an isolated closure
AppDelegate.swift:65:27: warning: capture of 'self' with non-Sendable type 'AppDelegate?' in a '@Sendable' closure [#SendableClosureCaptures]
```

That historical strict command returned exit code 1. The diagnostics were
resolved by the serial catch-up below; there was no strict error in an owned
file other than the then-deferred AppDelegate boundary.

The post-correction strict command returned exit code 1 before the serial
catch-up, as expected for the deferred AppDelegate diagnostics.

### Serial AppDelegate/AboutPanel catch-up (`336dd91`)

- `swift test --filter AppDelegateRefreshErrorTests`: PASS, 5 tests.
- `swift test --filter PanelLifecycleTests`: PASS, 19 tests.
- `swift test --filter StatusMenuControllerTests`: PASS, 7 tests.
- `swift test --filter StatusPageEditorTests`: PASS, 7 tests.
- `swift test --filter SystemToastDeliveryTests`: PASS, 4 tests.
- `swift test --filter AboutTests`: PASS, 4 tests.
- `swift test --filter CopyrightTests`: PASS, 4 tests.
- `swift build`: PASS.
- `swift test`: PASS, 163 tests passed, 1 intentional skip, 0 failures.
- `swift build -Xswiftc -swift-version -Xswiftc 6`: PASS, exit 0, no source
  actor warnings or errors.

## Final checks

- `swiftlint lint --reporter json`: PASS, JSON produced; 8 existing findings,
  0 serious findings. No new finding was introduced by this branch.
- `git diff --check`: PASS for the source/test changes and report edits.
- Serial source/test change from catch-up base: 3 allowlisted files,
  22 insertions and 11 deletions. BuildInfo has the direct AboutPanel actor
  boundary; AppDelegate and its test have the actor catch-up.
- `PerformanceHarnessTests.swift` unchanged.
- Worktree is clean after the documentation commit.
