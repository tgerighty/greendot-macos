# Changelog

## [Unreleased]

### Added

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
