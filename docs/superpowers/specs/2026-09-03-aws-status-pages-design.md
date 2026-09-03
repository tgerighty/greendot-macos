# AWS status pages

Date: 2026-09-03

This spec extends [2026-09-02-rss-feeds-design.md](2026-09-02-rss-feeds-design.md). It adds the AWS Health Dashboard as one watched page, using the public current-events JSON. It does not add a second add path.

## What it is

The user pastes one AWS landing URL. greendot watches it as one page named AWS. Current events are groups. Impacted services are children. Colour uses the same worst-enabled-leaf rule as other providers.

## Decisions

These decisions are settled. Do not re-open them in this slice.

| Topic | Decision |
|---|---|
| Scope | Public AWS Health current events only. No account health. No tokens. |
| Add | One URL still creates one watched page. |
| Shape | Events are groups. Impacted services are children. No incident list (that would duplicate the tree). |
| Colour | Worst enabled leaf. |
| Empty feed | No components. Overall green. |
| Event with no impacted services | Group is a leaf with the event colour. |
| Landing URLs | `https://health.aws.amazon.com/health/status` (empty path also), `https://status.aws.amazon.com/` (empty path), `https://health.aws.amazon.com/public/currentevents`. |
| JSON URL | Always GET `https://health.aws.amazon.com/public/currentevents`. Do not scrape the SPA HTML. Do not follow the cross-host redirect from `status.aws.amazon.com`. |
| Click URL | The pasted landing URL, except a paste of `/public/currentevents` stores `https://health.aws.amazon.com/health/status`. |
| RSS on `status.aws.amazon.com` | Not the hub. One flat RSS page. Missing `<status>` is yellow, like Azure. Empty feed is green. Host match is exact or a subdomain, not a containing host. |
| Provider | `.aws`. Re-poll uses `prefer: .aws`. |
| Encoding | currentevents may be UTF-16 (BOM `FE FF` or `FF FE`) or UTF-8. |

## Approaches

1. **Landing short-circuit plus JSON parser (chosen).** `AwsParser` reads the current-events array. `ProviderProbe` detects the landing URL first, then GETs the one JSON URL. RSS on `status.aws.amazon.com` stays RSS, with the Azure missing-status rule.
2. Hub from `all.rss` only. Rejected: many duplicate incident updates, no service tree, no numeric status.
3. Hundreds of per-service RSS feeds. Rejected: too many GETs per poll.

## Mapping

| Input | Page name | `snapshot.url` | Components |
|---|---|---|---|
| Health landing | `AWS` | The landing URL | Event groups; children from `impacted_services` |
| `status.aws.amazon.com` empty path | `AWS` | That URL | Same |
| `/public/currentevents` | `AWS` | `https://health.aws.amazon.com/health/status` | Same |
| `/rss/s3-us-east-1.rss` | Channel title, else host | Channel link if http(s), else the pasted URL | Flat RSS items |

Event group:

- id: `arn`
- name: `{service_name} ({region_name})`. If `region_name` is missing or empty, use `service_name` only.
- severity / status text: from event `status`
- `isGroup`: true
- children: `impacted_services` entries

Child:

- id: map key (example `s3-me-central-1`)
- name: `service_name`
- severity / status text: from `current`
- `isGroup`: false

Skip an event object that has no `arn`. Skip a child that has no name.

`status` / `current` may be a string or a number.

| Raw | Severity | Status text |
|---|---|---|
| `0` | green | Operational |
| `1`, `2` | yellow | Degraded |
| `3` | red | Major outage |
| missing / empty / anything else | yellow | the raw string, or `Degraded` if missing |

Overall severity is `ComponentTree.enabledLeafSeverity` with no disabled keys.

## Probe

Landing detection runs before Statuspage, Instatus, Flashduty, Statuspal, and RSS. A URL is an AWS landing when the host and path match the table above. `/rss/...` on `status.aws.amazon.com` is not a landing.

On a hit, GET only `https://health.aws.amazon.com/public/currentevents`. Decode UTF-16 or UTF-8. Parse as this JSON array.

Identity: a JSON array. An empty array is a valid green page. A non-array body is a miss.

`lastBodies` for AWS is `HTTP {status}\n` plus the body, so an unchanged re-poll skips parse. A status change with the same bytes does not reuse the snapshot.

`prefer: .aws` on a landing GETs only currentevents. `prefer: .aws` on a non-landing URL is a miss (no GET), then the other providers run.

## Failures

| Case | Result |
|---|---|
| currentevents network / 429 / 5xx | `ProbeError.unreachable` |
| 404, non-JSON, or JSON that is not an array | miss; `unsupported` if nothing else matched |
| Landing host down before JSON | `unreachable` (the only GET is currentevents) |

Add-panel error for a full miss names AWS:

`This URL is not a known status page format (Statuspage, Statuspal, Instatus, Flashduty, AWS, or RSS/Atom).`

## Files

- Create `Sources/StatusCore/AwsParser.swift` — current-events array → `PageSnapshot` with `provider: .aws`.
- Create `Sources/StatusCore/ProviderProbe+AWS.swift` — landing check, currentevents GET, UTF-16 decode, cache body.
- Modify `Sources/StatusCore/Models.swift` — `StatusProvider.aws`.
- Modify `Sources/StatusCore/StatusMapping.swift` — `aws` / `awsText`.
- Modify `Sources/StatusCore/ProviderProbe.swift` — landing short-circuit, probe order, error text.
- Modify `Sources/StatusCore/RssParser.swift` — missing-status yellow for `status.aws.amazon.com` and its subdomains.
- Test `Tests/StatusCoreTests/AwsParserTests.swift`
- Test `Tests/StatusCoreTests/AwsProbeTests.swift`
- Modify RSS parser tests for the AWS host exception.
- Modify README, CHANGELOG, and the RSS spec AWS RSS row.

Do not add a URL on `ComponentStatus`. Do not change `Monitor.add` to return multiple pages. Do not scrape HTML.

## Tests

Seams: parser (bytes → snapshot), probe (URL + HTTP responses → snapshot or error).

Parser:

- Two events, first with one impacted service `current: "3"` → group name `Multiple services (UAE)`, child id `s3-me-central-1`, child red, overall red, provider `.aws`, no incidents.
- Empty array → green, no components, name `AWS`.
- Event `status: 3` as a number still red.
- Event with no `impacted_services` → group leaf red.
- Child `current` missing → child yellow.
- Event without `arn` is skipped.
- UTF-16 BE body with BOM still parses.
- Object JSON `{}` throws `notThisProvider`.

Probe:

- Health landing 200 JSON → `.aws` snapshot named AWS. Only currentevents is GET.
- `https://status.aws.amazon.com/` does not GET HTML and does not GET a `status.aws.amazon.com` JSON path.
- `/public/currentevents` stores click URL `https://health.aws.amazon.com/health/status`.
- `/rss/s3-us-east-1.rss` is RSS, not the hub.
- `prefer: .aws` on the landing GETs only currentevents.
- Unchanged body skips parse. HTTP status change with same bytes does not reuse the snapshot.
- currentevents 503 → `unreachable`.
- currentevents 200 HTML → `unsupported`.
- RSS item on `status.aws.amazon.com` with no `<status>` is yellow. Containing host `status.aws.amazon.com.example.com` stays green.

## Out of this slice

- Account-specific AWS Health (tokens).
- Per-region watched pages.
- HTML scrape of the Health Dashboard.
- A general hub table for other vendors.
