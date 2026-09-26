# Settings files

greendot keeps two files in `~/Library/Application Support/greendot/`.

| File | Holds | Copy it to another Mac |
|---|---|---|
| `config.json` | Your settings. The watched pages, the component selections, and the poll interval. | Yes |
| `state.json` | Data for this Mac only. The last poll result for each page, and the launch-at-login flag. | No |

greendot sets mode `0600` on both files each time it reads them. A file that you
copy in with a wider mode is made private at once.

greendot writes a file only when its contents change.

## Find the files

Open the greendot menu. Click Reveal Config File. The Finder shows
`config.json`. greendot creates the file first if it does not exist.

To use a different directory, set the `GREENDOT_CONFIG_DIR` environment
variable to the path of that directory. The tests use this variable.

## config.json

The file is pretty-printed. The keys are sorted. The same settings always give
the same bytes, so the file gives a clean diff.

```json
{
  "pages" : [
    {
      "disabledComponentNames" : [
        "Ads API",
        "Sora"
      ],
      "id" : "0AB976B6-E45E-4C78-951E-570B9957D458",
      "name" : "OpenAI",
      "notificationsEnabled" : true,
      "url" : "https://status.openai.com"
    }
  ],
  "pollSeconds" : 60,
  "version" : 2
}
```

| Key | Type | Meaning |
|---|---|---|
| `version` | number | The format of the file. greendot writes `2`. |
| `pollSeconds` | number | The time between polls, in seconds. |
| `pages` | array | The watched pages, in menu order. |

Each item in `pages`:

| Key | Type | Meaning |
|---|---|---|
| `id` | string | A UUID. It connects the page to its cached result in `state.json`. |
| `url` | string | The URL of the status page. |
| `name` | string | The name in the menu. |
| `notificationsEnabled` | boolean | `true` shows a notification when the colour of the page changes. |
| `disabledComponentNames` | array of strings | The components to ignore. A value is a component `id` or a component `name`. The array is sorted. |

### Missing or bad values

greendot accepts a file that is not complete:

- A missing `version` is read as version 2.
- A missing `pollSeconds`, or a value that is zero or below, becomes 60 seconds.
- A missing `pages` becomes an empty list.
- A `pollSeconds` of the wrong JSON type becomes 60 seconds.
- A page without an `id` gets a new `id`. The second of two pages with the same
  `id` gets a new `id`. greendot writes the file again only when it changed an
  `id`.
- A missing `notificationsEnabled` is read as `true`. A missing
  `disabledComponentNames` is read as an empty list.

`pollSeconds` is the only key that accepts the wrong JSON type. greendot refuses
the file when a different key holds the wrong type, for example
`"notificationsEnabled": "yes"`, `"version": "2"`, `"pages": {}`, or an `id` that
is not a string.

greendot also refuses a file that is not valid JSON, a file with a `version`
above 2, and a file with a page that has no `url` or no `name`. See
[When greendot cannot read the file](#when-greendot-cannot-read-the-file).

## state.json

This file is the cache for one Mac. Do not copy it to another Mac. You do not
need to read it or edit it. It is listed here so that you know what it holds.

The example below is shortened. A real file holds one entry for each page, and a
page can hold many components. The empty arrays are written on one line here.
greendot writes an empty array across two lines.

```json
{
  "didSetLaunchAtLogin" : true,
  "snapshots" : {
    "0AB976B6-E45E-4C78-951E-570B9957D458" : {
      "snapshot" : {
        "components" : [
          {
            "children" : [],
            "id" : "01JMXBNJXG1S2D9V65P1ZZTD94",
            "isGroup" : false,
            "name" : "API",
            "severity" : "green",
            "statusText" : "Operational"
          }
        ],
        "incidents" : [],
        "isUnreachable" : false,
        "name" : "OpenAI",
        "overall" : "green",
        "provider" : "statuspage",
        "url" : "https://status.openai.com"
      },
      "url" : "https://status.openai.com"
    }
  },
  "version" : 2
}
```

| Key | Type | Meaning |
|---|---|---|
| `version` | number | The format of the file. greendot writes `2`. |
| `didSetLaunchAtLogin` | boolean | `true` after greendot set the login item once. It stops greendot from setting the item again. |
| `snapshots` | object | The last poll result for each page. The key is the page `id` from `config.json`. |

Each value in `snapshots` holds the page `url` and the `snapshot`. greendot uses
a cached result only when its `url` is the same as the `url` of the page in
`config.json`. A URL that you change by hand starts with no cached result.

A `severity` is `green`, `yellow`, `red`, or `grey`. A `provider` is
`statuspage`, `statuspal`, `instatus`, `flashduty`, `aws`, `icinga`, `okta`,
`salesforce`, `statusio`, `slack`, `heroku`, `google`, `apple`, `incidentio`,
`concur`, `adobe`, `azuredevops`, `n8n`, `zscaler`, or `rss`. A `grey` severity
with `isUnreachable` set to `true` is a page that greendot could not read.

## Edit config.json by hand

1. Open the greendot menu. Click Reveal Config File.
2. Edit the file. Save it.

greendot loads the file, builds the menu again, starts the poll timer again,
and polls one time. If Add, Edit, or Remove is open, greendot waits until that
window closes, then loads the file. Component choices in that window are written
when the window closes.

greendot does not write over a `config.json` that changed on disk after it last
read or wrote the file. It loads that file instead. Click Reload Config to load
the file before the next poll.

### When greendot cannot read the file

greendot shows an alert and keeps the pages that are on screen. It stops polling
and blocks changes from the menu. Nothing is written, so a poll or a menu change
cannot write the old settings over the file that you correct. Correct the file
and click Reload Config.

## Copy your settings to another Mac

Copy `config.json` only.

1. On the first Mac, open the greendot menu. Click Reveal Config File.
2. Copy `config.json` to the same folder on the other Mac.
3. On the other Mac, open the greendot menu. Click Reload Config. If greendot
   does not run, start it.

The dots stay grey until the first poll ends, which usually takes a few seconds.

Quit greendot on the other Mac before you copy the file, or click Reload Config
immediately after. greendot on the other Mac keeps its own `state.json`, so its
cached results and its login-item flag do not change.

### A URL can hold a token

A feed URL can hold a token, for example `?token=abc123`. greendot keeps the
query, and the token with it. Read the URLs in `config.json` before you send the
file to another person.

When you add or edit a page, greendot adds `https://` to a URL that has no
scheme, and removes a fragment, which is the part after a `#`. It makes no other
change. A URL that you write into `config.json` by hand is used as you wrote it.

## The poll interval

`pollSeconds` in `config.json` sets the time between polls. The default is 60
seconds. Set the `GREENDOT_POLL_SECONDS` environment variable to a number of
seconds to override the file.

## Upgrade from version 1

Version 1 kept one file. That `config.json` held the settings and also the data
for the Mac: each page carried its poll result in a `snapshot` key, and a
`didSetLaunchAtLogin` key sat at the top level.

**To upgrade, replace the app and start it. greendot does the rest.** It keeps
each page with its `id`, `url`, `name`, `notificationsEnabled` and
`disabledComponentNames`, in the same order. It moves the poll results to
`state.json`. It keeps the launch-at-login flag, so greendot does not set your
login item again. A file from a version of greendot before
`disabledComponentNames` also loads.

greendot writes the two files at the next save, not at the moment it reads the
version 1 file. A save happens when a poll result differs from the cached one,
when you change a setting, or when greendot repairs a page `id`. Until then the
version 1 file stays on disk. This does no harm, because greendot reads it
correctly at each start.

A version 2 `config.json` that still holds a `snapshot` or a
`didSetLaunchAtLogin` key ignores them, even when they hold the wrong type. Data
for one Mac comes from `state.json` only.

### The upgrade goes one way

An older app cannot read a version 2 `config.json`. It shows an alert and an
empty menu. To correct this, install the newer app again.

### Two cases to know about

- greendot writes `config.json` first and `state.json` second. If the Mac stops
  between the two writes, the next start finds no `state.json`. Your pages stay.
  The dots are grey until the first poll. greendot treats the start as a first
  run, so it can set your login item again.
- A `config.json` with no `version` key is read as version 2. greendot writes
  version 1 files with `"version": 1`, so this affects a file that you edited by
  hand. The poll results in the file are dropped, and greendot treats the start
  as a first run.

In both cases the pages, the names and the component selections stay.
