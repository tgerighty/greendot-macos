# Changelog

## [Unreleased]

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
