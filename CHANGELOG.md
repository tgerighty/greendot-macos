# Changelog

## [Unreleased]

### Changed

- Red, yellow, and grey status-change notifications stay on screen until you click them away. Green notifications clear themselves after 6 seconds.
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

- `make bench` times the shipped parse, poll, menu, and status-dot paths on in-memory fixtures (no live network).
- About greendot in the status menu and the application menu opens the native About panel. The copyright line is Copyright © 2026 Terry Gerighty. All rights reserved. The build number is the short GitHub commit hash.
- Click a page row, a component row, or Open Status Page to open that page in the default browser.
- UI tests exercise every Edit checkbox five times and switch Edit between two pages five times, without moving the pointer (avoids the bottom-left hot corner).

### Changed

- Add Status Page reports "Could not reach that URL" when the host is down, not a format error.
- A corrupt saved page list shows an alert and is not overwritten by first-run seed or poll.

### Fixed

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
