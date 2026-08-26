# Circular Dependency Assessment

Assessment scope: commit `310032b`, Swift package targets and source/test files under `Sources/` and `Tests/`. The generated UI project, `greendot.app`, `.build`, `.git`, and existing cleanup archives were not used as evidence. This is a read-only dependency assessment.

## Executive Summary

The Swift target graph has no import cycle. `swift package describe --type json` reports the following one-way edges: `greendot -> StatusCore`, `TestSupport -> StatusCore`, `StatusCoreTests -> StatusCore + TestSupport`, and `greendotTests -> greendot + StatusCore + TestSupport`. `StatusCore` has no package dependency. `swift build` completed successfully. `swift test` completed with 150 tests passed, one benchmark test skipped, and no failures.

There are 4 semantic findings: 0 HIGH, 1 MEDIUM, and 3 LOW. None is a confirmed breaking or runtime retain cycle. The MEDIUM finding is a file-level structural SCC in `StatusCore`. The LOW findings are intentional event or delegate loops whose back edges are weak or framework-managed.

Top three priorities:

1. `circular-001` (MEDIUM): keep generic severity aggregation independent from model-specific extensions. Extract the model-aware aggregation extension as the weakest-link change. This has the largest structural blast radius because it touches the `StatusCore` public aggregation surface.
2. `circular-002` (LOW): keep the menu callback loop, but preserve `[weak self]` in application handlers and the tracking-ended callback. The loop is part of menu interaction and has no strong owner back edge in the current code.
3. `circular-003` (LOW): keep the editor/panel callback loop. Preserve weak callback captures, cancellation generation checks, and the panel lifecycle test. The blast radius is limited to add/edit/remove UI flow.

The overall impact is low. No target graph change is required. The only recommended design improvement is the small extraction for `circular-001`; the other loops are useful control flow and should not be removed without a specific lifecycle defect.

## Critical Findings

None. No HIGH finding was identified. The target graph is acyclic, and the source compiles as one `greendot` executable target plus the `StatusCore` library.

## Medium Findings

### circular-001 - model-aware `Aggregator` extension forms a file-level SCC

Cycle traced as:

`Sources/StatusCore/Severity.swift::Aggregator` (`8-15`) -> `Sources/StatusCore/Models.swift::extension Aggregator` (`88-96`, which consumes `PageSnapshot` and `ComponentStatus`) -> `Sources/StatusCore/Models.swift::WatchedPage.displaySeverity` (`123-130`) -> `Sources/StatusCore/Severity.swift::Aggregator` (`9-15`).

`Aggregator.fromSeverities` is declared in `Severity.swift`. `Models.swift` then extends that type with model-specific methods, and `WatchedPage.displaySeverity` calls the model-aware method. This is a structural file dependency cycle inside one Swift target, not a package import cycle and not a recursive runtime call. It couples the generic severity utility to the domain model file and makes future movement of either file harder. The public methods are exercised by `AggregatorTests` and by monitor/menu code, so a careless move could affect those callers.

Minimal resolution: `EXTRACT` the model-aware methods into a small `StatusAggregation` helper or dedicated model aggregation file. Keep `Aggregator.fromSeverities` in `Severity.swift` and keep the public API as a forwarding layer if source compatibility is required. Blast radius: `StatusCore` aggregation code, `AggregatorTests`, and any external caller of `Aggregator.barSeverity` or `Aggregator.severity`; no UI ownership change is needed.

## Low / Debatable Findings

### circular-002 - application/menu callback loop is intentional and weak-backed

Cycle traced as:

`AppDelegate.statusMenu` (`Sources/greendot/AppDelegate.swift:5`, `42-45`) -> `StatusMenuController.builder` (`Sources/greendot/StatusMenuController.swift:7-10`, `33`) -> `MenuBuilder.handlers` and retained `TargetAction` menu items (`Sources/greendot/MenuBuilder.swift:34-39`, `61-74`, `206-223`) -> application handlers (`Sources/greendot/AppDelegate.swift:142-160`) -> `AppDelegate`.

The related tracking loop is:

`StatusMenuController.clickOpener` (`Sources/greendot/StatusMenuController.swift:9`, `39-40`) -> `MenuClickOpener.onTrackingEnded` (`Sources/greendot/MenuClickOpener.swift:7`, `40-47`) -> `StatusMenuController.scheduleDeferredMenuWork` (`Sources/greendot/StatusMenuController.swift:119-122`) -> `StatusMenuController`.

The first path is the normal menu event path. The application handlers capture `self` weakly, and the tracking callback also captures the controller weakly. `MenuClickOpener` removes its event monitor in `deinit` (`Sources/greendot/MenuClickOpener.swift:13-15`, `50-54`). Therefore the paths are semantic callback loops but not strong retain cycles in the current implementation. Changing the handlers to strong captures would turn this into a runtime leak risk.

Minimal resolution: `KEEP` the callback design and retain the weak captures. Blast radius: menu refresh, menu actions, and deferred menu presentation only. If the handler container is changed later, add a lifecycle test before changing ownership.

### circular-003 - editor, panel, and component picker callback loop

Cycle traced as:

`StatusPageEditor.panel` (`Sources/greendot/StatusPageEditor.swift:5-10`, `41-57`) -> `PagePanelController.onSave` (`Sources/greendot/PagePanelController.swift:9-20`, `22-37`) -> the `onSave` closure (`Sources/greendot/StatusPageEditor.swift:41-45`) -> `StatusPageEditor.save` (`Sources/greendot/StatusPageEditor.swift:94-107`) -> `StatusPageEditor`.

The component path is:

`StatusPageEditor` (`Sources/greendot/StatusPageEditor.swift:47-48`) -> `PagePanelController.picker` (`Sources/greendot/PagePanelController.swift:20`, `31-36`) -> `ComponentPicker` callbacks (`Sources/greendot/ComponentPicker.swift:4-20`, `98-124`) -> `StatusPageEditor.toggleComponentHandler` or `setAllComponentsHandler` (`Sources/greendot/StatusPageEditor.swift:73-91`) -> `StatusPageEditor`.

These are intended UI callbacks. The editor callbacks use `[weak self]`, the save task uses `[weak self]` (`Sources/greendot/PagePanelController.swift:161-175`), and close invalidates pending operations (`Sources/greendot/PagePanelController.swift:64-68`, `192-196`). `PanelReleaseTests` also checks that the controller and window deallocate (`Tests/greendotTests/PanelLifecycleTests.swift:269-290`). The remaining concern is maintenance risk if a new callback captures the editor or panel strongly.

Minimal resolution: `KEEP` the current weak callback boundary and generation guard. Blast radius: editor add/edit/remove and component toggle UI. Do not split the panel or monitor without a measured lifecycle problem.

### circular-004 - `PagePanelController` and `NSWindow` delegate edge is debatable

Cycle traced as:

`PagePanelController` retains its `window` (`Sources/greendot/PagePanelController.swift:9-10`, `42-53`) -> `NSWindow.delegate = self` (`Sources/greendot/PagePanelController.swift:51-53`) -> `PagePanelController`.

This is an AppKit delegate relationship, not a confirmed strong ownership cycle: AppKit delegate references are framework-managed and the controller explicitly clears the delegate before ordering the window out (`Sources/greendot/PagePanelController.swift:64-68`). The release test passes for both controller and window. It is recorded because delegate ownership is an easy regression point when replacing the window type or changing close behavior.

Minimal resolution: `KEEP` the current delegate clearing and release test. Blast radius: panel close and replacement only. Review again if a custom window class or retained delegate wrapper is introduced.

## Recommendations

- Apply only the `circular-001` extraction if reducing structural coupling is required. Move the model-aware `Aggregator` extension as one unit; do not split `StatusCore` targets or introduce a dependency from `StatusCore` to the executable.
- Preserve weak captures in `AppDelegate`, `StatusMenuController`, `StatusPageEditor`, and asynchronous panel tasks. Treat a new strong capture in these paths as a release-blocking review item.
- Preserve `PagePanelController.close()` delegate clearing and the existing deallocation test when changing panel ownership.
- Keep `TestSupport` as a one-way dependency on `StatusCore`. Do not move production types into `TestSupport` to solve a test-only callback.

## Out of Scope / Flagged for Review

- `TestSupport -> StatusCore` is a one-way target edge. `ControllableHTTPClient` conforms to `HTTPClient` and stores continuations, but no production target imports `TestSupport`; there is no test-support backedge. Tests use `failAll()` teardown for pending requests.
- `StatusDot`'s static image cache and `ProviderProbe`'s static counters/regular expression are shared state, but neither stores a callback or owner that points back to its caller. They are coupling points, not cycles.
- `PageStore.defaultDirectory` and `AppDelegate` read `GREENDOT_CONFIG_DIR` and other `GREENDOT_*` environment keys. These are input-only string/config edges. The source does not write those keys or call back into the environment, so no config cycle was found.
- Distributed notification names in `AppDelegate.installUITestHooks` (`Sources/greendot/AppDelegate.swift:192-232`) lead to `UITestDriver` actions, but the notification sender is external to this package and the package does not post the same names. This is an external UI-test edge, not an in-process cycle.
- `NSMenu.delegate`, `NSButton.target`, and `NSWindow.delegate` are framework ownership edges. The menu and panel paths are covered above only where source-level callback evidence exists; no package import cycle was invented from these AppKit relationships.

## Independent Verification Disposition

The mandatory gate selected 2 of 4 records. Independent verifiers confirmed 2; those records now have `verified: true`. 2 lower-confidence records remain provisional.

Verification evidence: [verification-batch-2.md](verification-batch-2.md).

Final machine-readable severity counts: HIGH 0, MEDIUM 1, LOW 3. The original prose above records the specialist's pre-verification assessment; this disposition and the JSON block below are authoritative after verification.
 
## Machine-Readable Findings

```json
{"findings":[{"id":"circular-001","file":"Sources/StatusCore/Models.swift","line":"88-96, 123-130","severity":"MEDIUM","confidence":"LIKELY","recommendation":"EXTRACT","detail":"File-level SCC: Severity.swift Aggregator -> Models.swift model-aware Aggregator extension -> WatchedPage.displaySeverity -> Severity.swift Aggregator. Structural only; no recursive runtime call.","verified":false},{"id":"circular-002","file":"Sources/greendot/AppDelegate.swift","line":"5, 42-45, 142-160","severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"Intentional menu callback loops have no strong self-retaining back-edge in the current code.","verified":true},{"id":"circular-003","file":"Sources/greendot/StatusPageEditor.swift","line":"41-57, 73-107","severity":"LOW","confidence":"CERTAIN","recommendation":"KEEP","detail":"The UI callback graph is cyclic as event flow but weak-backed and generation-gated.","verified":true},{"id":"circular-004","file":"Sources/greendot/PagePanelController.swift","line":"9-10, 42-53, 64-68","severity":"LOW","confidence":"UNCERTAIN","recommendation":"KEEP","detail":"Debatable AppKit edge: PagePanelController -> NSWindow -> delegate PagePanelController. Delegate ownership is framework-managed and cleared on close; release coverage passes.","verified":false}]}
```
