# status-app

A macOS menu bar app. You add a status-page URL. The app polls that page on an interval and shows the status in the menu bar.

## What the app does

- You enter the URL of a software or SaaS status page.
- The app adds that page to the menu bar with a status icon.
- The menu has one item for the app and a submenu for each added page.
- The app polls each page on a regular interval.
- If a page goes yellow or red, the menu-bar icon goes yellow or red.
- Optional notifications fire when a status changes and when it clears.
- The app can monitor internal status pages.

## Status page formats

The app will support common public JSON status APIs, including:

- Atlassian Statuspage (`/api/v2/summary.json`)
- Statuspal
- Other common status-page products that expose a JSON summary

## Status

This repository is new. Design and implementation are in progress.

## License

Private. All rights reserved.
