# Changelog

## [Unreleased]

### Added

- Reveal Config File and Reload Config in the status menu. Reveal Config File shows `config.json` in the Finder. Reload Config reads the file again, rebuilds the menu, restarts the poll timer, and polls once. A file that greendot cannot read shows an alert and keeps the pages on screen.
- `state.json` holds the cached poll results and the launch-at-login flag. `config.json` holds only your settings, so you can copy it to another machine or send it to a colleague. greendot reads a version 1 file and splits it on the next save.
- `pollSeconds` in `config.json` sets the time between polls. The default is 60 seconds. `GREENDOT_POLL_SECONDS` still overrides the file.

### Changed

- A hand-edited `config.json` loads. greendot gives a page without an `id` a new one, and gives a repeated `id` a new one. It rewrites the file only when it changed an `id`.
- `config.json` is pretty-printed with sorted keys and plain slashes. `disabledComponentNames` is written as a sorted array. The same settings always produce the same bytes, so the file diffs cleanly.
- Nested component checkbox refreshes now calculate subtree states in one pass.
  Release benchmark, 160-level tree and 20 clicks: 360.462 ms before, 6.781 ms
  after (five-run median).
- Display severity now scans enabled components directly without copied tree and
  leaf arrays. Release benchmark, 840 components and 500 reads: 56.431 ms
  before, 3.777 ms after (five-run median).
- `make bench` now benchmarks the release configuration and includes nested
  component selection and large-tree severity workloads.
- Red, yellow, and grey status-change notifications stay on screen until you click them away. Green notifications clear themselves after 6 seconds.
- A persistent alert is cleared when you turn Notifications off for that page, or when a component filter change makes the page green. If the page stays yellow or red, the alert is updated to that colour.
- A green notification that a quit cut short is cleared the next time greendot starts.
- Status-change notifications include a status-dot image in the issue colour (red, yellow, green, or grey).
- A first probe of a `*.statuspal.io` host does not GET the HTML page (the host already names the subdomain). First-probe GETs: 4 before, 3 after (second after run 3).
- The status menu is reused when the watched pages do not change. 80 identical builds: 80 unique menus before, 1 after (second after run 1).
- The Statuspal subdomain regex is compiled once. 500 extracts: 500 compiles before, 1 after (second after run 1).
- A re-poll with an unchanged response body does not parse JSON again. Second poll of three pages: 3 parses before, 0 after (second after run 0).
- The 4 Hz icon pulse does not refresh when every page is reachable. 240 ticks: 240 refreshes before, 0 after (second after run 0). Unreachable pages still flash grey.
- Status-dot images are reused per colour and size. 2000 constructions of the four bar colours: 2000 unique images before, 4 after (second after run 4). Construction time 1.14 ms before, 0.37 ms after (second after run 0.39 ms).
- An unchanged poll does not rewrite `config.json` (1 rewrite before, 0 after). A status change still writes.
- Refresh waits for the slowest watched page, not the sum of page waits. Three pages with an 80 ms probe delay: 253 ms before, 87 ms after (second after run 87 ms).
- A later poll of a known Statuspal or Instatus page does not GET the other providers. Mixed three-page re-poll: 7 GETs before, 3 after.

### Added

- AWS Health status pages. Paste https://health.aws.amazon.com/health/status or https://status.aws.amazon.com/. One page named AWS. Current events are groups. Impacted services are children. Empty is green. RSS on status.aws.amazon.com with no status is yellow.
- RSS 2.0 and Atom feeds. Paste a feed URL, HTML that advertises a feed, or https://status.cloud.microsoft/. Items are components. A `<status>` tag sets colour; a missing tag is operational. The Microsoft landing page is one watched page with Microsoft 365, Power Platform, and Azure as groups.
- Flashduty status pages (for example https://status.deepseek.com). The app reads `{page}/api/widget/v1/summary.json`. The bar uses overall status. Active incidents and in-progress maintenance appear in the menu. Component lists stay empty because that feed has no component tree.
- `make bench` times the shipped parse, poll, menu, and status-dot paths on in-memory fixtures (no live network).
- About greendot in the status menu and the application menu opens the native About panel. The copyright line is Copyright © 2026 Terry Gerighty. All rights reserved. The build number is the short GitHub commit hash.
- Click a page row, a component row, or Open Status Page to open that page in the default browser.
- UI tests exercise every Edit checkbox five times and switch Edit between two pages five times, without moving the pointer (avoids the bottom-left hot corner).

### Changed

- Add Status Page reports "Could not reach that URL" when the host is down, not a format error.
- A corrupt saved page list shows an alert and is not overwritten by first-run seed or poll.

### Fixed

- An RSS description with characters that change length when lowercased (for example `İ`) no longer reads the status token from the wrong position or crashes.
- RSS items that put severity in `<category>` or in the description (for example
  https://status.x.ai) now set the colour. An active `outage` is red. A
  `disruption` is yellow. `Status: RESOLVED` in the description stays
  operational. Unrecognized category tags are ignored, so a region or product
  name does not turn the bar yellow.
- Red, yellow, and grey status-change toasts stay on screen until you click them. macOS UserNotifications banners always time out; those colours now use an app-owned panel. Green toasts still clear after 6 seconds.
- A watched RSS or HTML URL keeps its query string after save, so later polls use the same feed.
- An HTML page that advertises `feed.xml` as a relative link uses the pasted directory URL, not a slash-stripped host root.
- A yellow or red toast for one watched page does not replace a toast for a different page that has the same name.
- When more persistent toasts are raised than fit on screen, the extras wait and return when you click one away. A later change for a waiting page updates that waiting toast. Recovery to green clears the persistent toast for that page.
- HTML feed links that encode `&` as `&amp;` still fetch the correct URL.
- HTML feed links with an unquoted `href` work. A `data-href` attribute is not treated as the feed URL.
- If an HTML status page redirects on the same host, relative feed links use the final URL. A same-host HTTP to HTTPS upgrade is followed. A redirect to another host, to HTTP from HTTPS, or to a different port is not followed. An HTTPS page does not fetch an HTTP or different-port alternate feed.
- Alternate feed links inside HTML comments, `<script>`, `<style>`, or `<template>` are ignored, including closing tags with spaces before `>`.
- HTML `rel` matching requires the complete `alternate` token, so `notalternate` is not treated as a feed.
- Each HTTP redirect is checked against the previous hop, so an HTTP to HTTPS upgrade cannot then drop back to HTTP.
- If a feed stays the same bytes but moves to another same-origin URL, the stored page URL follows the new location.
- A `<feed>` root is treated as Atom only when it uses the Atom namespace.
- The Azure missing-status exception applies only to `azure.status.microsoft` and its subdomains.
- If an HTML page contains feed-shaped text that is not a real feed, discovery still uses the advertised alternate link.
- Editing or removing a watched page clears that page's persistent alert. The submenu Remove path does this too.
- RSS and Atom feeds encoded as UTF-16 are still recognised.
- Feed sniffing still works when a UTF-8 prefix is cut in the middle of a character.
- An Atom `rel="hub"` or `rel="enclosure"` link is not stored as the page URL. A later `rel="alternate"` link beats an earlier `rel="self"` link.
- Click the overall status row (for example Operational) to open the page when a watched page has no components.
- Menu and Edit store errors no longer leave memory changed when the file write fails.
- Edit checkboxes stay in the last saved state when a store write fails.

### Security

- Open Status Page and row clicks open only http and https URLs.
- Fixture HTTP client rejects paths that leave the fixture directory.
- UI-test notifications require a config directory; dump files must stay inside it.

### Added

- greendot v1: macOS menu-bar monitor for Statuspage, Statuspal, and Instatus JSON status pages.
- Add, edit, and remove watched pages.
- First launch seeds https://status.openai.com/.
- Per-page notifications and launch-at-login.
- App icon is a plain green status dot.
- Edit dialog lists components; click a component to include or hide it. Remove Status Page sits at the bottom of that dialog.

- Status page groups (for example Box Web Application → Login/SSO) show as a nested menu and as indented checkboxes in Edit.
- Edit dialog has an All checkbox. Turning a group on or off turns every child on or off.

### Fixed

- Cut, copy, and paste work in the Add/Edit Status Page fields (Cmd+C / Cmd+V).
- Opening Edit for a second page no longer crashes (the previous dialog was released while the menu was still tracking).
- Edit no longer crashes on OpenAI: the window was released on close (`isReleasedWhenClosed`), then messaged again.
