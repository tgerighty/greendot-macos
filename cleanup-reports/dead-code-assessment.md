# Dead-Code Assessment

Scope: the current `main` tree at commit `310032b`. This is a read-only call-graph and packaging review of `Sources/StatusCore`, `Sources/greendot`, `Tests`, `UITests`, `Resources`, `Package.swift`, the Makefile, and current git history. Archived cleanup reports were not used.

The repository has no third-party Swift package dependencies. The package graph has five targets: `StatusCore`, `TestSupport`, `greendot`, `StatusCoreTests`, and `greendotTests`. `StatusCore` and `greendot` are production targets; `TestSupport` is consumed by both test targets. The Makefile, not SwiftPM resources, copies `Resources/Info.plist` and `Resources/AppIcon.icns` into the application bundle.

## Executive Summary

Six findings were identified: 0 HIGH, 3 MEDIUM, and 3 LOW. One finding is CERTAIN, four are LIKELY, and one is UNCERTAIN. The estimated likely dead or relocatable code is about 93 lines, plus 3 certain dead lines and one uncertain 44 KB PNG resource. No finding is a release-blocking security or runtime failure.

The three highest-priority reviews are:

1. `dead-002` to `dead-004`: `MapHTTPClient`, `DelayHTTPClient`, and `RecordingHTTPClient` are test-only HTTP doubles compiled into `StatusCore`; together they are about 61 lines. Consider moving them to `Tests/TestSupport`, while deciding whether their public declarations are an intentional package API.
2. `dead-005`: parse and regex counters plus `CountBox` are used only by performance tests but add lock-protected instrumentation to production probe paths (about 32 lines). Decide whether benchmark observability belongs in the shipped target.
3. `dead-001`: `BuildInfo.gitHash` is an unused internal computed property left after the About panel changed to `shortHash`; it can be removed without changing behaviour.

The normal build and test evidence is healthy: `swift build` and `swift build -Xswiftc -warn-concurrency` pass, and `swift test` passes 150 tests with one intentionally skipped benchmark test. `swiftlint lint --strict` reports 11 existing violations (mostly length rules), which do not establish dead code.

## Critical Findings

None.

## Medium Findings

### dead-002 — MapHTTPClient is a test-only type in StatusCore

`Sources/StatusCore/HTTPClient.swift:21` declares `MapHTTPClient` and its initializer/get implementation. Repository call sites are in test targets only (`StatusCoreTests` and `greendotTests`); production selects `URLSessionHTTPClient` or `DirectoryHTTPClient`. It is `public`, so an external consumer cannot be ruled out, and the package target is not itself a published library product. Estimated relocatable code: about 15 LOC. This is a recent performance/test-support shape, so it may be intentional in-progress work.

Recommendation: REVIEW. Move it to `Tests/TestSupport` if it is not a supported StatusCore API; otherwise document the API and keep it.

### dead-003 — DelayHTTPClient is a benchmark-only type in StatusCore

`Sources/StatusCore/HTTPClient.swift:37` declares `DelayHTTPClient`. All repository uses are in `StatusCoreTests/PollPerformanceTests.swift`; no application source constructs it. It is `public`, so external use remains possible. Estimated relocatable code: about 14 LOC. Its origin is the recent poll-performance work, so it may still be deliberately shared by tests.

Recommendation: REVIEW. Move it with the other HTTP test doubles if no package-level consumer needs it.

### dead-004 — RecordingHTTPClient and RecordedURLs are benchmark-only support

`Sources/StatusCore/HTTPClient.swift:52` through `:83` declares `RecordingHTTPClient` and its private `RecordedURLs` lock box. Repository uses are limited to performance tests that count requests; no production source reads `requested` or constructs the wrapper. `RecordingHTTPClient` is `public`, so this is LIKELY rather than CERTAIN dead code. Estimated relocatable code: about 32 LOC.

Recommendation: REVIEW. Move the wrapper and its lock box to `Tests/TestSupport`, or document that it is intentionally part of the StatusCore test/diagnostic API.

## Low / Debatable Findings

### dead-001 — Unused BuildInfo.gitHash computed property

`Sources/greendot/BuildInfo.swift:5` through `:7` declares `BuildInfo.gitHash`. The app calls `BuildInfo.shortHash(from:)`; tests call `BuildInfo.gitHash(from:)` and `shortHash(from:)`, but no source, test, UI string, selector, reflection path, plist key, or configuration value reads the computed property. The enum and property are internal, and the release whole-module build does not retain a separate symbol for this property. Estimated dead code: 3 LOC.

Recommendation: REMOVE the property only; keep `gitHash(from:)`, which is used by `shortHash` and tests.

### dead-005 — Performance counters in the shipped probe target

`Sources/StatusCore/ProviderProbe.swift:18` through `:23`, `:152`, `:223`, and `:246` through `:270` implement `parseCount`, `regexCompileCount`, `resetCounts`, `CountBox`, and the two global boxes. Repository readers/resetters are performance tests; the application has no reader. The increment calls therefore add lock operations to parse and regex-initialisation paths without a product feature. The counters are valid test instrumentation, so this is not a certain removal. Estimated test-only/instrumentation code: about 32 LOC.

Recommendation: REVIEW. Move the counters behind a test-support seam or compile-time test flag if benchmark observability is still required; otherwise remove them after updating the benchmark assertions.

### dead-006 — AppIcon.png has no current packaging or code reference

`Resources/AppIcon.png` is a tracked 1024x1024, approximately 44 KB PNG. `Resources/Info.plist` names the `AppIcon` asset and `Makefile:29` copies only `Resources/AppIcon.icns`; no package resource declaration, source reference, test, or documentation reference uses the PNG. It may be the editable source used to regenerate the ICNS, so external design-tool use cannot be ruled out. Estimated dead source LOC: 0; possible unused resource: 44 KB.

Recommendation: REVIEW. Keep it if it is the maintained icon source, or remove it (and record the source-of-truth elsewhere) if the ICNS is the only maintained artifact.

## Recommendations

- Decide whether the three public HTTP doubles are package API or test support. If test support, move them together to `Tests/TestSupport` and retain the production `HTTPClient` protocol plus `URLSessionHTTPClient` and `DirectoryHTTPClient`.
- Decide whether performance counters belong in production. Their current lock-based counters affect every parse even though only benchmark tests read them.
- Remove `BuildInfo.gitHash` after a final repository-wide reference check; no dynamic Objective-C or configuration path applies to this internal property.
- Resolve the icon source-of-truth decision before deleting `AppIcon.png`.
- Keep the AppKit callbacks, `@objc` action methods, menu target boxes, accessibility identifiers, distributed notification names, notification category strings, and plist/Makefile references. Textual call-graph absence is not evidence of dead code for those paths.

## Out of Scope / Flagged for Review

- `Monitor.barSeverity()` and `Aggregator.barSeverity(from:)` have no application call site, but test seams call them and they are public StatusCore APIs. They are retained rather than reported as dead.
- `DirectoryHTTPClient` is primarily a UI-test fixture adapter, but `AppDelegate` selects it through `GREENDOT_FIXTURE_DIR` and the XCUITest environment; it is live dynamic test-mode code.
- `UITestDriver`, `AppDelegate.observe`, accessibility identifiers, and distributed notification names are intentionally string-driven. They were cross-checked against `UITests/GreenDotUITests/GreenDotUITests.swift` and were not treated as dead.
- `PagePanelController` window callbacks and button actions are Objective-C/AppKit entry points. `MenuClickOpener` delegate callbacks and `TargetAction.invoke` are likewise runtime-dispatched.
- `Resources/AppIcon.icns` and `Resources/Info.plist` are live Makefile/bundle inputs. `.DS_Store` is ignored and untracked, so it is not a package finding.
- No third-party package or unused target dependency was found. The direct test dependencies on `StatusCore` and `TestSupport` are used by test source.
- Recent commits added the HTTP performance helpers and probe counters (`e56941e`) and the `TestSupport` target (`69affa2`); these are flagged as possible in-progress test infrastructure, not automatic removals.
- The assessment does not evaluate generated `UITests/GreenDotUITests.xcodeproj`, archived reports, runtime memory leaks, or formal product/API compatibility outside this repository.

## Independent Verification Disposition

The mandatory gate selected 1 of 6 records. Independent verifiers confirmed 1; those records now have `verified: true`. 5 lower-confidence records remain provisional.

Verification evidence: [verification-batch-2.md](verification-batch-2.md).

Final machine-readable severity counts: HIGH 0, MEDIUM 3, LOW 3. The original prose above records the specialist's pre-verification assessment; this disposition and the JSON block below are authoritative after verification.

## Machine-Readable Findings

```json
{"findings":[{"id":"dead-001","file":"Sources/greendot/BuildInfo.swift","line":5,"severity":"LOW","confidence":"CERTAIN","recommendation":"REMOVE","detail":"Only the computed property is dead; retain gitHash(from:) and shortHash(from:).","verified":true},{"id":"dead-002","file":"Sources/StatusCore/HTTPClient.swift","line":21,"severity":"MEDIUM","confidence":"LIKELY","recommendation":"REVIEW","detail":"MapHTTPClient is constructed only by repository tests and is not used by application source. It is public, so an external consumer cannot be ruled out; consider moving it to TestSupport.","verified":false},{"id":"dead-003","file":"Sources/StatusCore/HTTPClient.swift","line":37,"severity":"MEDIUM","confidence":"LIKELY","recommendation":"REVIEW","detail":"DelayHTTPClient is used only by poll-performance tests and no production source constructs it. It is public and may be intentional shared benchmark infrastructure.","verified":false},{"id":"dead-004","file":"Sources/StatusCore/HTTPClient.swift","line":52,"severity":"MEDIUM","confidence":"LIKELY","recommendation":"REVIEW","detail":"RecordingHTTPClient and its private RecordedURLs box are used only by performance tests; no production source reads requested or constructs the wrapper. Public visibility prevents CERTAIN classification.","verified":false},{"id":"dead-005","file":"Sources/StatusCore/ProviderProbe.swift","line":18,"severity":"LOW","confidence":"LIKELY","recommendation":"REVIEW","detail":"parseCount, regexCompileCount, resetCounts, CountBox, and the global boxes are read only by performance tests but increment lock-protected counters on production probe paths.","verified":false},{"id":"dead-006","file":"Resources/AppIcon.png","line":1,"severity":"LOW","confidence":"UNCERTAIN","recommendation":"REVIEW","detail":"The tracked PNG has no current package, Makefile, plist, source, test, or documentation reference; Makefile packaging uses AppIcon.icns. It may still be the editable source for the ICNS.","verified":false}]}
```
