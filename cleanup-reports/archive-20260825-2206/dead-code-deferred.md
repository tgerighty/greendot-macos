# Dead Code Deferred

Date: 2026-08-21
Source: `cleanup-reports/dead-code-assessment.md`

These findings were **not** applied. The apply pass only removes items with `verified: true` and `recommendation: REMOVE`. LIKELY, REVIEW, KEEP, and unverified items stay.

| ID | File | Confidence | Recommendation | Why deferred |
|---|---|---|---|---|
| dead-005 | `Resources/Info.plist:27` | LIKELY | REVIEW | `NSUserNotificationAlertStyle` may still control banner style on some macOS versions. Confirm banners from `UNUserNotificationCenter` alone before delete. File is not on the apply allowlist. |
| dead-006 | `Resources/AppIcon.png` | LIKELY | REVIEW | PNG is not in the build, but it is likely the icns master. Do not delete without an icon source-of-truth. File is not on the apply allowlist. |
| dead-007 | `Sources/greendot/PagePanelController.swift:9` | LIKELY | REVIEW | Empty `NSWindowDelegate` conformance. `window.delegate` is still set and cleared. `closeWindow()` is live. File is not on the apply allowlist. |
| dead-008 | `Sources/greendot/AppDelegate.swift:169` | UNCERTAIN | KEEP | `com.tgerighty.greendot.showMenu` is a DistributedNotificationCenter hook. No in-repo poster is not proof that the path is dead. Never delete DNC observers. |
| dead-009 | `.gitignore:18` / `.swiftlint.yml:8` | LIKELY | REMOVE | Stale `Status Menu.app` ignore rules. Config-only leftover. Not `verified: true`, and those files are not on the apply allowlist. |

No production behaviour change is pending from this list. Revisit after a banner-style check (dead-005), an icon pipeline decision (dead-006), and a separate config cleanup (dead-009).
