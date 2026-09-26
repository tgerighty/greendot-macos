# Type Consolidation Assessment — greendot

**Scope:** `Sources/StatusCore`, `Sources/greendot` (Swift 5.9). Tests catalogued only.
Read-only analysis. No product source was modified.

**Method:** Grep every `struct` / `class` / `enum` / `protocol` / `typealias` / `actor` in
`*.swift`, then read each definition and its call sites. There are **zero** `typealias`
and **zero** `actor` definitions.

## Executive Summary

StatusCore already holds the domain model in a small set of public types
(`Severity`, `ComponentStatus`, `Incident`, `PageSnapshot`, `WatchedPage`, `Toast`,
`AppConfig`). The AppKit target does not re-declare those shapes. There is **no
copy-paste second model** of the same struct.

The one real consolidation problem is a **split of the same page-colour concept**
across two fields, plus a third patched copy:

- `PageSnapshot.overall` — provider overall from the last fetch
- `WatchedPage.displaySeverity` — overall after component filters (and grey if unreachable)
- `Monitor.pollAll` writes `displaySeverity` into a **copy** of `PageSnapshot.overall`
  so `ToastPolicy` can treat the copy as the page colour

That is one domain idea with two stored meanings and a hidden third. It is the only
MEDIUM finding.

Everything else that looks like duplication is either (a) a tiny duplicated
Severity→label switch, (b) a field name that does not match what it stores, or
(c) types that **must stay local** (private DTOs, AppKit adapters, test doubles).

| Metric | Count |
|---|---|
| Type definitions in `Sources/` (struct/class/enum/protocol, including nested) | 46 |
| `typealias` / `actor` | 0 |
| Protocols | 1 (`HTTPClient`) |
| Truly local types (do not move) | 6 |
| HIGH | 0 |
| MEDIUM | 1 |
| LOW (actionable) | 2 |
| LOW (KEEP / do not centralize) | 4 |

**Top priorities:**

1. Stop feeding `ToastPolicy` a mutated `PageSnapshot`. Pass `displaySeverity` (or
   a small colour-change value) instead of overwriting `overall` on a copy.
2. Optional: one `Severity` label helper for the two identical
   Operational/Degraded/Major outage/Unreachable switches. Do **not** fold provider
   `statusText` into that helper.
3. Do not add a `StatusParser` protocol, a mega `GreenDotError`, or a shared
   `Types.swift`. That would be over-centralization in a 30-file app.

**Estimated impact:** Small. One MEDIUM API cleanup in `ToastPolicy`/`Monitor`.
No type merge of `WatchedPage` and `PageSnapshot` is needed.

## Inventory

### StatusCore — domain (keep public, already canonical)

| Type | Kind | File:line | Role |
|---|---|---|---|
| `StatusProvider` | enum | `Sources/StatusCore/Models.swift:3` | statuspage / statuspal / instatus |
| `ComponentStatus` | struct | `Models.swift:9` | one component or group node |
| `Incident` | struct | `Models.swift:50` | active incident title + URL |
| `PageSnapshot` | struct | `Models.swift:60` | last fetch for one URL |
| `WatchedPage` | struct | `Models.swift:88` | persisted watch + last snapshot |
| `Severity` | enum | `Sources/StatusCore/Severity.swift:3` | red / yellow / green / grey |
| `Aggregator` | enum (namespace) | `Severity.swift:10` | worst-colour rules |
| `Toast` | struct | `Sources/StatusCore/ToastPolicy.swift:3` | notification payload |
| `ToastPolicy` | enum (namespace) | `ToastPolicy.swift:15` | when to toast |
| `AppConfig` | struct | `Sources/StatusCore/PageStore.swift:3` | persisted envelope |
| `StoreError` | enum | `PageStore.swift:16` | corrupt config |
| `PageStore` | class | `PageStore.swift:20` | load/save `config.json` |
| `HTTPClient` | protocol | `Sources/StatusCore/HTTPClient.swift:3` | GET seam |
| `URLSessionHTTPClient` | struct | `HTTPClient.swift:7` | live client |
| `MapHTTPClient` | struct | `HTTPClient.swift:21` | in-memory test client |
| `DirectoryHTTPClient` | struct | `DirectoryHTTPClient.swift:5` | fixture-dir client |
| `ParserError` | enum | `StatuspageParser.swift:3` | shared parser miss/invalid JSON |
| `StatuspageParser` | enum (namespace) | `StatuspageParser.swift:15` | Atlassian JSON |
| `InstatusParser` | enum (namespace) | `InstatusParser.swift:3` | Instatus JSON |
| `StatuspalParser` | enum (namespace) | `StatuspalParser.swift:3` | Statuspal JSON |
| `ProbeError` | enum | `ProviderProbe.swift:3` | unsupported / unreachable |
| `ProviderProbe` | enum (namespace) | `ProviderProbe.swift:17` | probe order |
| `StatusMapping` | enum (namespace) | `StatusMapping.swift:3` | provider string → `Severity` |
| `Monitor` | class | `Monitor.swift:3` | pages, poll, toasts |
| `GreyPulse` | enum (namespace) | `GreyPulse.swift:3` | grey flash overlay |
| `PathSafety` | enum (namespace) | `PathSafety.swift:3` | path containment |

### StatusCore — nested / local (do not move)

| Type | Kind | File:line | Why local |
|---|---|---|---|
| `ComponentStatus.CodingKeys` | enum | `Models.swift:35` | Codable keys |
| `WatchedPage.CodingKeys` | enum | `Models.swift:148` | Codable keys |
| `StatuspageParser.Row` | private struct | `StatuspageParser.swift:44` | raw Statuspage row before nest |
| `ProviderProbe.AttemptResult` | private enum | `ProviderProbe.swift:77` | hit / miss / networkError |

### greendot — AppKit shell (do not move into StatusCore)

| Type | Kind | File:line | Role |
|---|---|---|---|
| `AppDelegate` | class | `AppDelegate.swift:4` | app entry |
| `MenuBarController` | class | `MenuBarController.swift:4` | `NSStatusItem` |
| `MenuActions` | struct | `MenuBuilder.swift:4` | closure bag for the menu |
| `MenuBuilder` | enum (namespace) | `MenuBuilder.swift:15` | builds `NSMenu` |
| `TargetAction` | class | `MenuBuilder.swift:176` | keeps a closure as menu target |
| `KeyablePanel` | private class | `PagePanelController.swift:4` | `NSWindow` that can become key |
| `PagePanelController` | class | `PagePanelController.swift:9` | add/edit panel |
| `ComponentPicker` | class | `ComponentPicker.swift:4` | component checkboxes |
| `StatusDot` | enum (namespace) | `StatusDot.swift:4` | draws the colour dot |
| `Notifier` | class | `Notifier.swift:5` | `UNUserNotification` |
| `URLOpener` | enum (namespace) | `URLOpener.swift:3` | http(s) open + UI-test log |
| `LaunchAtLogin` | enum (namespace) | `LaunchAtLogin.swift:4` | `SMAppService` |
| `MenuCommands` | enum (namespace) | `MenuCommands.swift:3` | UI-test path invoke / dump |
| `MenuClickOpener` | class | `MenuClickOpener.swift:5` | click on submenu parent rows |
| `AppEditMenu` | enum (namespace) | `AppEditMenu.swift:4` | accessory Edit menu |
| `UITestDriver` | enum (namespace) | `UITestDriver.swift:3` | identifier click/set/focus |

Caseless enums (`Aggregator`, `ToastPolicy`, `StatusDot`, parsers, and the other
namespaces) are Swift namespaces for static functions. They are not duplicate
domain types. Do not merge them into one `Utils` type.

## Critical Findings

None.

## Medium Findings

### type-001 — Same page-colour concept lives in `overall` and `displaySeverity`

**Files/lines:**

- `Sources/StatusCore/Models.swift:64` — `PageSnapshot.overall: Severity`
- `Sources/StatusCore/Models.swift:116-119` — `WatchedPage.displaySeverity`
- `Sources/StatusCore/ToastPolicy.swift:16-28` — toasts compare `previous.overall` vs `current.overall`
- `Sources/StatusCore/Monitor.swift:128-140` — copies each snapshot and **overwrites `overall`** with `displaySeverity` before calling `ToastPolicy`
- `Sources/StatusCore/Severity.swift:12-13` — `Aggregator.barSeverity(from:)` still aggregates `snapshot.overall`
- `Sources/StatusCore/Monitor.swift:152-154` — production bar colour uses `displaySeverity`, not `Aggregator.barSeverity`

**What it is:**

The design has two legitimate colours for one watched page:

1. Provider overall (`PageSnapshot.overall`) — raw fetch result.
2. Display colour (`WatchedPage.displaySeverity`) — leaves of enabled components, or grey if unreachable.

Those are not the same value after the user disables a red component. The toast
and the menu bar must follow (2). `ToastPolicy` only knows (1). `Monitor.pollAll`
bridges the gap by mutating a copy:

```swift
copy.overall = previousDisplay          // previous snapshot
copy.overall = config.pages[index].displaySeverity  // current snapshot
```

`Aggregator.barSeverity(from: [PageSnapshot])` is the old seam
("snapshots → bar colour"). Production `Monitor.barSeverity()` does not call it.
Tests in `AggregatorTests.swift` are the only callers. The live bar uses
`fromSeverities(pages.map(\.displaySeverity))`.

**Why it matters:**

`PageSnapshot.overall` now means "provider overall" **or** "display colour I just
wrote in", depending on the call site. A later change to toast rules can silently
use the wrong colour. The two `barSeverity` entry points can disagree when a
component is disabled.

**Canonical fix (do not merge the two types):**

Keep `PageSnapshot` and `WatchedPage` as separate types. They are not duplicates
(see type-004). Change `ToastPolicy` so it does not need a patched snapshot, for
example:

- compare `previousDisplay` and `current.displaySeverity` as `Severity` values
- take `isUnreachable` from the real snapshot

Then delete the copy-and-overwrite in `Monitor.pollAll`. Optionally retire
`Aggregator.barSeverity(from:)` or make it take `[Severity]` only (it already
delegates to `fromSeverities`).

**Recommendation:** CONSOLIDATE the *colour-change* path onto `displaySeverity`.
Do **not** merge `PageSnapshot` into `WatchedPage`.

**Severity:** MEDIUM. No runtime bug reported. The patch in `Monitor` currently
keeps toasts aligned. The shape will drift the next time toast policy grows.

## Low Findings

### type-002 — Identical `Severity` → label switch in two modules

**Files/lines:**

- `Sources/StatusCore/ToastPolicy.swift:32-39` — `body(for:)`
- `Sources/greendot/MenuBuilder.swift:154-160` — `overallText(_:)`

Both map:

| Severity | Label |
|---|---|
| `.green` | Operational |
| `.yellow` | Degraded |
| `.red` | Major outage |
| `.grey` | Unreachable |

(`ToastPolicy` also returns "Unreachable" when `isUnreachable` is true, before the
switch.)

**Not the same mapping (do not fold in):**

- `StatusMapping.statuspageComponentText` — provider tokens (`degraded_performance` → "Degraded", `partial_outage` → "Partial outage")
- `StatuspalParser.node` — same four colours, but `.yellow` can be "Maintenance" when `type == "scheduled"`
- `InstatusParser` — stores the raw provider string as `statusText` (`OPERATIONAL`, not "Operational")

**Recommendation:** REVIEW. A `Severity` label (or `ToastPolicy`/`StatusCore` helper)
for the **app colour vocabulary only** is enough. Do not replace `ComponentStatus.statusText`
with that helper. Provider text is a different concept.

### type-003 — `disabledComponentNames` stores ids and names

**Files/lines:**

- `Sources/StatusCore/Models.swift:93` — `WatchedPage.disabledComponentNames: Set<String>`
- `Sources/StatusCore/Models.swift:125-126` — lookup uses both `component.id` and `component.name`
- `Sources/StatusCore/Monitor.swift:65-72` — toggle unions `[id, name]`
- `Sources/greendot/ComponentPicker.swift:7,19` — local mutable copy named `disabledNames`

The persisted field name says "names". The set also holds component ids (`g1`,
`c1`, …). `ComponentPicker` shortens the same set to `disabledNames`. This is a
naming inconsistency on one type, not a second type.

**Recommendation:** RENAME when the config schema can change (for example
`disabledComponentKeys`). Do not introduce a new wrapper type for `Set<String>`
until a second consumer needs more than contains/insert/remove. Keep the
`ComponentPicker` copy local — it is UI state, not a domain type.

### type-004 — `WatchedPage` and `PageSnapshot` both have `url` and `name` (KEEP)

**Files/lines:** `Models.swift:61-62` (`PageSnapshot`) and `Models.swift:90-91` (`WatchedPage`).

The design spec splits them on purpose:

- watched page = id, url, name, notifications, last snapshot
- snapshot = overall, components, incidents, page URL, unreachable

The watched URL is what the user pasted. The snapshot URL is what the provider
JSON returned. `MenuBuilder` uses `page.snapshot?.url ?? page.url` for Open.
That overlap is real data, not a duplicate type.

**Recommendation:** KEEP SEPARATE. Merging them would lose "user URL vs provider URL"
and "config name vs fetch name".

### type-005 — Three parsers share one function shape (KEEP)

`StatuspageParser.parse`, `InstatusParser.parse`, and `StatuspalParser.parse` all
have `(Data, URL) throws -> PageSnapshot`. `ProviderProbe` calls them as closures.

A `StatusParser` protocol would add a type with one method and three empty
conforming enums. The probe order and the extra Statuspal HTML/subdomain path
would still be special cases.

**Recommendation:** KEEP SEPARATE. Do not add a parser protocol. That is
over-centralization.

### type-006 — Three error enums (KEEP)

| Type | Cases | Layer |
|---|---|---|
| `ParserError` | `notThisProvider`, `invalidJSON` | parse miss (internal, shared by the three parsers) |
| `ProbeError` | `unsupported`, `unreachable` | user-facing probe result (public) |
| `StoreError` | `corrupt` | config file (public) |

`ParserError.notThisProvider` is the probe "try next format" signal.
`ProbeError.unsupported` is the final user error. They look similar and are not
the same.

**Recommendation:** KEEP SEPARATE. Do not make a single `GreenDotError`.
Optional later: move `ParserError` out of `StatuspageParser.swift` into its own
file so the home is not Statuspage-only. That is file placement, not a type merge.

### type-007 — HTTPClient family is polymorphism, not duplication (KEEP)

`HTTPClient` + `URLSessionHTTPClient` (live) + `DirectoryHTTPClient` (fixture dir)
+ `MapHTTPClient` (in-memory map) + test-only `FailingHTTPClient`
(`Tests/StatusCoreTests/ProbeAndMonitorTests.swift:196`).

Different behaviours, one protocol. `FailingHTTPClient` is correctly local to one
test file. Do not move it into StatusCore. Do not merge `MapHTTPClient` and
`DirectoryHTTPClient`.

**Recommendation:** KEEP. Placement of `MapHTTPClient` in production StatusCore
is a packaging note for a later cleanup, not a type-consolidation action.

## Recommendations

1. **Do the MEDIUM cleanup (type-001).** Teach `ToastPolicy` the display colour
   (or take two `Severity` values plus `isUnreachable`). Remove the snapshot
   clone that overwrites `overall` in `Monitor.pollAll`. Align or retire
   `Aggregator.barSeverity(from: [PageSnapshot])` so there is one bar-colour
   entry point.
2. **Optional LOW (type-002).** Add one label helper on `Severity` for the app
   vocabulary used by toasts and the empty-component menu row. Leave provider
   `statusText` mapping in `StatusMapping` / the parsers.
3. **Optional LOW (type-003).** Rename `disabledComponentNames` when you next
   touch the config schema. Do not wrap `Set<String>` in a new type now.
4. **Do not centralize:**
   - Do not merge `WatchedPage` and `PageSnapshot`.
   - Do not add `protocol StatusParser`.
   - Do not merge `ParserError` / `ProbeError` / `StoreError`.
   - Do not move `KeyablePanel`, `TargetAction`, `MenuActions`,
     `StatuspageParser.Row`, `AttemptResult`, or `FailingHTTPClient` into a
     shared models file.
   - Do not create `Sources/StatusCore/Types.swift` as a dump of every enum.
   - Do not move AppKit types (`StatusDot`, panel, menu) into StatusCore.
     StatusCore must stay Foundation-only.

## Out of Scope

- **Function clones, not types.** `Monitor.find`/`collect` and
  `ComponentPicker.find`/`collect` are the same tree walk. That belongs in a
  deduplication assessment, not a type merge. A method on `ComponentStatus`
  would be a helper, not a new type.
- **Instatus component switch vs `StatusMapping`.** `InstatusParser` maps
  component status with a local `switch`. Statuspage/Statuspal go through
  `StatusMapping`. Same *function* family, not a second `Severity` type.
- **`ComponentStatus.statusText` vs app labels.** Provider text can be
  "Maintenance", "Partial outage", or raw `OPERATIONAL`. The app colour
  vocabulary is the four words in type-002. Keep both.
- **`MenuClickOpener.monitor: Any?`** is an `NSEvent` monitor token. It is not
  the `Monitor` class. Property name only.
- **Test `XCTestCase` classes** and `GreenDotUITests`. Organizational, not domain.
- **Codable `CodingKeys`.** Nested boilerplate. Keep next to the parent.
- **Caseless namespace enums.** Swift idiom for static functions. Not duplicate
  models.
- **Weak JSON typing.** Parsers use `[String: Any]` from `JSONSerialization`.
  That is type *strength*, not duplication. `StatuspageParser.Row` is the only
  intermediate DTO and must stay private.
- **Config field overlap with env vars** (`GREENDOT_*`). Not Swift types.

## Local types — do not move

| Type | Home | Reason |
|---|---|---|
| `StatuspageParser.Row` | `StatuspageParser.swift:44` | raw JSON row; `status` is still a `String` |
| `ProviderProbe.AttemptResult` | `ProviderProbe.swift:77` | probe control flow |
| `KeyablePanel` | `PagePanelController.swift:4` | one window subclass |
| `TargetAction` | `MenuBuilder.swift:176` | AppKit target-action box |
| `MenuActions` | `MenuBuilder.swift:4` | closure bag for one builder |
| `FailingHTTPClient` | `ProbeAndMonitorTests.swift:196` | one test double |

`MenuActions` is used by `AppDelegate` and `MenuBuilderTests`. That is still the
menu layer. Do not promote it to StatusCore.

## Machine-Readable Findings

```json
{
  "findings": [
    {
      "id": "type-001",
      "file": "Sources/StatusCore/Models.swift;Sources/StatusCore/Monitor.swift;Sources/StatusCore/ToastPolicy.swift;Sources/StatusCore/Severity.swift",
      "line": 64,
      "severity": "MEDIUM",
      "confidence": "CERTAIN",
      "recommendation": "CONSOLIDATE",
      "detail": "Page colour is split across PageSnapshot.overall and WatchedPage.displaySeverity. Monitor.pollAll copies snapshots and overwrites overall so ToastPolicy can toast on display colour. Aggregator.barSeverity still uses overall and is unused in production. Keep the two types; stop patching overall; pass displaySeverity into ToastPolicy.",
      "verified": false
    },
    {
      "id": "type-002",
      "file": "Sources/StatusCore/ToastPolicy.swift;Sources/greendot/MenuBuilder.swift",
      "line": 32,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "REVIEW",
      "detail": "ToastPolicy.body and MenuBuilder.overallText duplicate the same four-word Severity label map (Operational/Degraded/Major outage/Unreachable). Optional helper on Severity. Do not fold provider statusText (StatusMapping, StatuspalParser Maintenance, Instatus raw tokens) into that helper.",
      "verified": false
    },
    {
      "id": "type-003",
      "file": "Sources/StatusCore/Models.swift",
      "line": 93,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "RENAME",
      "detail": "WatchedPage.disabledComponentNames is a Set<String> of both component ids and names. ComponentPicker copies it as disabledNames. Naming only; do not add a wrapper type. Rename on next config schema touch (e.g. disabledComponentKeys).",
      "verified": false
    },
    {
      "id": "type-004",
      "file": "Sources/StatusCore/Models.swift",
      "line": 60,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "KEEP",
      "detail": "WatchedPage and PageSnapshot both have url and name. Intentional: user-pasted watch vs provider snapshot. MenuBuilder uses snapshot?.url ?? page.url. Do not merge the types.",
      "verified": false
    },
    {
      "id": "type-005",
      "file": "Sources/StatusCore/StatuspageParser.swift;Sources/StatusCore/InstatusParser.swift;Sources/StatusCore/StatuspalParser.swift",
      "line": 15,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "KEEP",
      "detail": "Three parser namespaces share (Data, URL) throws -> PageSnapshot. A StatusParser protocol would be over-centralization; Statuspal probe path is already special. Keep three enums.",
      "verified": false
    },
    {
      "id": "type-006",
      "file": "Sources/StatusCore/StatuspageParser.swift;Sources/StatusCore/ProviderProbe.swift;Sources/StatusCore/PageStore.swift",
      "line": 3,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "KEEP",
      "detail": "ParserError, ProbeError, and StoreError are different layers (parse miss vs user-facing probe vs corrupt config). Do not merge into one error type. ParserError is already shared by all three parsers.",
      "verified": false
    },
    {
      "id": "type-007",
      "file": "Sources/StatusCore/HTTPClient.swift;Sources/StatusCore/DirectoryHTTPClient.swift;Tests/StatusCoreTests/ProbeAndMonitorTests.swift",
      "line": 3,
      "severity": "LOW",
      "confidence": "CERTAIN",
      "recommendation": "KEEP",
      "detail": "HTTPClient implementations (URLSession, Map, Directory, test-local FailingHTTPClient) are distinct behaviours behind one protocol. Keep FailingHTTPClient local. Do not merge MapHTTPClient with DirectoryHTTPClient.",
      "verified": false
    }
  ]
}
```
