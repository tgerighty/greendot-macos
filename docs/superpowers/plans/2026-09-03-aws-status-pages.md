# AWS Status Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Paste an AWS Health landing URL and watch one page named AWS, with current events as groups and impacted services as children.

**Architecture:** `AwsParser` turns the public current-events JSON array into a `PageSnapshot`. `ProviderProbe` detects the landing URL before other providers, GETs one hardcoded JSON URL, and caches the body. RSS on `status.aws.amazon.com` stays RSS, with missing `<status>` yellow.

**Tech Stack:** Swift 5.9, Foundation `JSONSerialization`, existing `HTTPClient` / `ProviderProbe` / XCTest.

**Spec:** `docs/superpowers/specs/2026-09-03-aws-status-pages-design.md`

## Global Constraints

- macOS 13+, SwiftPM, `swift test` / `make test`.
- TDD: failing test first, watch it fail, then minimal code.
- One URL still creates one watched page.
- Do not scrape HTML. Do not follow the cross-host redirect from `status.aws.amazon.com`.
- Do not add a URL on `ComponentStatus`. Do not change `Monitor.add` to return multiple pages.
- Match existing parser/probe style (`FlashdutyParser`, `RssHubProbeTests`, `RssParser.missingSeverity`).
- Commit prefix `[FEATURE]`, `[FIX]`, `[TEST]`, or `[DOCS]`.
- File ownership: a task may edit only the files listed for that task.

---

### Task 1: AwsParser and status mapping

**Files:**
- Create: `Sources/StatusCore/AwsParser.swift`
- Create: `Tests/StatusCoreTests/AwsParserTests.swift`
- Modify: `Sources/StatusCore/Models.swift` (add `StatusProvider.aws` only)
- Modify: `Sources/StatusCore/StatusMapping.swift` (add `aws` / `awsText` only)
- Modify: `Sources/StatusCore/ProviderProbe.swift` (exhaustive `.aws` cases only: miss / include in probe order after Statuspal and before RSS; do not add landing detection)

**Interfaces:**
- Consumes: `PageSnapshot`, `ComponentStatus`, `ParserError`, `StatusMapping`
- Produces: `AwsParser.parse(data:sourceURL:) throws -> PageSnapshot` with `provider: .aws`; `StatusMapping.aws(_:)` / `awsText(_:)`; `StatusProvider.aws`

- [ ] **Step 1: Write the failing parser tests** in `Tests/StatusCoreTests/AwsParserTests.swift` covering the spec Parser list (two-event tree, empty array, numeric status, no impacted_services, missing child current, skip missing arn, UTF-16 BE BOM, `{}` → `notThisProvider`). Use sourceURL `https://health.aws.amazon.com/health/status`. Empty array name is `AWS`. Click URL for parser is `sourceURL`.

- [ ] **Step 2: Run tests to verify they fail** (`swift test --filter AwsParserTests`). Expected: compile failure or missing `AwsParser` / `.aws`.

- [ ] **Step 3: Minimal implementation.** Decode UTF-16 BOM or UTF-8, then `JSONSerialization`. Identity is a JSON array. Map as spec. Accept status as String or NSNumber.

- [ ] **Step 4: Run `swift test --filter AwsParserTests` then `swift test --filter StatusCoreTests`.** Parser tests pass. Project compiles: `probeOrder` and switches include `.aws` as a miss (no currentevents GET yet).

- [ ] **Step 5: Commit** `[FEATURE] Parse AWS Health current-events JSON`

---

### Task 2: AWS RSS missing-status exception

**Files:**
- Modify: `Sources/StatusCore/RssParser.swift`
- Modify: `Tests/StatusCoreTests/RssParserGuardTests.swift` (add tests; keep existing Azure containing-host test)

**Interfaces:**
- Consumes: `RssParser.parse(data:sourceURL:)`
- Produces: missing `<status>` is yellow when host is `status.aws.amazon.com` or a subdomain; containing host is still green

- [ ] **Step 1: Write failing tests:** RSS item with no status on `https://status.aws.amazon.com/rss/s3-us-east-1.rss` is yellow; empty channel on that host is green; `https://status.aws.amazon.com.example.com/rss/s3.rss` missing status is green.

- [ ] **Step 2: Run `swift test --filter RssParserGuardTests` and confirm the new tests fail.**

- [ ] **Step 3: Extend `missingSeverity` / host check. Do not broaden Azure matching.**

- [ ] **Step 4: Run `swift test --filter RssParserGuardTests` and `swift test --filter RssParserTests`.**

- [ ] **Step 5: Commit** `[FEATURE] Treat AWS RSS items without status as yellow`

---

### Task 3: AWS landing probe

**Files:**
- Create: `Sources/StatusCore/ProviderProbe+AWS.swift`
- Create: `Tests/StatusCoreTests/AwsProbeTests.swift`
- Modify: `Sources/StatusCore/ProviderProbe.swift` (short-circuit landing before other providers; error text names AWS; `prefer: .aws` tries AWS first)
- Modify: `Tests/StatusCoreTests/RssProbeTests.swift` (unsupported error string now includes AWS)

**Interfaces:**
- Consumes: `AwsParser.parse`, `HTTPClient.get`
- Produces: landing URL → `.aws` snapshot; GET only `https://health.aws.amazon.com/public/currentevents`

- [ ] **Step 1: Write failing probe tests** from the spec Probe list.

- [ ] **Step 2: Run `swift test --filter AwsProbeTests` and confirm they fail.**

- [ ] **Step 3: Implement landing detection, currentevents GET, UTF-16 decode at the probe, cache body `HTTP {status}\n` + bytes, click-URL rewrite for `/public/currentevents`. Do not GET HTML for `status.aws.amazon.com/`.**

- [ ] **Step 4: Run `swift test --filter AwsProbeTests` and `swift test --filter RssProbeTests` then `swift test`.**

- [ ] **Step 5: Commit** `[FEATURE] Probe AWS Health landing URLs`

---

### Task 4: Docs

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md` (`[Unreleased]` Added)
- Modify: `docs/superpowers/specs/2026-09-02-rss-feeds-design.md` (AWS RSS missing-status row; out-of-slice hub table still excludes a general vendor table)
- Modify: `docs/superpowers/specs/2026-08-21-status-menu-design.md` (providers row names AWS)

- [ ] **Step 1: Update the four files. No production code.**

- [ ] **Step 2: Commit** `[DOCS] Document AWS Health status pages`
