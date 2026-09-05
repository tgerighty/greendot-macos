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

v1 parsers: Atlassian Statuspage, Statuspal, Instatus, Flashduty, AWS Health, RSS 2.0, and Atom. Paste https://health.aws.amazon.com/health/status or https://status.aws.amazon.com/ for one page named AWS. HTML scrape of status (not feed discovery) is next.

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

greendot keeps two files in `~/Library/Application Support/greendot/`.

| File | Contents |
|---|---|
| `config.json` | Your settings. The watched pages, the component selections, and `pollSeconds`. |
| `state.json` | The cache for this machine. The last poll result for each page, and the launch-at-login flag. |

Both files use mode `0600`. greendot writes a file only when its contents change.

### Copy your settings to another machine

Copy `config.json`. Do not copy `state.json`.

1. Open the greendot menu. Click Reveal Config File. The Finder shows `config.json`.
2. Copy the file to the same folder on the other machine.
3. On the other machine, open the greendot menu. Click Reload Config.

greendot reads the file again and polls the pages. The dots stay grey until the first poll ends. This takes about one second.

### Edit the file by hand

Open `config.json` in a text editor. The file is pretty-printed, and the keys are sorted. Save the file. Then click Reload Config.

greendot repairs a broken page list. It gives a page without an `id` a new `id`. It gives the second of two pages with the same `id` a new `id`.

### Poll interval

`pollSeconds` sets the time between polls. The default is 60 seconds. Set the `GREENDOT_POLL_SECONDS` environment variable to override the file.

Set `GREENDOT_CONFIG_DIR` to use another directory. The UI tests do this.

### Warning about tokens

A feed URL can contain a token, for example `?token=abc123`. greendot keeps the URL as you typed it. Read the URLs in `config.json` before you send the file to another person.

## License

Copyright © 2026 Terry Gerighty. All rights reserved.
