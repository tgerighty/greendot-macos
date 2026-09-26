Ponytail: full intensity. Climb the YAGNI ladder. Prefer existing code, the standard library, and native features. Keep diffs minimal. Preserve trust-boundary validation, security, and accessibility.

# Dead-Code Assessment

## Executive Summary

- Scope: the Swift targets in `Package.swift:8`, their tests, and the app inputs in `Makefile:24`.
- Total findings: 4. Severity: HIGH 0, MEDIUM 0, LOW 4.
- Confidence: CERTAIN 1, LIKELY 2, UNCERTAIN 1. All machine-readable findings remain unverified.
- Dead code estimate: 9 nonblank lines at CERTAIN confidence in `Tests/greendotTests/InMemoryToastDelivery.swift:7` and `Tests/greendotTests/InMemoryToastDelivery.swift:29`. At LIKELY confidence, 8 lines form an unused public initializer in `Sources/StatusCore/HTTPClient.swift:57`. About 26 more production lines serve test-only probe counters; those lines still have test consumers and are a review item, not an automatic deletion (`Sources/StatusCore/ProviderProbe.swift:24`, `Sources/StatusCore/ProviderProbe.swift:249`, `Tests/StatusCoreTests/PollPerformanceTests.swift:120`). The uncertain icon file has no source LOC estimate (`Makefile:33`).
- Top priorities: remove only the unread test counter (`Tests/greendotTests/InMemoryToastDelivery.swift:7`); decide whether the public session initializer is an intended API (`Sources/StatusCore/HTTPClient.swift:57`); keep or remove probe measurements with their tests as one decision (`Sources/StatusCore/ProviderProbe.swift:24`, `Tests/StatusCoreTests/PollPerformanceTests.swift:120`).

The package declares no external packages or dependency downloads, so unused dependency install-size impact is 0 (`Package.swift:4`). This host has no Swift compiler or Swift dead-code analyzer. The assessment uses a read-only identifier scan, manual call-site checks, the package manifest, build inputs, and git blame. Swift build and tests were not run.

## Critical Findings

None.

## Medium Findings

None.

## Low / Debatable Findings

### dead-001 — unread counter in a test double — CERTAIN

`InMemoryToastDelivery.startCount` reads `storedStartCount`, but no source or test reads `startCount`; a repository-wide identifier search found only its declaration (`Tests/greendotTests/InMemoryToastDelivery.swift:7`). The double increments the stored count in `start()` (`Tests/greendotTests/InMemoryToastDelivery.swift:29`). The protocol still requires `start()`, so keep that method and remove only its unused counting state and accessor (`Sources/greendot/ToastDelivery.swift:4`). Estimated reduction: 9 nonblank lines. Recommendation: REMOVE the counter, not the protocol method.

### dead-002 — unused public URLSession initializer — LIKELY

`URLSessionHTTPClient.init(session:)` has no repository caller (`Sources/StatusCore/HTTPClient.swift:57`). The application calls the zero-argument initializer (`Sources/greendot/AppDelegate.swift:262`), and that initializer installs the redirect and trust delegate (`Sources/StatusCore/HTTPClient.swift:66`). The other initializer is public, so external module use remains possible. Git blame places it in the September 2 HTTP-client changes; check API intent before removal. Estimated reduction: 8 nonblank lines. Recommendation: REVIEW, then remove only this initializer if it is not supported API. Keep the default initializer and delegate (`Sources/StatusCore/HTTPClient.swift:66`, `Sources/StatusCore/HTTPClient.swift:95`).

### dead-003 — probe counters used only by tests — LIKELY

Production probe code keeps two lock-protected counters and reset/read APIs (`Sources/StatusCore/ProviderProbe.swift:24`, `Sources/StatusCore/ProviderProbe.swift:249`). Parse and regex paths update them, including the common JSON landing path (`Sources/StatusCore/ProviderProbe+JSONLandings.swift:201`) and regex initialization (`Sources/StatusCore/ProviderProbe.swift:225`). Repository readers and resetters are tests, for example `Tests/StatusCoreTests/PollPerformanceTests.swift:120` and `Tests/greendotTests/PerformanceHarnessTests.swift:214`. The counters are live test instrumentation, so removing them requires changing those tests. An inventory found about 26 nonblank production lines across the definitions and update calls. Recommendation: REVIEW benchmark value and measured overhead before removing the counters and their assertions together. Do not remove cached regexes or parsing logic (`Sources/StatusCore/ProviderProbe.swift:225`).

### dead-004 — PNG icon is absent from the app packaging path — UNCERTAIN

The app copies `AppIcon.icns` into the bundle (`Makefile:33`), and the plist names that icon (`Resources/Info.plist:13`). The package does not declare a resource target (`Package.swift:8`). A repository-wide search found no build, source, test, or documentation reference to `Resources/AppIcon.png`. The PNG may be the maintained source for the ICNS. Recommendation: REVIEW the icon source of truth. Keep the PNG if it is used to produce or edit the shipped icon (`Makefile:33`). No source LOC or dependency install size is assigned.

## Recommendations

1. Remove the unread test-only start counter and retain `start()` for protocol conformance (`Tests/greendotTests/InMemoryToastDelivery.swift:7`, `Sources/greendot/ToastDelivery.swift:4`).
2. Confirm whether `init(session:)` is public API. If not, remove its eight lines and retain the live default initializer (`Sources/StatusCore/HTTPClient.swift:57`, `Sources/greendot/AppDelegate.swift:262`).
3. Decide whether the existing benchmark assertions justify counters on production probe paths. Change the counters and tests together if they do not (`Sources/StatusCore/ProviderProbe.swift:24`, `Tests/StatusCoreTests/PollPerformanceTests.swift:120`).
4. Keep `AppIcon.png` until the icon source of truth is known (`Makefile:33`, `Resources/Info.plist:13`).

## Out of Scope / Flagged for Review

- `UITestDriver` has live environment-gated notification entry points. A static call graph cannot prove that string-based hooks are dead (`Sources/greendot/AppDelegate.swift:207`, `UITests/GreenDotUITests/GreenDotUITests.swift:221`). The `showMenu` observer has no in-repository poster, but may have an external test driver (`Sources/greendot/AppDelegate.swift:211`). KEEP pending explicit test-contract review.
- AppKit actions and delegates are runtime entry points. For example, `PagePanelController.saveTapped` is connected with `#selector` (`Sources/greendot/PagePanelController.swift:84`, `Sources/greendot/PagePanelController.swift:151`); `windowWillClose` is a delegate callback (`Sources/greendot/PagePanelController.swift:77`). KEEP.
- `DirectoryHTTPClient` supports the fixture environment path in the executable (`Sources/greendot/AppDelegate.swift:262`). `TestSupport` is a declared target consumed by both test targets (`Package.swift:9`). The HTTP doubles have test call sites, such as `Tests/StatusCoreTests/PollPerformanceTests.swift:31` and `Tests/greendotTests/PerformanceHarnessTests.swift:100`. KEEP.
- Codable keys and model fields have serialization use even when a direct member access is absent. For example, `WatchedPage` defines coding keys and decode/encode methods (`Sources/StatusCore/Models.swift:164`). No model field is recommended for deletion from a name-only scan.
- The current package has no third-party dependency to remove (`Package.swift:4`). The target and resource review did not establish another unused Swift source file (`Package.swift:8`, `Makefile:24`).

## Machine-Readable Findings

```json
{
  "findings": [
    {
      "id": "dead-001",
      "file": "Tests/greendotTests/InMemoryToastDelivery.swift",
      "line": 11,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "REMOVE",
      "detail": "The startCount accessor and its stored counter have no reader. Keep the required ToastDelivery.start() method as a no-op.",
      "verified": false
    },
    {
      "id": "dead-002",
      "file": "Sources/StatusCore/HTTPClient.swift",
      "line": 57,
      "severity": "LOW",
      "confidence": "LIKELY",
      "recommendation": "REVIEW",
      "detail": "No repository call uses URLSessionHTTPClient.init(session:). Its public visibility requires an API decision before removal.",
      "verified": false
    },
    {
      "id": "dead-003",
      "file": "Sources/StatusCore/ProviderProbe.swift",
      "line": 24,
      "severity": "LOW",
      "confidence": "LIKELY",
      "recommendation": "REVIEW",
      "detail": "Production probe paths update lock-protected counters that only tests read. Keep or remove the counters and dependent tests as one decision.",
      "verified": false
    },
    {
      "id": "dead-004",
      "file": "Makefile",
      "line": 33,
      "severity": "LOW",
      "confidence": "UNCERTAIN",
      "recommendation": "REVIEW",
      "detail": "Resources/AppIcon.png is absent from the app packaging path; it may be the maintained source for the copied AppIcon.icns.",
      "verified": false
    }
  ]
}
```
