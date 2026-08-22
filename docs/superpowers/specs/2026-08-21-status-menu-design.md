# greendot design

Date: 2026-08-21

Product name: greendot
Bundle ID: `com.tgerighty.greendot`
GitHub: `https://github.com/tgerighty/greendot` (private)
Project key for SonarQube: `tgerighty_greendot`

## What it is

greendot is a macOS menu-bar app. You add the URL of a software status page. The app polls that page and shows the status in the menu bar. First launch adds https://status.openai.com/. The app icon is a plain green status dot.

## Decisions

These decisions are settled. Do not re-open them in v1.

| Topic | Decision |
|---|---|
| Audience | Personal local-first app. The same binary can be given to a teammate. No accounts. No cloud. |
| Auth | Reachable URL only (VPN/LAN). No token, basic auth, or SSO in v1. |
| Stack | Native Swift. AppKit `NSStatusItem`. Testable core with no AppKit. |
| Menu | Bar icon = worst real status. Top level = one row per page. Submenu = components, like the ChatGPT status screenshot. |
| Providers | Atlassian Statuspage, Statuspal, Instatus. HTML scrape is the next slice, not v1. |
| Notifications | Per-page toggle. Default on. Toast when that page's overall colour changes, including recovery. |
| Chrome | Menu bar only. No Dock. No settings window. Launch-at-login default on. About greendot opens the native About panel. Copyright © 2026 Terry Gerighty. All rights reserved. The build number is the GitHub commit hash. |
| Poll | 60 seconds, global. |
| Colours | Green = operational. Yellow = degraded / minor / maintenance. Red = major or critical. Fetch failure = grey. |
| Mixed icon | red > yellow > green. Grey never drives the bar unless no page has a real status. |
| Grey hint | If any page is grey and the bar is not already grey, flash the bar icon grey for 1 second every 30 seconds. |
| Add | Menu item opens a small panel. Paste the human status URL. The app probes JSON endpoints. |
| Edit | Submenu item opens the same panel with URL and name filled. |
| Click | Page row, component row, or Open Status Page opens the page URL in the default browser. |
| Out of v1 | HTML scraper, tokens/SSO, iCloud, App Store/Homebrew, widgets, graphs, per-page poll, component toasts, Dock, settings window. |

## Approaches

1. **StatusCore library + AppKit status item (chosen).** Core is Foundation-only and is tested with `swift test`. The app is a thin menu, panel, notification, and login-item shell. The 30-second grey pulse needs direct control of the status-item image, which `NSStatusItem` gives.
2. SwiftUI `MenuBarExtra` only. Weaker control of timed icon colour. Rejected.
3. Electron/Tauri. Rejected in Q4.

## Architecture

```
URL  ->  HTTPClient  ->  ProviderProbe  ->  Parser  ->  PageSnapshot
                                                          |
WatchedPage store  <->  Monitor  <->  Aggregator / GreyPulse / Toast policy
                                                          |
                                              greendot (NSStatusItem, panel, UNUserNotification, SMAppService)
```

StatusCore owns models, parsers, probe, store, poll, aggregation, pulse, and toast decisions.

greendot owns the menu, the add/edit panel, drawing the icon, posting notifications, and launch-at-login.

## Domain

Severity, worst first: red, yellow, green. Grey is not in that order. Grey wins the bar only when every watched page is grey, or the list is empty after a fetch failure with no other pages.

A watched page has: id, url, name, notificationsEnabled, last snapshot.

A snapshot has: overall severity, components (name, severity, status text), active incidents (title, url), page URL, unreachable flag.

## Providers

The user pastes the human URL (`https://www.githubstatus.com`), not the JSON URL.

Probe order:

1. `{base}/api/v2/summary.json` — Atlassian Statuspage if the JSON has `status.indicator`.
2. `{base}/summary.json` — Instatus if the JSON has `page.status`.
3. Statuspal JSON: `{statuspal-host}/api/v2/status_pages/{subdomain}/summary`. Subdomain comes from `*.statuspal.io` / `*.statuspal.eu`, or from the HTML of `{base}` if it names Statuspal.

If none match, the add panel shows an error. It does not scrape HTML for status in v1.

Statuspage indicator: `none` green, `minor` yellow, `major`/`critical` red. Component `operational` green, `degraded_performance`/`partial_outage`/`under_maintenance` yellow, `major_outage` red. Skip component groups.

Statuspal `current_status_type`: null green, `minor`/`scheduled` yellow, `major` red. Flatten nested services to leaves.

Instatus `page.status`: `UP` green, `UNDERMAINTENANCE` yellow, `HASISSUES` yellow unless an active incident impact is a major outage, then red.

## Persistence

JSON file under `~/Library/Application Support/greendot/config.json`, mode `0600`.

`GREENDOT_CONFIG_DIR` overrides the directory so UI tests never touch the real config.

## First launch

If there is no config file and `GREENDOT_SKIP_LOGIN_ITEM` is not set, register launch-at-login. First launch also adds https://status.openai.com/.

## TDD

Red-green. No production code without a failing test first.

Seams (the only unit-test surface):

1. Parser: JSON bytes → snapshot.
2. Probe: URL + HTTP responses → provider or error.
3. Aggregator: snapshots → bar severity.
4. Grey pulse: persistent colour + has-grey + time → displayed colour.
5. Toast policy: previous snapshot + new snapshot + toggle → toast or none.
6. Store: add / edit / remove / load round-trip.
7. Monitor: add probes and saves; poll updates snapshots; edit changes URL/name; remove drops the page.

Do not unit-test AppKit. XCUITest covers the menu, panel, add, edit, remove, notification toggle, launch-at-login item, and open-page item.

## SonarQube

Canonical rules: `~/coding/sonarcubeguide.md` (this file replaces `sonarqube.md`).

- Project key: `tgerighty_greendot`.
- The fleet discovers the GitHub repo. No manual registration.
- Native SonarQube has no Swift analyzer. A green `main` baseline is vacuous unless extras import.
- PR gates are real for Swift: SwiftLint (`external_swiftlint:*`) and opengrep-swift (`external_opengrep-swift:*`) import on every PR.
- Do not run `sonar-scanner` with the analysis cache on. Fleet scans already set `sonar.analysisCache.enabled=false`.
- There is no Swift coverage loop. Do not invent a vitest/pytest config to fake coverage. Do not exclude product code from analysis.
- Keep a `.swiftlint.yml` and `sonar-project.properties` with `sonar.sources=Sources` and tests excluded from source.
- Gitleaks is `import` on `main` for allowlisted repos only; still keep secrets out of the tree.
- To close a finding: fix the code. Do not try to transition issues with the read token.

## UI test on this Mac

`make uitest` builds the `.app` and runs XCUITest against the real menu bar. Tests set `GREENDOT_FIXTURE_DIR`. The app then uses `DirectoryHTTPClient` to read fixture files. The tests do not start an HTTP server. Tests must cover: launch with no dock icon, add, submenu components, edit name/URL, notification toggle, remove, launch-at-login menu item, quit. They use a scratch config directory.
