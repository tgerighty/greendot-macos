# greendot

A macOS menu-bar app. You add a status-page URL. The app polls the page and shows a green, yellow, or red dot in the menu bar.

On first launch it adds [OpenAI Status](https://status.openai.com/) so you can see it working.

## What it does

- Add the public URL of a SaaS or internal status page.
- The menu lists each page. The submenu lists that page's components.
- The app polls every 60 seconds.
- The menu-bar icon uses the worst real status (red > yellow > green).
- A fetch failure is grey. If any page is grey, the icon flashes grey for one second every 30 seconds.
- Optional per-page notifications when overall status changes, including recovery.
- Launch at login is on by default.

v1 parsers: Atlassian Statuspage, Statuspal, Instatus, Flashduty. HTML scrape is next.

## Build

```bash
make test
make bench      # release-mode benchmarks with local fixtures
make app
make install
make uitest    # local GUI session; needs Accessibility for the test runner
```

Requires macOS 13+ and Xcode.

See the
[2026-08-29 performance report](docs/performance-report-2026-08-29.md)
for the benchmark method and measured results.

## Config

Pages are stored in `~/Library/Application Support/greendot/config.json`.

Set `GREENDOT_CONFIG_DIR` to use another directory (UI tests do this).

## License

Copyright © 2026 Terry Gerighty. All rights reserved.
