# RSS and Atom feeds

Date: 2026-09-02

This spec extends [2026-08-21-status-menu-design.md](2026-08-21-status-menu-design.md). It adds RSS 2.0 and Atom as a status-page provider. It does not add a second add path.

## What it is

The user pastes one URL. If that URL is an RSS or Atom feed, or HTML that advertises a feed, or the Microsoft service-health landing page, greendot watches it as one page. Feed items are components. Colour uses the same worst-enabled-leaf rule as Statuspage.

## Decisions

These decisions are settled. Do not re-open them in this slice.

| Topic | Decision |
|---|---|
| Scope | Any RSS 2.0 or Atom URL is a watched page. |
| Add | One URL still creates one watched page. |
| Shape | Items are components. No incident list for RSS (that would duplicate the tree). |
| Colour | Worst enabled leaf. No RSS-only colour policy. |
| Missing `<status>` | Green / Operational, except Azure status RSS (`*.azure.status.microsoft`) and AWS RSS (`status.aws.amazon.com` and subdomains), where items are incidents so missing `<status>` is yellow. Empty Azure or AWS feed stays green. A containing host does not match. |
| Unknown `<status>` | Yellow. Raw text is the status text. |
| Empty feed | No components. Overall green. |
| Microsoft landing | `https://status.cloud.microsoft/` (empty path) is one page named Microsoft, with three groups: Microsoft 365, Power Platform, Azure. |
| Microsoft feed URL | `/api/feed/mac` (or another single feed) is a normal one-feed page, not the hub. |
| HTML discovery | First `<link rel="alternate" type="application/rss+xml">` or `application/atom+xml`. |
| Probe order | JSON providers first. RSS last. Poll with `prefer: .rss` tries RSS first. |
| Clicks | Unchanged: page row, component row, and Open Status Page open the page URL. Do not add a URL field on `ComponentStatus`. |
| Auth | Still no tokens. A 401 on a JSON path is a miss. |

## Approaches

1. **RSS provider last, plus a Microsoft hub in the probe (chosen).** `RssParser` reads one feed into a flat component list. `ProviderProbe` tries RSS after Statuspal. The Microsoft landing URL fetches three known feeds and nests them as groups. `Monitor.add` does not grow a multi-page API.
2. Three watched pages from one Microsoft paste. Rejected: the menu would not match other providers (one URL, one row, tree underneath).
3. Feed URL only, no HTML discovery and no Microsoft hub. Rejected: the URL the user already tried would still fail.

## Mapping

| Input | Page name | `snapshot.url` | Components |
|---|---|---|---|
| RSS/Atom body | Channel/feed title, else host | Channel/feed link if http(s), else the pasted URL | One component per item |
| HTML with alternate | From the discovered feed | From the feed | Flat items |
| Microsoft landing | `Microsoft` | The landing URL | Three groups; each group's children are that feed's items |

Component id: item `guid`, else Atom `id`, else title. Group ids for the hub: `m365`, `ppac`, `azure`. Mute uses those ids, so a title change does not unmute a row.

`<status>` (case-insensitive):

| Raw | Severity | Status text |
|---|---|---|
| missing / empty | green | Operational |
| `available`, `operational`, `up`, `none`, `resolved` | green | Operational |
| `servicedegradation`, `degraded`, `degraded_performance`, `partial_outage` | yellow | Degraded |
| `maintenance`, `undermaintenance` | yellow | Maintenance |
| `serviceinterruption`, `full_outage`, `major_outage`, `majoroutage`, `critical`, `major`, `down`, `outage` | red | Major outage |
| anything else | yellow | the raw string |

Overall severity is `ComponentTree.enabledLeafSeverity` with no disabled keys. An empty group is a leaf (Azure with no items is green and does not pull the bar yellow). A failed hub feed is a grey group with no children.

## Probe

Order (default): Statuspage, Instatus, Flashduty, Statuspal, RSS.

RSS attempt:

1. If the normalized URL host is `status.cloud.microsoft` and the path is empty, fetch the hub feeds. Do not require the landing HTML.
2. Else GET the pasted URL.
3. If the body looks like RSS or Atom (`<rss` or `<feed` as a tag in the first 512 bytes), parse it as a flat page.
4. Else if the body is HTML, take the first alternate RSS/Atom link, resolve it against the page URL, GET it, parse it as a flat page.
5. Else miss.

Hub feeds (hardcoded; do not scrape JavaScript):

- `m365` / Microsoft 365 → `{base}/api/feed/mac`
- `ppac` / Power Platform → `{base}/api/feed/ppac`
- `azure` / Azure → `https://rssfeed.azure.status.microsoft/en-us/status/feed/`

Look-like-feed must not match `<feedback`. Use a tag pattern: `<rss` or `<feed` followed by space, `>`, or `/`.

XML parse uses Foundation `XMLDocument` with `nodeLoadExternalEntitiesNever`. Invalid XML is a miss (`ParserError.notThisProvider`), not a crash.

`lastBodies` for a hub is the three feed bodies joined with a delimiter so an unchanged re-poll skips parse, same as JSON.

## Failures

| Case | Result |
|---|---|
| Single feed GET fails (network / 429 / 5xx) | `ProbeError.unreachable` if nothing else matched |
| Single feed 404 or non-feed 200 | miss; `unsupported` if nothing else matched |
| Hub: all three feeds fail to parse or return non-feed | miss / unreachable from the flags |
| Hub: at least one feed parses | snapshot; failed feeds are grey groups |
| JSON matches | RSS is not used |

Add-panel error for a full miss stays `ProbeError.unsupported`, with RSS/Atom named in the text:

`This URL is not a known status page format (Statuspage, Statuspal, Instatus, Flashduty, or RSS/Atom).`

## Files

- Create `Sources/StatusCore/RssParser.swift` — one feed → `PageSnapshot` with `provider: .rss`.
- Create `Sources/StatusCore/ProviderProbe+RSS.swift` — RSS attempt, HTML alternate, Microsoft hub.
- Modify `Sources/StatusCore/Models.swift` — `StatusProvider.rss`.
- Modify `Sources/StatusCore/StatusMapping.swift` — `rss` / `rssText`.
- Modify `Sources/StatusCore/ProviderProbe.swift` — probe order and dispatch; error text.
- Test `Tests/StatusCoreTests/RssParserTests.swift`
- Test `Tests/StatusCoreTests/RssProbeTests.swift`
- Modify README, CHANGELOG, and the 2026-08-21 providers row to list RSS.

Do not add a URL on `ComponentStatus`. Do not change `Monitor.add` to return multiple pages.

## Tests

Seams: parser (bytes → snapshot), probe (URL + HTTP responses → snapshot or error).

Parser:

- RSS 2.0 with `<status>ServiceDegradation</status>` → yellow component, id from guid, overall yellow, no incidents.
- RSS item with no status → green / Operational.
- Empty channel → green, no components.
- Atom entry with no status → green; id from `<id>`; link from `href`.
- JSON body throws `notThisProvider`.

Probe:

- Feed URL 200 RSS → `.rss` snapshot.
- HTML 200 with alternate link → GET that feed, `.rss`.
- `https://status.cloud.microsoft/` → one snapshot named Microsoft, three groups; M365 child uses the mac feed item.
- Same host with path `/api/feed/mac` → flat page, not three groups.
- Statuspage JSON 200 on a host that also has RSS → `.statuspage` (JSON wins).
- `prefer: .rss` on the Microsoft landing GETs only the three hub feeds.
- Hub with two good feeds and one 503 → snapshot; Azure group grey; overall from the real feeds.
- Unknown HTML with no alternate → `unsupported`.

## Out of this slice

- HTML scrape of status (not feed discovery).
- Category-based grouping on generic feeds.
- Per-component click URLs.
- A general hub table for other vendors.
- Tokens / authenticated Microsoft Graph service health.
