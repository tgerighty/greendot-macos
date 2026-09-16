# SaaS status-page platforms

Date: 2026-09-16

This spec extends [2026-08-21-status-menu-design.md](2026-08-21-status-menu-design.md). It adds parsers for the public status-page platforms used by major SaaS that greendot did not already read.

A live check of about 150 major SaaS status URLs found that most of them are Atlassian Statuspage, Instatus, Flashduty, Statuspal, RSS, AWS, Okta, or Salesforce. Those already work. This slice adds the remaining platforms that publish JSON.

## What it is

The user pastes the public status URL. greendot detects the platform, reads one JSON feed, and shows one watched page. Colour uses the worst enabled leaf.

## Decisions

These decisions are settled. Do not re-open them in this slice.

| Topic | Decision |
|---|---|
| Scope | Public JSON only. No HTML scrape of status. No API keys. |
| Add | One URL still creates one watched page. |
| Colour | Worst enabled leaf. |
| Empty feed | No components. Overall green. |
| Status.io | HTML contains `static.status.io`. Extract `page_id`. GET `https://api.status.io/1.0/status/{id}`. Components are groups. Containers are children. |
| Slack | Host `slack-status.com` or `status.slack.com`. GET `/api/v2.0.0/current`. Active incidents are groups. Empty is green. |
| Heroku | Host `status.heroku.com`. GET `/api/v4/current-status`. Systems are leaves. Upcoming scheduled maintenance is ignored. |
| Google | `status.cloud.google.com`, `status.firebase.google.com`, and `www.google.com/appsstatus`. GET `{origin}/incidents.json` or `/appsstatus/dashboard/incidents.json`. Only incidents with no `end`. |
| Apple | Path under `apple.com/support/systemstatus`. GET `https://www.apple.com/support/systemstatus/data/system_status_en_US.js`. Only services that have events. |
| incident.io | GET `{base}/proxy/status.incident.io`. Identity is a `summary` object. Ongoing incidents are groups. Empty is green. Do not list every healthy component. |
| Stripe | Host `status.stripe.com` with an empty path. GET `https://www.stripestatus.com/api/v2/summary.json` as Statuspage. Name Stripe. Click URL is the pasted landing. |
| Out of this slice | Hund (Bitwarden needs an API key), Adobe SPA, Zendesk SPA, Docusign SPA, Redis/FireHydrant SPA, Zscaler, IBM Cloud SPA, Workday login, Mailchimp HTML, JetBrains, PostHog, Railway, Freshworks, Adyen. Generic HTML scrape stays out of v1. |

## Mapping

### Status.io `status_code`

| Code | Severity | Status text |
|---|---|---|
| 100 | green | Operational |
| 200 | yellow | Maintenance |
| 300 | yellow | Degraded |
| 400 | yellow | Partial outage |
| 500 | red | Major outage |
| 600 | yellow | Degraded |
| missing / other | yellow | Degraded |

Overall comes from `result.status_overall.status_code`. A component with no name is skipped. A container with no name is skipped.

Page name is the host of the pasted URL.

### Slack

`status` of `ok` and no `active_incidents` is green. Each active incident is a group. `type` of `outage` is red. Anything else is yellow. Services are children when present.

Page name is `Slack`. Click URL is the normalised landing.

### Heroku

Each `status[]` row is a leaf. `green` / `yellow` / `red` map to those colours. Active `incidents` are extra groups. `scheduled` rows whose `state` is not `in-progress` are ignored.

Page name is `Heroku`.

### Google

An incident with a non-empty `end` is skipped. `severity` of `high` or `critical` is red. Other active incidents are yellow. `external_desc` first line is the name. `affected_products[].title` are children.

Page names: `Google Cloud`, `Firebase`, `Google Workspace`.

### Apple

A service with no `events` is skipped. `statusType` of `Outage` is red. Other events are yellow. Resolved event status is skipped.

Page name is `Apple`.

### incident.io

`summary.ongoing_incidents` are groups. `summary.name` is the page name when present. Empty ongoing list is green with no components.

## Probe

Landing short-circuits run with AWS, Okta, and Salesforce: Slack, Heroku, Google, Apple, Stripe.

Status.io and incident.io run in the provider loop after Statuspal and before RSS.

`lastBodies` is `HTTP {status}\n` plus the JSON body.

A 5xx or 429 on the JSON URL is unreachable. A non-matching body is a miss. A Status.io or Google landing miss does not fall through to Statuspage.

## Files

- Parsers and probe files per platform under `Sources/StatusCore/`.
- `StatusProvider` cases: `statusio`, `slack`, `heroku`, `google`, `apple`, `incidentio`. Stripe stays `.statuspage`.
- Tests next to the other parser and probe tests.
- README, CHANGELOG, menu spec, this spec.

Do not add a URL on `ComponentStatus`. Do not change `Monitor.add` to return multiple pages.
