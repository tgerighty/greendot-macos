# Defensive Programming Deferred

Date: 2026-08-21
Source: `cleanup-reports/defensive-programming-assessment.md`
Branch: `cleanup/defensive-programming`

The apply pass only changes items with `verified: true` and `ERROR-HIDING` or `NEEDS-REFACTOR`. LEGITIMATE items stay. Unverified items stay.

| ID | File | Confidence | Recommendation | Why deferred |
|---|---|---|---|---|
| def-002 (seed probe/save alert) | `Sources/greendot/AppDelegate.swift:92` | CERTAIN | ERROR-HIDING | `verified: false`. First-run `try? await monitor.add` still hides probe/save failure for the OpenAI seed. Skip-seed after a failed load is done as part of def-001. |
| def-004 | `Sources/StatusCore/Monitor.swift:130` | CERTAIN | ERROR-HIDING | `verified: false`. `pollAll` still uses `try? store.save`. Instruction: apply only if verified. Do not make `pollAll` throw. |
| def-005 | `Sources/StatusCore/Monitor.swift:24` | CERTAIN | NEEDS-REFACTOR | `verified: false`. First-run `try? store.save` for `didSetLaunchAtLogin`. Load-failure skip is in AppDelegate. Logging the save error is out of this pass. |
| def-006 | `Sources/StatusCore/Monitor.swift:116` | CERTAIN | NEEDS-REFACTOR | `verified: false`. Per-page poll catch still greys without `NSLog`. Isolation stays. |
| def-007 | `Sources/StatusCore/ProviderProbe.swift:90` | CERTAIN | NEEDS-REFACTOR | `verified: false`. File is not on the apply allowlist. HTTP 5xx/429 classification stays. |
| def-008 | `Sources/greendot/Notifier.swift:24` | CERTAIN | NEEDS-REFACTOR | `verified: false`. File is not on the apply allowlist. Notification `add` still has no completion handler. |
| def-009 | `Sources/StatusCore/Monitor.swift:23` | CERTAIN | NEEDS-REFACTOR | `verified: false`. Persist `didSetLaunchAtLogin` only after `SMAppService.register` succeeds. Keep LaunchAtLogin `NSLog`. |
| def-010 | `Sources/StatusCore/ProviderProbe.swift:146` | CERTAIN | UNNECESSARY | `verified: false`. File is not on the apply allowlist. Static regex `try?` stays. |
| def-011 | `Sources/StatusCore/StatuspageParser.swift:65` | CERTAIN | LEGITIMATE | Safe `groupID!` after filter. Do not remove. |
| def-012 | `Sources/StatusCore/PageStore.swift:41` | CERTAIN | LEGITIMATE | Missing `config.json` returns empty `AppConfig`. First-run I/O. Do not remove. |
| def-013 | `Sources/StatusCore/PageStore.swift:53` | CERTAIN | LEGITIMATE | Decode/version failure throws `StoreError.corrupt`. Caller swallow was def-001. |
| def-014 | `Sources/StatusCore/ProviderProbe.swift:93` | CERTAIN | LEGITIMATE | Parse miss so the next provider can run. Do not remove. |
| def-015 | `Sources/StatusCore/ProviderProbe.swift:96` | CERTAIN | LEGITIMATE | HTTP `client.get` throw is `.networkError`. Do not remove. |
| def-016 | `Sources/StatusCore/ProviderProbe.swift:121` | CERTAIN | LEGITIMATE | Statuspal HTML fetch catch sets `sawNetworkError`. Do not remove. |
| def-017 | `Sources/greendot/LaunchAtLogin.swift:13` | CERTAIN | LEGITIMATE | `SMAppService` catch logs. Do not remove. |
| def-018 | `Sources/greendot/AppDelegate.swift` | CERTAIN | LEGITIMATE | Panel add/edit `NSAlert` is the pattern. Now shared through `presentError`. |
| def-019 | `Sources/greendot/URLOpener.swift:31` | CERTAIN | LEGITIMATE | UI-test URL-log `try?`. Do not block `NSWorkspace.open`. |
| def-020 | `Sources/greendot/AppDelegate.swift:235` | CERTAIN | LEGITIMATE | UI-test dump `try? write`. Do not remove. |
| def-021 | parsers `compactMap` | CERTAIN | LEGITIMATE | Skip rows without names. Do not remove. |
| def-022 | `Sources/StatusCore/DirectoryHTTPClient.swift:18` | CERTAIN | LEGITIMATE | Fixture `Data(contentsOf:)` throws to the probe. Do not remove. |
| def-023 | Tests / UITests `try? FileManager.removeItem` | CERTAIN | LEGITIMATE | Teardown I/O. Do not remove. |
| def-024 | `Sources/StatusCore/Models.swift` | CERTAIN | LEGITIMATE | Fail-closed JSON decode. Do not remove. |
| def-025 | `Sources/StatusCore/HTTPClient.swift:15` | CERTAIN | LEGITIMATE | `URLSession.data` throws into `ProviderProbe`. Do not remove. |

No production change is pending from LEGITIMATE items. Revisit def-002 seed-add alert, def-004 poll save, def-006 probe log, and def-007 HTTP 5xx classification after verification.
