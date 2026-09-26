# Salesforce Trust status page

Date: 2026-09-16

This spec extends [2026-08-21-status-menu-design.md](2026-08-21-status-menu-design.md). It adds the Salesforce Trust landing as one watched page, using the public active-incidents JSON. It does not add a second add path.

## What it is

The user pastes `https://status.salesforce.com/`. greendot watches it as one page named Salesforce. Active incidents are groups. Impacted services are children. Colour uses the same worst-enabled-leaf rule as other providers.

## Decisions

These decisions are settled. Do not re-open them in this slice.

| Topic | Decision |
|---|---|
| Scope | Public Trust active incidents only. No per-instance page. No tokens. |
| Add | One URL still creates one watched page. |
| Shape | Incidents are groups. `serviceKeys` are children. No incident list (that would duplicate the tree). |
| Colour | Worst enabled leaf. |
| Empty feed | No components. Overall green. |
| Incident with no `serviceKeys` | Group is a leaf with the incident colour. |
| Instance keys | Do not become children. One incident can name more than a thousand instances. |
| Maintenances | Out of this slice. `/v1/maintenances/preview` stays unused. |
| Landing URLs | `https://status.salesforce.com` and `https://status.salesforce.com/`. Host match is exact. A path such as `/products/Tableau` is not a landing. |
| JSON URL | Always GET `https://api.status.salesforce.com/v1/incidents/active`. Do not scrape the SPA HTML. Do not GET `/v1/instances` (about 5 MB). |
| Click URL | The pasted landing URL, normalised like Okta (no trailing slash). |
| Provider | `.salesforce`. Re-poll uses `prefer: .salesforce`. |

## Approaches

1. **Landing short-circuit plus JSON parser (chosen).** `SalesforceParser` reads the active-incidents array. `ProviderProbe` detects the landing URL first, then GETs the one JSON URL.
2. Full instance catalog from `/v1/instances`. Rejected: about 5 MB per poll, and thousands of menu rows.
3. Products from `/v1/products` plus maintenances. Rejected: no incident titles, and scheduled maintenance would keep the bar yellow.

## Mapping

| Input | Page name | `snapshot.url` | Components |
|---|---|---|---|
| Trust landing | `Salesforce` | Normalised landing URL | Incident groups; children from `serviceKeys` |

Incident group:

- id: string form of `id` (required integer)
- name: trimmed `additionalInformation`, first line, if that text is not empty. Else `{type} {externalId}`. If `externalId` is missing, `{type} {id}`. If `type` is missing, `externalId` or `id`.
- severity / status text: from incident `type`
- `isGroup`: true
- children: `serviceKeys` entries

Child:

- id: the service key
- name: the service key
- severity / status text: the parent incident colour
- `isGroup`: false

Skip an object that has no `id`. Skip an incident whose `status` is `resolved` (any case). Skip a service key that is empty.

| Raw `type` | Severity | Status text |
|---|---|---|
| `Disruption` | red | Major outage |
| `Degradation` | yellow | Degraded |
| `Maintenance` | yellow | Maintenance |
| missing / empty / anything else | yellow | Degraded |

Overall severity is `ComponentTree.enabledLeafSeverity` with no disabled keys.

## Probe

Landing detection runs before Statuspage, Instatus, Flashduty, Statuspal, and RSS. A URL is a Salesforce landing when the host is `status.salesforce.com` and the path is empty.

On a hit, GET only `https://api.status.salesforce.com/v1/incidents/active`. Parse as this JSON array.

Identity: a JSON array. An empty array is a valid green page. A non-array body is a miss.

`lastBodies` for Salesforce is `HTTP {status}\n` plus the body, so an unchanged re-poll skips parse. A status change with the same bytes does not reuse the snapshot.

`prefer: .salesforce` on a landing GETs only the active-incidents URL. `prefer: .salesforce` on a non-landing URL is a miss (no GET), then the other providers run.

## Failures

| Case | Result |
|---|---|
| active-incidents network / 429 / 5xx | `ProbeError.unreachable` |
| 404, non-JSON, or JSON that is not an array | miss; `unsupported` if nothing else matched |
| Landing host down before JSON | `unreachable` (the only GET is active-incidents) |

Add-panel error for a full miss names Salesforce:

`This URL is not a known status page format (Statuspage, Statuspal, Instatus, Flashduty, AWS, Icinga, Okta, Salesforce, or RSS/Atom).`

## Files

- Create `Sources/StatusCore/SalesforceParser.swift` — active-incidents array → `PageSnapshot` with `provider: .salesforce`.
- Create `Sources/StatusCore/ProviderProbe+Salesforce.swift` — landing check, active-incidents GET, cache body.
- Modify `Sources/StatusCore/Models.swift` — `StatusProvider.salesforce`.
- Modify `Sources/StatusCore/StatusMapping.swift` — `salesforce` / `salesforceText`.
- Modify `Sources/StatusCore/ProviderProbe.swift` — landing short-circuit, probe order, error text.
- Test `Tests/StatusCoreTests/SalesforceParserTests.swift`
- Test `Tests/StatusCoreTests/SalesforceProbeTests.swift`
- Modify README, CHANGELOG, and the v1 provider list in the menu spec.

Do not add a URL on `ComponentStatus`. Do not change `Monitor.add` to return multiple pages. Do not scrape HTML. Do not GET `/v1/instances` or `/v1/maintenances/preview`.

## Tests

Seams: parser (bytes → snapshot), probe (URL + HTTP responses → snapshot or error).

Parser:

- Two incidents, first `type: Disruption` with `serviceKeys: ["coreService"]` and many `instanceKeys` → group id `"20004433"`, child `coreService` only, overall red, provider `.salesforce`, no incidents list.
- Second `type: Degradation` with `additionalInformation` → that text is the group name.
- Empty array → green, no components, name `Salesforce`.
- `status: resolved` is skipped.
- Object JSON is not this provider.

Probe:

- Landing GETs only `https://api.status.salesforce.com/v1/incidents/active`.
- A path under `status.salesforce.com` is not a landing.
- 503 is unreachable. Non-array body is unsupported. A landing miss does not fall through to Statuspage.
- Unchanged body skips parse.
