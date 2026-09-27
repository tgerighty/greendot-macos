# greendot

A macOS menu-bar app. You add a status-page URL. The app polls the page and shows a green, yellow, or red dot in the menu bar.

On first launch it adds [OpenAI Status](https://status.openai.com/) so you can see it working.

## What it does

- Add the public URL of a SaaS or internal status page.
- The menu lists each page. The submenu lists that page's components.
- The app polls every 60 seconds.
- The menu-bar icon uses the worst real status (red > yellow > green).
- A fetch failure is grey. If any page is grey, the icon flashes grey for one second every 30 seconds.
- Optional per-page notifications. A page gives one notification when it stops being green, and one when it becomes green again. While the page stays unhealthy, a change of colour rewrites the notification without a sound.
- One network notification when the Mac loses its network, and one when it comes back. greendot asks the system for the network state and also confirms a poll that finds only some pages unreachable, so a drop that reaches the pages over two polls still gives one notification.
- Launch at login is on by default.

v1 parsers: Atlassian Statuspage, Statuspal, Instatus, Flashduty, Status.io, Slack, Heroku, Google Cloud/Workspace/Firebase, Apple System Status, incident.io, AWS Health, Icinga 2 API, Okta Trust, Salesforce Trust, RSS 2.0, and Atom. Paste https://health.aws.amazon.com/health/status or https://status.aws.amazon.com/ for one page named AWS. Paste https://status.okta.com/ for Okta. Paste https://status.salesforce.com/ for Salesforce. Paste https://status.gitlab.com/ for Status.io. Paste https://slack-status.com/ for Slack. Paste https://status.heroku.com/ for Heroku. Paste https://status.cloud.google.com/ or the Google Workspace status dashboard for Google. Paste https://www.apple.com/support/systemstatus/ for Apple. Paste https://status.stripe.com/ for Stripe. Paste https://open.concur.com/ for SAP Concur. Paste https://status.adobe.com/ for Adobe. Paste https://status.dev.azure.com/ for Azure DevOps. Paste https://status.n8n.cloud/ for n8n. Paste https://trust.zscaler.com/ for Zscaler. Paste https://status.qlikcloud.com/ for Qlik Cloud. Paste https://status.bitbar.com/ for BitBar. Paste an Icinga 2 API URL as `https://user:password@host:5665/v1` (the password is the API key). HTML scrape of status (not feed discovery) is next.

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
[2026-09-26 performance report](docs/performance-report-2026-09-26.md)
for the latest benchmark results. The
[2026-08-29 performance report](docs/performance-report-2026-08-29.md)
records the earlier measurement.

## Config

greendot keeps two files in `~/Library/Application Support/greendot/`.

| File | Contents |
|---|---|
| `config.json` | Your settings. The watched pages, the component selections, and `pollSeconds`. |
| `state.json` | The cache for this machine. The last poll result for each page, and the launch-at-login flag. |

Both files use mode `0600`. greendot writes a file only when its contents change.

To copy your settings to another Mac, copy `config.json`. Do not copy
`state.json`. To edit a file, click Reveal Config File in the menu and edit the file.
greendot loads the file when it changes. If Add, Edit, or Remove is open,
greendot loads the file when that window closes.

To upgrade from a version of greendot that kept one file, replace the app and
start it. greendot keeps your pages, your component selections and your
launch-at-login setting.

`pollSeconds` sets the time between polls. The default is 60 seconds. Set
`GREENDOT_POLL_SECONDS` to override the file. Set `GREENDOT_CONFIG_DIR` to use
another directory.

A feed URL can hold a token, for example `?token=abc123`. An Icinga URL can hold
a username and password. Read the URLs in `config.json` before you send the file
to another person.

See [Settings files](docs/settings-files.md) for each key in both files, the
rules for a file that is not complete, and the upgrade in full.

## License

Copyright © 2026 Terry Gerighty. All rights reserved.
