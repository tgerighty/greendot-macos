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
- One network notification when every page goes unreachable at once, and one when they come back.
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

To copy your settings to another Mac, copy `config.json`. Do not copy
`state.json`. To edit a file, click Reveal Config File in the menu, edit the
file, then click Reload Config.

To upgrade from a version of greendot that kept one file, replace the app and
start it. greendot keeps your pages, your component selections and your
launch-at-login setting.

`pollSeconds` sets the time between polls. The default is 60 seconds. Set
`GREENDOT_POLL_SECONDS` to override the file. Set `GREENDOT_CONFIG_DIR` to use
another directory.

A feed URL can hold a token, for example `?token=abc123`. Read the URLs in
`config.json` before you send the file to another person.

See [Settings files](docs/settings-files.md) for each key in both files, the
rules for a file that is not complete, and the upgrade in full.

## License

Copyright © 2026 Terry Gerighty. All rights reserved.
