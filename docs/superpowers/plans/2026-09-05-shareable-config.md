# Shareable Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `config.json` a small, readable settings file that a user can copy to another machine or send to a colleague, and give the menu a way to reveal and reload it.

**Architecture:** `PageStore` writes two files. `config.json` holds settings. `state.json` holds the machine-local cache (poll snapshots, launch-at-login flag). `AppConfig` stays the single in-memory truth, so `Monitor` and the editor do not change. Custom `Codable` members decide which field goes in which file. Load is tolerant of hand edits. Two new menu items reveal and reload the file.

**Tech Stack:** Swift 5.9, SwiftPM (`StatusCore`, `greendot`, `TestSupport`), Foundation `JSONEncoder` / `JSONDecoder` / `JSONSerialization`, AppKit `NSMenu` / `NSWorkspace`, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-05-shareable-config-design.md`

## Global Constraints

- macOS 13+, SwiftPM. Test with `swift test --filter <TestClass>` during a task and `swift test` at the end of every task.
- Run `swiftlint lint --strict` before every commit. It must report `0 violations`. `.swiftlint.yml`: `line_length: 120`, `identifier_name.min_length: 3` with `id` excluded, `included: Sources, Tests`, `excluded: .build, UITests, greendot.app`. SwiftLint defaults also apply: `function_body_length` 50, `type_body_length` 250, `file_length` 400.
- TDD: write the failing test, run it and watch it fail, then write the minimal code.
- Two files in the config directory. `config.json` holds settings. `state.json` holds machine-local cache. Both mode `0600`, atomic write.
- `config.json` shape: `{ "version": 2, "pollSeconds": 60, "pages": [ { "id": "<uuid>", "url": "...", "name": "...", "notificationsEnabled": true, "disabledComponentNames": ["a", "b"] } ] }`. No `snapshot`. No `didSetLaunchAtLogin`.
- `state.json` shape: `{ "version": 2, "didSetLaunchAtLogin": true, "snapshots": { "<page uuid>": <PageSnapshot> } }`.
- `JSONEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]` for both files. `disabledComponentNames` encodes as a sorted array. The same `AppConfig` always encodes to the same bytes.
- `PageStore.save` reads each target file first and does not write when the bytes are identical.
- `AppConfig.currentVersion = 2`. Load accepts `version <= 2`. A version-1 file loads and is split on the next save. A `state.json` snapshot beats a version-1 inline snapshot.
- Missing `state.json` loads as `didSetLaunchAtLogin: false` with no snapshots. Missing `config.json` loads as an empty `AppConfig`.
- Missing page `id`: mint a `UUID()` on decode. Duplicate page `id`: keep every page and mint a fresh `UUID()` for the second and later pages. `PageStore.save` still rejects duplicates.
- `PageStore.load` saves the normalised config back only when it minted or replaced an `id`. A load that changed nothing does not write.
- `AppConfig.pollSeconds: TimeInterval`, default `60`, always written. On decode, missing / non-finite / `<= 0` becomes `60`. `GREENDOT_POLL_SECONDS` still overrides the file when set and valid.
- Menu: two new items directly under "Refresh". "Reveal Config File" (identifier `reveal-config`) and "Reload Config" (identifier `reload-config`).
- `AppConfig` stays the single in-memory truth for `Monitor`. Only `PageStore` knows about the two files. **Do not change `Sources/StatusCore/Monitor.swift` (except the `pollSeconds` accessor in Task 4), `Sources/StatusCore/Monitor+Mutations.swift`, or `Sources/StatusCore/Monitor+Polling.swift`.** The skip-unchanged-write behaviour lives in the store, not in `applyPollResults`.
- Out of slice: import / export dialogs, URL-token redaction, grey pulse timing, toast timing, icon tick. Do not build them.
- **UITests survey (no UITests file changes in this plan).** `UITests/` is excluded from SwiftLint and is not built by `swift test`. Only `UITests/GreenDotUITests/GreenDotUITests.swift` reads the menu. `testMenuHasAddRefreshLaunchAtLoginAndQuit` (line 62) asserts with `dump.contains(...)` for each of "Add Status Page…", "Refresh", "Launch at Login", "About greendot", "Quit greendot", "No status pages" — never an equality assertion on the whole dump, and never an index or a count. `testRefreshStaysAlive` (line 162) calls `clickMenu("Refresh")`, which routes to `MenuCommands.invokeFirst(named:in:)` and matches `item.title == "Refresh"` exactly, so "Reveal Config File" and "Reload Config" cannot capture it. `waitForSaved(name:)` (line 258) waits for the page name to appear in `config.json`; page names stay in `config.json` after the split, so it keeps working. Conclusion: adding the two menu items breaks no UI test.
- Commit prefix `[FEATURE]`, `[FIX]`, `[TEST]`, or `[DOCS]`.
- File ownership: a task may edit only the files listed for that task.

---

### Task 1: Deterministic, readable JSON

**Files:**
- Modify: `Sources/StatusCore/PageStore.swift` (add a shared encoder, use it in `save`)
- Modify: `Sources/StatusCore/Models.swift` (add `WatchedPage.encode(to:)` at the bottom, in the existing `extension WatchedPage: Codable`)
- Create: `Tests/StatusCoreTests/ConfigEncodingTests.swift`
- Modify: `CHANGELOG.md` (`[Unreleased]` → `### Changed`)

**Interfaces:**
- Consumes: `PageStore.save(_:)`, `PageStore.configURL`, `AppConfig`, `WatchedPage`
- Produces: `config.json` written with `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`; `WatchedPage` encodes `disabledComponentNames` as a sorted `[String]`. Later tasks reuse the private `PageStore.encoder` for both files.

- [ ] **Step 1: Write the failing tests**

Create `Tests/StatusCoreTests/ConfigEncodingTests.swift`:

```swift
import XCTest
@testable import StatusCore

final class ConfigEncodingTests: XCTestCase {
    func testSetInsertionOrderDoesNotChangeSavedBytes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        let forward = try Self.config(keys: ["alpha", "beta", "gamma", "delta"])
        let backward = try Self.config(keys: ["delta", "gamma", "beta", "alpha"])

        try store.save(forward)
        let first = try Data(contentsOf: store.configURL)
        try FileManager.default.removeItem(at: store.configURL)
        try store.save(backward)
        let second = try Data(contentsOf: store.configURL)

        XCTAssertEqual(first, second)
    }

    func testSavedConfigIsReadableWithSortedKeysAndPlainSlashes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        try store.save(try Self.config(keys: ["beta", "alpha"]))
        let text = try XCTUnwrap(String(data: try Data(contentsOf: store.configURL), encoding: .utf8))

        XCTAssertTrue(text.contains("\n"), text)
        XCTAssertTrue(text.contains("https://status.example.com/page"), text)
        XCTAssertFalse(text.contains("\\/"), text)

        let disabled = try Self.offset(of: "\"disabledComponentNames\"", in: text)
        let identifier = try Self.offset(of: "\"id\"", in: text)
        let name = try Self.offset(of: "\"name\"", in: text)
        let notifications = try Self.offset(of: "\"notificationsEnabled\"", in: text)
        let pageURL = try Self.offset(of: "\"url\"", in: text)
        XCTAssertTrue(disabled < identifier, text)
        XCTAssertTrue(identifier < name, text)
        XCTAssertTrue(name < notifications, text)
        XCTAssertTrue(notifications < pageURL, text)

        let alpha = try Self.offset(of: "\"alpha\"", in: text)
        let beta = try Self.offset(of: "\"beta\"", in: text)
        XCTAssertTrue(alpha < beta, text)
    }

    private static func config(keys: [String]) throws -> AppConfig {
        var disabled: Set<String> = []
        for key in keys {
            disabled.insert(key)
        }
        let page = WatchedPage(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            url: try XCTUnwrap(URL(string: "https://status.example.com/page")),
            name: "Example",
            notificationsEnabled: true,
            disabledComponentNames: disabled
        )
        return AppConfig(pages: [page])
    }

    private static func offset(of needle: String, in text: String) throws -> Int {
        let range = try XCTUnwrap(text.range(of: needle))
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `swift test --filter ConfigEncodingTests`
Expected: `testSavedConfigIsReadableWithSortedKeysAndPlainSlashes` fails — the saved file is one line with `\/` escapes. `testSetInsertionOrderDoesNotChangeSavedBytes` fails on most runs, because `Set<String>` iteration order depends on insertion order.

- [ ] **Step 3: Add the shared encoder to `PageStore`**

In `Sources/StatusCore/PageStore.swift`, add the encoder as a static member of `PageStore` (put it directly under the `defaultDirectory` property) and use it in `save`:

```swift
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
```

Change the one line in `save`:

```swift
        let data = try Self.encoder.encode(config)
```

- [ ] **Step 4: Encode `disabledComponentNames` sorted**

In `Sources/StatusCore/Models.swift`, add `encode(to:)` inside the existing `extension WatchedPage: Codable`, under `init(from:)`:

```swift
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(name, forKey: .name)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(disabledComponentNames.sorted(), forKey: .disabledComponentNames)
        try container.encodeIfPresent(snapshot, forKey: .snapshot)
    }
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `swift test --filter ConfigEncodingTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Run the whole suite**

Run: `swift test`
Expected: PASS. Nothing else asserts on the saved bytes.

- [ ] **Step 7: Add the changelog line**

In `CHANGELOG.md`, under `## [Unreleased]` → `### Changed`, add:

```markdown
- `config.json` is pretty-printed with sorted keys and plain slashes. `disabledComponentNames` is written as a sorted array. The same settings always produce the same bytes, so the file diffs cleanly.
```

- [ ] **Step 8: Lint and commit**

```bash
swiftlint lint --strict
git add Sources/StatusCore/PageStore.swift Sources/StatusCore/Models.swift \
        Tests/StatusCoreTests/ConfigEncodingTests.swift CHANGELOG.md
git commit -m "[FEATURE] Write config.json as readable deterministic JSON"
```

---

### Task 2: Tolerant load

**Files:**
- Modify: `Sources/StatusCore/PageStore.swift` (`load`, plus `uniquingPageIDs` and `needsIDNormalisation` helpers; keep `validate` duplicate rejection for `save`)
- Modify: `Sources/StatusCore/Models.swift` (`WatchedPage.init(from:)` id decode only)
- Modify: `Tests/StatusCoreTests/PageStoreValidationTests.swift`
- Modify: `CHANGELOG.md` (`[Unreleased]` → `### Changed`)

**Interfaces:**
- Consumes: `PageStore.load()`, `PageStore.save(_:)`, `PageStore.configURL`, `StoreError.corrupt`
- Produces: `PageStore.load()` never throws for a missing or repeated `id`. It mints ids and rewrites the file only when it changed one. `PageStore.save(_:)` still throws `StoreError.corrupt` for duplicate ids. Task 3 keeps both helpers and adds the state file on top.

- [ ] **Step 1: Write the failing tests**

Replace `testLoadRejectsDuplicateWatchedPageIDs` in `Tests/StatusCoreTests/PageStoreValidationTests.swift` with the three tests below. Keep `testSaveRejectsDuplicateWatchedPageIDsBeforeWriting` exactly as it is.

```swift
    func testLoadKeepsDuplicateIDPagesAndMintsNewIDs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = """
        {
          "version": 1,
          "pages": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "url": "https://first.example.com",
              "name": "First"
            },
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "url": "https://second.example.com",
              "name": "Second"
            }
          ],
          "didSetLaunchAtLogin": false
        }
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = PageStore(directory: directory)
        try Data(json.utf8).write(to: store.configURL)

        let config = try store.load()

        XCTAssertEqual(config.pages.map(\.name), ["First", "Second"])
        XCTAssertEqual(config.pages[0].id.uuidString, "00000000-0000-0000-0000-000000000001")
        XCTAssertNotEqual(config.pages[1].id, config.pages[0].id)
        // A second load returns the same ids, which proves the file was rewritten.
        XCTAssertEqual(try store.load().pages.map(\.id), config.pages.map(\.id))
    }

    func testLoadMintsMissingPageIDAndRewritesFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = """
        {
          "version": 1,
          "pages": [
            {"url": "https://first.example.com", "name": "First"}
          ],
          "didSetLaunchAtLogin": false
        }
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = PageStore(directory: directory)
        try Data(json.utf8).write(to: store.configURL)

        let config = try store.load()

        XCTAssertEqual(config.pages.map(\.name), ["First"])
        let text = try XCTUnwrap(String(data: try Data(contentsOf: store.configURL), encoding: .utf8))
        XCTAssertTrue(text.contains(config.pages[0].id.uuidString), text)
        XCTAssertEqual(try store.load().pages.map(\.id), config.pages.map(\.id))
    }

    func testCleanLoadDoesNotRewriteConfigFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PageStore(directory: directory)
        let page = WatchedPage(
            url: try XCTUnwrap(URL(string: "https://first.example.com")),
            name: "First"
        )
        try store.save(AppConfig(pages: [page]))
        let before = try Self.inode(store.configURL)

        _ = try store.load()

        XCTAssertEqual(try Self.inode(store.configURL), before)
    }

    private static func inode(_ url: URL) throws -> NSNumber {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attrs[.systemFileNumber] as? NSNumber)
    }
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `swift test --filter PageStoreValidationTests`
Expected: `testLoadKeepsDuplicateIDPagesAndMintsNewIDs` fails with `StoreError.corrupt`. `testLoadMintsMissingPageIDAndRewritesFile` fails with `StoreError.corrupt` (the `id` key is required today). `testCleanLoadDoesNotRewriteConfigFile` passes already.

- [ ] **Step 3: Mint a missing or malformed page id on decode**

In `Sources/StatusCore/Models.swift`, in `extension WatchedPage: Codable`, replace the `id` line of `init(from:)`:

```swift
        let rawID = try container.decodeIfPresent(String.self, forKey: .id)
        id = rawID.flatMap(UUID.init(uuidString:)) ?? UUID()
```

- [ ] **Step 4: Make `PageStore.load` normalise and rewrite**

In `Sources/StatusCore/PageStore.swift`, replace `load()` and add the two helpers. Keep `validate(_:)` as it is — `save` still calls it.

```swift
    public func load() throws -> AppConfig {
        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            let nsError = error as NSError
            guard nsError.domain == NSCocoaErrorDomain,
                  nsError.code == NSFileReadNoSuchFileError || nsError.code == NSFileNoSuchFileError else {
                throw error
            }
            return AppConfig()
        }
        let decoded: AppConfig
        do {
            decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            throw StoreError.corrupt
        }
        guard decoded.version <= AppConfig.currentVersion else { throw StoreError.corrupt }
        let config = Self.uniquingPageIDs(decoded)
        if Self.needsIDNormalisation(data) {
            try save(config)
        }
        return config
    }

    /// Keeps every page. The second and later pages with a repeated id get a fresh one.
    private static func uniquingPageIDs(_ config: AppConfig) -> AppConfig {
        var next = config
        var seen: Set<UUID> = []
        for index in next.pages.indices where !seen.insert(next.pages[index].id).inserted {
            let fresh = UUID()
            next.pages[index].id = fresh
            seen.insert(fresh)
        }
        return next
    }

    /// True when the file misses an id, holds an unreadable id, or repeats one.
    private static func needsIDNormalisation(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = root["pages"] as? [[String: Any]] else { return false }
        var seen: Set<String> = []
        for page in pages {
            guard let raw = page["id"] as? String, UUID(uuidString: raw) != nil else { return true }
            guard seen.insert(raw).inserted else { return true }
        }
        return false
    }
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `swift test --filter PageStoreValidationTests`
Expected: PASS (4 tests).

- [ ] **Step 6: Run the whole suite**

Run: `swift test`
Expected: PASS. `ProbeAndMonitorTests.testPageStoreLoadCorruptJSONThrows`, `testPageStoreLoadUnsupportedVersionThrows`, `testPageStoreLoadMissingFileReturnsEmptyConfigAndDoesNotWrite`, and `ComponentToggleTests.testOldConfigWithoutDisabledNamesStillLoads` all still pass unchanged.

- [ ] **Step 7: Add the changelog line**

In `CHANGELOG.md`, under `## [Unreleased]` → `### Changed`, add:

```markdown
- A hand-edited `config.json` loads. greendot gives a page without an `id` a new one, and gives a repeated `id` a new one. It rewrites the file only when it changed an `id`.
```

- [ ] **Step 8: Lint and commit**

```bash
swiftlint lint --strict
git add Sources/StatusCore/PageStore.swift Sources/StatusCore/Models.swift \
        Tests/StatusCoreTests/PageStoreValidationTests.swift CHANGELOG.md
git commit -m "[FEATURE] Load hand-edited config files without failing"
```

---

### Task 3: Split the cache into `state.json`

**Files:**
- Create: `Sources/StatusCore/StateFile.swift` (the `StateFile` struct and `extension AppConfig: Codable`)
- Modify: `Sources/StatusCore/PageStore.swift` (`AppConfig` declaration, `currentVersion`, `stateURL`, `load`, `save`, `writeIfChanged`)
- Modify: `Sources/StatusCore/Models.swift` (`WatchedPage.encode(to:)` drops `snapshot`)
- Create: `Tests/StatusCoreTests/StateFileSplitTests.swift`
- Modify: `Tests/StatusCoreTests/PollPerformanceTests.swift` (`testUnchangedPollDoesNotRewriteConfig`, `testChangedPollStillRewritesConfig`)
- Modify: `Tests/StatusCoreTests/ProbeAndMonitorTests.swift` (`testPageStoreLoadUnsupportedVersionThrows` only)
- Modify: `Tests/StatusCoreTests/MonitorFirstRunTests.swift` (add one test)
- Modify: `Tests/StatusCoreTests/PageStoreValidationTests.swift` (`testSaveRejectsDuplicateWatchedPageIDsBeforeWriting` also asserts no `state.json`)
- Modify: `CHANGELOG.md` (`[Unreleased]` → `### Added`)

**Interfaces:**
- Consumes: `PageStore.encoder`, `PageStore.uniquingPageIDs(_:)`, `PageStore.needsIDNormalisation(_:)`, `WatchedPage.encode(to:)` from Tasks 1 and 2.
- Produces:
  - `public let PageStore.stateURL: URL` (`<directory>/state.json`)
  - `public static let AppConfig.currentVersion = 2`
  - `struct StateFile: Codable` (internal to `StatusCore`) with `version: Int`, `didSetLaunchAtLogin: Bool`, `snapshots: [String: PageSnapshot]` keyed by `page.id.uuidString`
  - `extension AppConfig: Codable` with `CodingKeys { version, pages, didSetLaunchAtLogin }`; `encode(to:)` writes `version` and `pages` only; `init(from:)` reads `didSetLaunchAtLogin` with `decodeIfPresent` for version-1 files. Task 4 adds `pollSeconds` to the same `CodingKeys` and to both members.

- [ ] **Step 1: Write the failing tests**

Create `Tests/StatusCoreTests/StateFileSplitTests.swift`:

```swift
import XCTest
@testable import StatusCore

final class StateFileSplitTests: XCTestCase {
    func testSaveThenLoadRoundTripsSnapshotsAndLaunchFlagThroughStateFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig(didSetLaunchAtLogin: true)
        config.pages = [try Self.page(name: "GitHub")]

        try store.save(config)

        let configText = try XCTUnwrap(String(data: try Data(contentsOf: store.configURL), encoding: .utf8))
        let stateText = try XCTUnwrap(String(data: try Data(contentsOf: store.stateURL), encoding: .utf8))
        XCTAssertFalse(configText.contains("snapshot"), configText)
        XCTAssertFalse(configText.contains("didSetLaunchAtLogin"), configText)
        XCTAssertTrue(configText.contains("\"version\""), configText)
        XCTAssertTrue(stateText.contains("didSetLaunchAtLogin"), stateText)
        XCTAssertTrue(stateText.contains("snapshots"), stateText)

        let loaded = try store.load()
        XCTAssertTrue(loaded.didSetLaunchAtLogin)
        XCTAssertEqual(loaded.version, 2)
        XCTAssertEqual(loaded.pages.map(\.name), ["GitHub"])
        XCTAssertEqual(loaded.pages[0].snapshot?.overall, .green)
        XCTAssertEqual(loaded.pages[0].snapshot?.components.map(\.name), ["API"])
    }

    func testLoadWithoutStateFileDropsSnapshotsAndLaunchFlag() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig(didSetLaunchAtLogin: true)
        config.pages = [try Self.page(name: "GitHub")]
        try store.save(config)

        try FileManager.default.removeItem(at: store.stateURL)

        let loaded = try store.load()
        XCTAssertFalse(loaded.didSetLaunchAtLogin)
        XCTAssertEqual(loaded.pages.map(\.name), ["GitHub"])
        XCTAssertNil(loaded.pages[0].snapshot)
        XCTAssertEqual(loaded.pages[0].displaySeverity, .grey)
    }

    func testVersion1FileLoadsInlineStateAndNextSaveSplitsIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        try Data(Self.legacyConfigJSON.utf8).write(to: store.configURL)

        let loaded = try store.load()
        XCTAssertTrue(loaded.didSetLaunchAtLogin)
        XCTAssertEqual(loaded.pages[0].snapshot?.overall, .yellow)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.stateURL.path))

        try store.save(loaded)

        let configData = try Data(contentsOf: store.configURL)
        let configText = try XCTUnwrap(String(data: configData, encoding: .utf8))
        let stateText = try XCTUnwrap(String(data: try Data(contentsOf: store.stateURL), encoding: .utf8))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: configData) as? [String: Any])
        XCTAssertFalse(configText.contains("snapshot"), configText)
        XCTAssertEqual(root["version"] as? Int, 2)
        XCTAssertNil(root["didSetLaunchAtLogin"])
        XCTAssertTrue(stateText.contains("00000000-0000-0000-0000-000000000001"), stateText)
        XCTAssertEqual(try store.load().pages[0].snapshot?.overall, .yellow)
    }

    func testStateFileSnapshotBeatsInlineVersion1Snapshot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        let state = """
        {
          "version": 2,
          "didSetLaunchAtLogin": false,
          "snapshots": {
            "00000000-0000-0000-0000-000000000001": {
              "name": "GitHub",
              "url": "https://www.githubstatus.com",
              "provider": "statuspage",
              "overall": "red",
              "components": [],
              "incidents": [],
              "isUnreachable": false
            }
          }
        }
        """
        try Data(Self.legacyConfigJSON.utf8).write(to: store.configURL)
        try Data(state.utf8).write(to: store.stateURL)

        let loaded = try store.load()

        XCTAssertEqual(loaded.pages[0].snapshot?.overall, .red)
        XCTAssertFalse(loaded.didSetLaunchAtLogin)
    }

    /// A version-1 file: the snapshot is inline and `didSetLaunchAtLogin` is at the top level.
    private static let legacyConfigJSON = """
    {
      "version": 1,
      "didSetLaunchAtLogin": true,
      "pages": [
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "url": "https://www.githubstatus.com",
          "name": "GitHub",
          "notificationsEnabled": true,
          "disabledComponentNames": [],
          "snapshot": {
            "name": "GitHub",
            "url": "https://www.githubstatus.com",
            "provider": "statuspage",
            "overall": "yellow",
            "components": [
              {"id": "c1", "name": "API", "severity": "yellow",
               "statusText": "Degraded", "children": [], "isGroup": false}
            ],
            "incidents": [],
            "isUnreachable": false
          }
        }
      ]
    }
    """

    private static func page(name: String) throws -> WatchedPage {
        let url = try XCTUnwrap(URL(string: "https://www.githubstatus.com"))
        return WatchedPage(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            url: url,
            name: name,
            snapshot: PageSnapshot(
                name: name,
                url: url,
                provider: .statuspage,
                overall: .green,
                components: [ComponentStatus(name: "API", severity: .green, statusText: "Operational")],
                incidents: [],
                isUnreachable: false
            )
        )
    }
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `swift test --filter StateFileSplitTests`
Expected: compile failure — `PageStore` has no member `stateURL`.

- [ ] **Step 3: Create `StateFile.swift`**

Create `Sources/StatusCore/StateFile.swift`:

```swift
import Foundation

/// `state.json`. The machine-local cache. `config.json` holds settings only.
struct StateFile: Codable {
    enum CodingKeys: String, CodingKey {
        case version, didSetLaunchAtLogin, snapshots
    }

    var version: Int
    var didSetLaunchAtLogin: Bool
    var snapshots: [String: PageSnapshot]

    init(
        version: Int = AppConfig.currentVersion,
        didSetLaunchAtLogin: Bool,
        snapshots: [String: PageSnapshot]
    ) {
        self.version = version
        self.didSetLaunchAtLogin = didSetLaunchAtLogin
        self.snapshots = snapshots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? AppConfig.currentVersion
        didSetLaunchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .didSetLaunchAtLogin) ?? false
        snapshots = try container.decodeIfPresent([String: PageSnapshot].self, forKey: .snapshots) ?? [:]
    }
}

extension AppConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case version, pages, didSetLaunchAtLogin
    }

    /// `didSetLaunchAtLogin` is read for version-1 files only. `state.json` wins when it exists.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? AppConfig.currentVersion
        pages = try container.decodeIfPresent([WatchedPage].self, forKey: .pages) ?? []
        didSetLaunchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .didSetLaunchAtLogin) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(pages, forKey: .pages)
    }
}
```

- [ ] **Step 4: Drop the snapshot from the encoded page**

In `Sources/StatusCore/Models.swift`, delete the last line of `WatchedPage.encode(to:)` so it reads:

```swift
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(name, forKey: .name)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(disabledComponentNames.sorted(), forKey: .disabledComponentNames)
    }
```

Leave `init(from:)` alone. It still decodes an inline version-1 `snapshot`.

- [ ] **Step 5: Split the two files in `PageStore`**

In `Sources/StatusCore/PageStore.swift`:

Change the `AppConfig` declaration line (the custom `Codable` now lives in `StateFile.swift`) and bump the version:

```swift
public struct AppConfig: Equatable, Sendable {
    public static let currentVersion = 2
```

Add `stateURL` and set it in `init`:

```swift
public final class PageStore: @unchecked Sendable {
    public let configURL: URL
    public let stateURL: URL
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
        self.configURL = directory.appendingPathComponent("config.json")
        self.stateURL = directory.appendingPathComponent("state.json")
    }
```

In `load()`, normalise the version and merge the state file. Replace the tail of `load()` (everything after the `guard decoded.version` line) with:

```swift
        var config = Self.uniquingPageIDs(decoded)
        config.version = AppConfig.currentVersion
        applyState(to: &config)
        if Self.needsIDNormalisation(data) {
            try save(config)
        }
        return config
    }

    /// A cache file that cannot be read is ignored. Settings never depend on it.
    private func applyState(to config: inout AppConfig) {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(StateFile.self, from: data) else { return }
        config.didSetLaunchAtLogin = state.didSetLaunchAtLogin
        for index in config.pages.indices {
            if let snapshot = state.snapshots[config.pages[index].id.uuidString] {
                config.pages[index].snapshot = snapshot
            }
        }
    }
```

Replace `save(_:)` and add `writeIfChanged`:

```swift
    public func save(_ config: AppConfig) throws {
        try validate(config)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeIfChanged(try Self.encoder.encode(config), to: configURL)
        let state = StateFile(
            didSetLaunchAtLogin: config.didSetLaunchAtLogin,
            snapshots: Self.snapshots(of: config)
        )
        try writeIfChanged(try Self.encoder.encode(state), to: stateURL)
    }

    private static func snapshots(of config: AppConfig) -> [String: PageSnapshot] {
        var result: [String: PageSnapshot] = [:]
        for page in config.pages {
            result[page.id.uuidString] = page.snapshot
        }
        return result
    }

    private func writeIfChanged(_ data: Data, to url: URL) throws {
        if let existing = try? Data(contentsOf: url), existing == data { return }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
```

- [ ] **Step 6: Run the new tests and watch them pass**

Run: `swift test --filter StateFileSplitTests`
Expected: PASS (4 tests).

- [ ] **Step 7: Update the inode tests in `PollPerformanceTests`**

In `Tests/StatusCoreTests/PollPerformanceTests.swift`, replace the two tests. The store now rewrites `state.json` for a snapshot change and leaves `config.json` alone.

```swift
    func testUnchangedPollDoesNotRewriteConfig() async throws {
        let client = MapHTTPClient(byPath: [
            "/api/v2/summary.json": (Self.statuspageJSON, 200)
        ])
        let (monitor, dir) = try seededMonitor(
            client: client,
            pages: [BenchmarkFixtures.greenPage(host: "a.example", name: "A", provider: .statuspage)]
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        _ = try await monitor.pollAll()
        XCTAssertEqual(monitor.pages[0].displaySeverity, .yellow)
        XCTAssertEqual(monitor.pages[0].snapshot?.incidents.first?.title, "API slow")
        let configAfterFirst = try inode(store.configURL)
        let stateAfterFirst = try inode(store.stateURL)
        _ = try await monitor.pollAll()
        XCTAssertEqual(try inode(store.configURL), configAfterFirst)
        XCTAssertEqual(try inode(store.stateURL), stateAfterFirst)
        XCTAssertEqual(monitor.pages[0].displaySeverity, .yellow)
    }

    func testChangedPollStillRewritesConfig() async throws {
        let client = MapHTTPClient(byPath: [
            "/api/v2/summary.json": (Self.statuspageJSON, 200)
        ])
        let (monitor, dir) = try seededMonitor(
            client: client,
            pages: [BenchmarkFixtures.greenPage(host: "a.example", name: "A", provider: .statuspage)]
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        let configBefore = try inode(store.configURL)
        let stateBefore = try inode(store.stateURL)
        _ = try await monitor.pollAll()
        XCTAssertEqual(try inode(store.configURL), configBefore)
        XCTAssertNotEqual(try inode(store.stateURL), stateBefore)
        XCTAssertEqual(monitor.pages[0].displaySeverity, .yellow)
    }
```

- [ ] **Step 8: Update the version test in `ProbeAndMonitorTests`**

In `Tests/StatusCoreTests/ProbeAndMonitorTests.swift`, change the payload of `testPageStoreLoadUnsupportedVersionThrows` from version 99 to version 3, and add a version-2 test next to it:

```swift
    func testPageStoreLoadUnsupportedVersionThrows() throws {
        try assertLoadThrows(
            Data(#"{"version":3,"pages":[],"didSetLaunchAtLogin":false}"#.utf8),
            StoreError.corrupt
        )
    }

    func testPageStoreLoadAcceptsCurrentVersion() throws {
        let dir = try writeConfig(Data(#"{"version":2,"pollSeconds":60,"pages":[]}"#.utf8))
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = try PageStore(directory: dir).load()
        XCTAssertTrue(config.pages.isEmpty)
        XCTAssertEqual(config.version, 2)
    }
```

(`pollSeconds` is an unknown key until Task 4. `init(from:)` ignores unknown keys, so this passes now and keeps passing after Task 4.)

- [ ] **Step 9: Assert the flag lives in `state.json`**

In `Tests/StatusCoreTests/MonitorFirstRunTests.swift`, add this test to the class:

```swift
    func testLaunchAtLoginFlagRoundTripsThroughStateFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PageStore(directory: directory)

        try store.save(AppConfig(didSetLaunchAtLogin: true))

        let configText = try XCTUnwrap(String(data: try Data(contentsOf: store.configURL), encoding: .utf8))
        let stateText = try XCTUnwrap(String(data: try Data(contentsOf: store.stateURL), encoding: .utf8))
        XCTAssertFalse(configText.contains("didSetLaunchAtLogin"), configText)
        XCTAssertTrue(stateText.contains("didSetLaunchAtLogin"), stateText)
        XCTAssertTrue(try store.load().didSetLaunchAtLogin)
    }
```

In `Tests/StatusCoreTests/PageStoreValidationTests.swift`, add one line to the end of `testSaveRejectsDuplicateWatchedPageIDsBeforeWriting`:

```swift
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.stateURL.path))
```

- [ ] **Step 10: Run the whole suite**

Run: `swift test`
Expected: PASS. Check in particular `swift test --filter ComponentToggleTests` (the version-1 fixture in `testOldConfigWithoutDisabledNamesStillLoads` still loads) and `swift test --filter MonitorFirstRunTests` (`testFirstRunSaveFailureDoesNotEnableLaunchAtLogin` still throws, because a directory in place of `config.json` makes `writeIfChanged` fail before `state.json` is touched).

- [ ] **Step 11: Add the changelog line**

In `CHANGELOG.md`, under `## [Unreleased]` → `### Added`, add:

```markdown
- `state.json` holds the cached poll results and the launch-at-login flag. `config.json` holds only your settings, so you can copy it to another machine or send it to a colleague. greendot reads a version 1 file and splits it on the next save.
```

- [ ] **Step 12: Lint and commit**

```bash
swiftlint lint --strict
git add Sources/StatusCore/StateFile.swift Sources/StatusCore/PageStore.swift \
        Sources/StatusCore/Models.swift Tests/StatusCoreTests/StateFileSplitTests.swift \
        Tests/StatusCoreTests/PollPerformanceTests.swift Tests/StatusCoreTests/ProbeAndMonitorTests.swift \
        Tests/StatusCoreTests/MonitorFirstRunTests.swift Tests/StatusCoreTests/PageStoreValidationTests.swift \
        CHANGELOG.md
git commit -m "[FEATURE] Split cached poll data into state.json"
```

---

### Task 4: `pollSeconds` in the config file

**Files:**
- Modify: `Sources/StatusCore/PageStore.swift` (`AppConfig` property, init, `defaultPollSeconds`, `validPollSeconds`)
- Modify: `Sources/StatusCore/StateFile.swift` (`AppConfig` `CodingKeys`, `init(from:)`, `encode(to:)`)
- Modify: `Sources/StatusCore/Monitor.swift` (add the `pollSeconds` accessor)
- Modify: `Sources/greendot/AppDelegate.swift` (`pollInterval(from:configured:)` and its one call site)
- Create: `Tests/StatusCoreTests/PollSecondsTests.swift`
- Modify: `Tests/greendotTests/PanelLifecycleTests.swift` (the two poll-interval tests, plus three new ones)
- Modify: `CHANGELOG.md` (`[Unreleased]` → `### Added`)

**Interfaces:**
- Consumes: `AppConfig`, `PageStore.load()`, `Monitor.withStateLock(_:)`
- Produces:
  - `public var AppConfig.pollSeconds: TimeInterval` (default `AppConfig.defaultPollSeconds`)
  - `public static let AppConfig.defaultPollSeconds: TimeInterval = 60`
  - `public static func AppConfig.validPollSeconds(_ value: TimeInterval?) -> TimeInterval`
  - `public var Monitor.pollSeconds: TimeInterval`
  - `nonisolated static func AppDelegate.pollInterval(from rawValue: String?, configured: TimeInterval) -> TimeInterval` — Task 5 calls this from `reloadConfig()`.

- [ ] **Step 1: Write the failing StatusCore tests**

Create `Tests/StatusCoreTests/PollSecondsTests.swift`:

```swift
import XCTest
@testable import StatusCore
import TestSupport

final class PollSecondsTests: XCTestCase {
    func testMissingPollSecondsDecodesToSixty() throws {
        let config = try Self.load(#"{"version":2,"pages":[]}"#)
        XCTAssertEqual(config.pollSeconds, 60)
    }

    func testInvalidPollSecondsDecodesToSixty() throws {
        XCTAssertEqual(try Self.load(#"{"version":2,"pollSeconds":0,"pages":[]}"#).pollSeconds, 60)
        XCTAssertEqual(try Self.load(#"{"version":2,"pollSeconds":-5,"pages":[]}"#).pollSeconds, 60)
        XCTAssertEqual(try Self.load(#"{"version":2,"pollSeconds":"soon","pages":[]}"#).pollSeconds, 60)
    }

    func testValidPollSecondsDecodes() throws {
        XCTAssertEqual(try Self.load(#"{"version":2,"pollSeconds":15,"pages":[]}"#).pollSeconds, 15)
        XCTAssertEqual(try Self.load(#"{"version":2,"pollSeconds":0.5,"pages":[]}"#).pollSeconds, 0.5)
    }

    func testSavedConfigAlwaysWritesPollSeconds() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pollSeconds = 300
        try store.save(config)
        let text = try XCTUnwrap(String(data: try Data(contentsOf: store.configURL), encoding: .utf8))
        XCTAssertTrue(text.contains("pollSeconds"), text)
        XCTAssertEqual(try store.load().pollSeconds, 300)
    }

    func testMonitorExposesLoadedPollSeconds() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        try Data(#"{"version":2,"pollSeconds":120,"pages":[]}"#.utf8).write(to: store.configURL)
        let monitor = Monitor(store: store, client: MapHTTPClient())
        XCTAssertEqual(monitor.pollSeconds, 60)
        try monitor.load()
        XCTAssertEqual(monitor.pollSeconds, 120)
    }

    private static func load(_ json: String) throws -> AppConfig {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        try Data(json.utf8).write(to: store.configURL)
        return try store.load()
    }
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `swift test --filter PollSecondsTests`
Expected: compile failure — `AppConfig` has no member `pollSeconds`.

- [ ] **Step 3: Add `pollSeconds` to `AppConfig`**

In `Sources/StatusCore/PageStore.swift`, replace the `AppConfig` body:

```swift
public struct AppConfig: Equatable, Sendable {
    public static let currentVersion = 2
    public static let defaultPollSeconds: TimeInterval = 60
    public var version: Int
    public var pollSeconds: TimeInterval
    public var pages: [WatchedPage]
    public var didSetLaunchAtLogin: Bool

    public init(
        version: Int = currentVersion,
        pollSeconds: TimeInterval = defaultPollSeconds,
        pages: [WatchedPage] = [],
        didSetLaunchAtLogin: Bool = false
    ) {
        self.version = version
        self.pollSeconds = pollSeconds
        self.pages = pages
        self.didSetLaunchAtLogin = didSetLaunchAtLogin
    }

    /// Missing, non-finite, or zero and below becomes the default.
    public static func validPollSeconds(_ value: TimeInterval?) -> TimeInterval {
        guard let value, value.isFinite, value > 0 else { return defaultPollSeconds }
        return value
    }
}
```

- [ ] **Step 4: Code `pollSeconds` in both directions**

In `Sources/StatusCore/StateFile.swift`, update the three `AppConfig` members:

```swift
    enum CodingKeys: String, CodingKey {
        case version, pollSeconds, pages, didSetLaunchAtLogin
    }
```

```swift
        let rawPollSeconds = (try? container.decodeIfPresent(TimeInterval.self, forKey: .pollSeconds)) ?? nil
        pollSeconds = AppConfig.validPollSeconds(rawPollSeconds)
```

(put those two lines after the `version` line in `init(from:)`), and in `encode(to:)`:

```swift
        try container.encode(pollSeconds, forKey: .pollSeconds)
```

- [ ] **Step 5: Expose the interval on `Monitor`**

In `Sources/StatusCore/Monitor.swift`, add under the `pages` property:

```swift
    public var pollSeconds: TimeInterval {
        withStateLock { config.pollSeconds }
    }
```

- [ ] **Step 6: Run the StatusCore tests and watch them pass**

Run: `swift test --filter PollSecondsTests`
Expected: PASS (5 tests).

- [ ] **Step 7: Write the failing AppDelegate tests**

In `Tests/greendotTests/PanelLifecycleTests.swift`, replace the two poll-interval tests at the end of the `extension PanelLifecycleTests` block with these five:

```swift
    func testPollIntervalUsesDefaultForInvalidValues() {
        let invalidValues: [String?] = [
            nil,
            "",
            "not-a-number",
            "0",
            "-10",
            "NaN",
            "infinity",
            "-infinity"
        ]

        for value in invalidValues {
            XCTAssertEqual(
                AppDelegate.pollInterval(from: value, configured: 60),
                60,
                "Expected default for \(value ?? "missing")"
            )
        }
    }

    func testPollIntervalAcceptsFinitePositiveValues() {
        for value in ["0.25", "60", "3600"] {
            XCTAssertEqual(AppDelegate.pollInterval(from: value, configured: 60), Double(value))
        }
    }

    func testPollIntervalUsesConfiguredValueWhenEnvIsMissingOrInvalid() {
        XCTAssertEqual(AppDelegate.pollInterval(from: nil, configured: 300), 300)
        XCTAssertEqual(AppDelegate.pollInterval(from: "not-a-number", configured: 300), 300)
        XCTAssertEqual(AppDelegate.pollInterval(from: "0", configured: 300), 300)
    }

    func testPollIntervalEnvOverridesConfiguredValue() {
        XCTAssertEqual(AppDelegate.pollInterval(from: "15", configured: 300), 15)
    }

    func testPollIntervalFallsBackToDefaultForInvalidConfiguredValue() {
        XCTAssertEqual(AppDelegate.pollInterval(from: nil, configured: 0), 60)
        XCTAssertEqual(AppDelegate.pollInterval(from: nil, configured: -1), 60)
        XCTAssertEqual(AppDelegate.pollInterval(from: nil, configured: .nan), 60)
    }
```

- [ ] **Step 8: Run the tests and watch them fail**

Run: `swift test --filter PanelLifecycleTests`
Expected: compile failure — `pollInterval(from:)` takes one argument.

- [ ] **Step 9: Add the `configured` argument**

In `Sources/greendot/AppDelegate.swift`, replace `pollInterval(from:)`:

```swift
    nonisolated static func pollInterval(from rawValue: String?, configured: TimeInterval) -> TimeInterval {
        if let rawValue, let interval = Double(rawValue), interval.isFinite, interval > 0 {
            return interval
        }
        return AppConfig.validPollSeconds(configured)
    }
```

and update the one call site in `applicationDidFinishLaunching`:

```swift
            let poll = Self.pollInterval(
                from: ProcessInfo.processInfo.environment["GREENDOT_POLL_SECONDS"],
                configured: monitor.pollSeconds
            )
```

- [ ] **Step 10: Run the tests and watch them pass**

Run: `swift test --filter PanelLifecycleTests`
Expected: PASS.

- [ ] **Step 11: Run the whole suite**

Run: `swift test`
Expected: PASS.

- [ ] **Step 12: Add the changelog line**

In `CHANGELOG.md`, under `## [Unreleased]` → `### Added`, add:

```markdown
- `pollSeconds` in `config.json` sets the time between polls. The default is 60 seconds. `GREENDOT_POLL_SECONDS` still overrides the file.
```

- [ ] **Step 13: Lint and commit**

```bash
swiftlint lint --strict
git add Sources/StatusCore/PageStore.swift Sources/StatusCore/StateFile.swift \
        Sources/StatusCore/Monitor.swift Sources/greendot/AppDelegate.swift \
        Tests/StatusCoreTests/PollSecondsTests.swift Tests/greendotTests/PanelLifecycleTests.swift \
        CHANGELOG.md
git commit -m "[FEATURE] Read the poll interval from config.json"
```

---

### Task 5: "Reveal Config File" and "Reload Config"

**Files:**
- Modify: `Sources/greendot/MenuBuilder.swift` (`StatusMenuHandlers` fields, two `addItem` lines in `build(for:)`)
- Modify: `Sources/greendot/AppDelegate.swift` (`store` and `revealConfigFile` properties, `pollTimer` visibility, `applicationDidFinishLaunching`, `makeStatusMenuHandlers`, and `revealConfig` / `reloadConfig` / `restartPollTimer` in the bottom extension)
- Create: `Tests/greendotTests/AppDelegateConfigMenuTests.swift`
- Modify: `Tests/greendotTests/MenuBuilderTests.swift` (4 handler literals at lines 74, 107, 137, 174; two new tests)
- Modify: `Tests/greendotTests/StatusMenuControllerTests.swift` (handler literal at line 246)
- Modify: `Tests/greendotTests/EmptyComponentMenuTests.swift` (handler literal at line 25)
- Modify: `Tests/greendotTests/PerformanceHarnessTests.swift` (handler literal at line 12)
- Modify: `CHANGELOG.md` (`[Unreleased]` → `### Added`)

**Interfaces:**
- Consumes: `AppDelegate.pollInterval(from:configured:)` and `Monitor.pollSeconds` from Task 4; `PageStore.configURL`; `AppDelegate.loadMonitor(_:)`; `AppDelegate.presentError`.
- Produces:
  - `StatusMenuHandlers.onRevealConfig: () -> Void` and `StatusMenuHandlers.onReloadConfig: () -> Void`, declared directly after `onRefresh`. **Every `StatusMenuHandlers(...)` literal is positional and complete, so all nine call sites must gain both arguments after `onRefresh:`.**
  - Menu items "Reveal Config File" (`reveal-config`) and "Reload Config" (`reload-config`), in that order, directly under "Refresh".
  - `AppDelegate.revealConfig()`, `AppDelegate.reloadConfig()`, `AppDelegate.restartPollTimer(interval:)`
  - `var AppDelegate.store: PageStore?`, `var AppDelegate.monitor: Monitor?`, `var AppDelegate.pollTimer: Timer?`, `var AppDelegate.revealConfigFile: @MainActor (URL) -> Void`

- [ ] **Step 1: Write the failing MenuBuilder tests**

In `Tests/greendotTests/MenuBuilderTests.swift`, add these two tests to the class (put them under `testMenuHasAboutGreendotImmediatelyAboveQuit`):

```swift
    func testRevealAndReloadConfigFollowRefresh() throws {
        let menu = Self.menu(page: Self.nestedPage(), onOpen: { _ in })
        let titles = menu.items.map(\.title)
        let refresh = try XCTUnwrap(titles.firstIndex(of: "Refresh"), titles.joined(separator: " | "))
        XCTAssertEqual(titles[refresh + 1], "Reveal Config File")
        XCTAssertEqual(titles[refresh + 2], "Reload Config")
        XCTAssertEqual(menu.items[refresh + 1].identifier?.rawValue, "reveal-config")
        XCTAssertEqual(menu.items[refresh + 2].identifier?.rawValue, "reload-config")
    }

    func testRevealAndReloadConfigInvokeCallbacks() {
        var revealCount = 0
        var reloadCount = 0
        let menu = MenuBuilder(
            handlers: StatusMenuHandlers(
                onAdd: {},
                onEdit: { _ in },
                onRemove: { _ in },
                onToggleNotifications: { _ in },
                onOpen: { _ in },
                onRefresh: {},
                onRevealConfig: { revealCount += 1 },
                onReloadConfig: { reloadCount += 1 },
                onToggleLaunchAtLogin: {},
                onAbout: {},
                onQuit: {}
            )
        ).build(for: Self.state(pages: []))
        Self.invoke(menu.item(withTitle: "Reveal Config File"))
        Self.invoke(menu.item(withTitle: "Reload Config"))
        XCTAssertEqual(revealCount, 1)
        XCTAssertEqual(reloadCount, 1)
    }
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `swift test --filter MenuBuilderTests`
Expected: compile failure — `StatusMenuHandlers` has no `onRevealConfig` argument.

- [ ] **Step 3: Add the handlers and the two menu items**

In `Sources/greendot/MenuBuilder.swift`, add the two fields to `StatusMenuHandlers` directly after `onRefresh`:

```swift
struct StatusMenuHandlers {
    var onAdd: () -> Void
    var onEdit: (UUID) -> Void
    var onRemove: (UUID) -> Void
    var onToggleNotifications: (UUID) -> Void
    var onOpen: (URL) -> Void
    var onRefresh: () -> Void
    var onRevealConfig: () -> Void
    var onReloadConfig: () -> Void
    var onToggleLaunchAtLogin: () -> Void
    var onAbout: () -> Void
    var onQuit: () -> Void
}
```

In `build(for:)`, add two lines directly under the "Refresh" line:

```swift
        menu.addItem(actionItem("Refresh", identifier: "refresh", action: handlers.onRefresh))
        menu.addItem(
            actionItem("Reveal Config File", identifier: "reveal-config", action: handlers.onRevealConfig)
        )
        menu.addItem(actionItem("Reload Config", identifier: "reload-config", action: handlers.onReloadConfig))
```

- [ ] **Step 4: Fix the other eight handler literals**

Add these two lines directly after the `onRefresh:` line of every remaining `StatusMenuHandlers(...)` literal:

```swift
                onRevealConfig: {},
                onReloadConfig: {},
```

Sites: `Tests/greendotTests/MenuBuilderTests.swift` lines 74, 107, 137 and the `handlers(onOpen:)` helper at line 174; `Tests/greendotTests/EmptyComponentMenuTests.swift` line 25; `Tests/greendotTests/PerformanceHarnessTests.swift` line 12 (indent there is 8 spaces, not 16).

`Tests/greendotTests/StatusMenuControllerTests.swift` line 246 uses the fail-on-unexpected style, so use:

```swift
            onRevealConfig: { XCTFail("Unexpected reveal-config action") },
            onReloadConfig: { XCTFail("Unexpected reload-config action") },
```

`Sources/greendot/AppDelegate.swift` (`makeStatusMenuHandlers`) is handled in Step 7.

- [ ] **Step 5: Write the failing AppDelegate tests**

Create `Tests/greendotTests/AppDelegateConfigMenuTests.swift`:

```swift
import AppKit
import StatusCore
import XCTest
@testable import greendot
import TestSupport

@MainActor
final class AppDelegateConfigMenuTests: XCTestCase {
    func testRevealConfigSelectsTheConfigFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        delegate.store = store
        var revealed: [URL] = []
        delegate.revealConfigFile = { revealed.append($0) }

        delegate.revealConfig()

        XCTAssertEqual(revealed, [store.configURL])
    }

    func testReloadConfigPicksUpAPageAddedOnDiskAndRestartsTheTimer() throws {
        _ = NSApplication.shared
        let (dir, store, monitor) = try Self.seeded()
        defer { try? FileManager.default.removeItem(at: dir) }
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        defer { delegate.pollTimer?.invalidate() }
        delegate.store = store
        delegate.monitor = monitor
        var presented: Error?
        delegate.presentError = { presented = $0 }
        XCTAssertEqual(monitor.pages.map(\.name), ["GitHub"])

        var next = try store.load()
        next.pollSeconds = 300
        next.pages.append(
            WatchedPage(url: try XCTUnwrap(URL(string: "https://status.openai.com")), name: "OpenAI")
        )
        try store.save(next)

        delegate.reloadConfig()

        XCTAssertNil(presented)
        XCTAssertEqual(monitor.pages.map(\.name), ["GitHub", "OpenAI"])
        XCTAssertEqual(delegate.pollTimer?.timeInterval, 300)
    }

    func testReloadConfigWithCorruptFilePresentsErrorAndKeepsPages() throws {
        _ = NSApplication.shared
        let (dir, store, monitor) = try Self.seeded()
        defer { try? FileManager.default.removeItem(at: dir) }
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        defer { delegate.pollTimer?.invalidate() }
        delegate.store = store
        delegate.monitor = monitor
        var presented: Error?
        delegate.presentError = { presented = $0 }

        try Data("{".utf8).write(to: store.configURL)
        delegate.reloadConfig()

        XCTAssertEqual(presented as? StoreError, .corrupt)
        XCTAssertEqual(monitor.pages.map(\.name), ["GitHub"])
        XCTAssertNil(delegate.pollTimer)
    }

    private static func seeded() throws -> (URL, PageStore, Monitor) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pages = [
            WatchedPage(url: try XCTUnwrap(URL(string: "https://www.githubstatus.com")), name: "GitHub")
        ]
        try store.save(config)
        let monitor = Monitor(store: store, client: MapHTTPClient())
        try monitor.load()
        return (dir, store, monitor)
    }
}
```

Note: `testReloadConfigPicksUpAPageAddedOnDiskAndRestartsTheTimer` asserts the timer interval, so it fails if `GREENDOT_POLL_SECONDS` is set in your shell. Unset it before running the suite.

- [ ] **Step 6: Run the tests and watch them fail**

Run: `swift test --filter AppDelegateConfigMenuTests`
Expected: compile failure — `AppDelegate` has no `store`, `revealConfigFile`, `revealConfig()`, `reloadConfig()`, or accessible `pollTimer`.

- [ ] **Step 7: Wire the delegate**

In `Sources/greendot/AppDelegate.swift`, change the stored properties at the top of the class:

```swift
    private var statusMenu: StatusMenuController?
    var monitor: Monitor?
    var store: PageStore?
    var pollTimer: Timer?
    private var pulseTimer: Timer?
```

and add the injectable reveal closure next to `presentError`:

```swift
    var revealConfigFile: @MainActor (URL) -> Void = { url in
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
```

In `applicationDidFinishLaunching`, keep the store and use the shared timer helper. Replace

```swift
        let monitor = Monitor(store: store, client: client)
```

with

```swift
        let monitor = Monitor(store: store, client: client)
        self.store = store
```

and replace the whole `if Self.shouldPoll(loadSucceeded: loadSucceeded) { let poll = ...; pollTimer = Timer.scheduledTimer(...) }` block with:

```swift
        if Self.shouldPoll(loadSucceeded: loadSucceeded) {
            restartPollTimer(interval: Self.pollInterval(
                from: ProcessInfo.processInfo.environment["GREENDOT_POLL_SECONDS"],
                configured: monitor.pollSeconds
            ))
        }
```

In `makeStatusMenuHandlers`, add the two handlers after `onRefresh`:

```swift
            onRefresh: { [weak self] in
                Task { await self?.pollAndRefresh() }
            },
            onRevealConfig: { [weak self] in self?.revealConfig() },
            onReloadConfig: { [weak self] in self?.reloadConfig() },
```

- [ ] **Step 8: Add the three methods to the bottom extension**

Add these to the existing `extension AppDelegate { ... }` at the end of `Sources/greendot/AppDelegate.swift` (the extension keeps `AppDelegate`'s own body under the SwiftLint `type_body_length` limit):

```swift
    @MainActor
    func revealConfig() {
        guard let store else { return }
        revealConfigFile(store.configURL)
    }

    /// Reads the file again. On failure the in-memory config and the old timer stay.
    @MainActor
    func reloadConfig() {
        guard let monitor, loadMonitor(monitor) else { return }
        rebuild()
        restartPollTimer(interval: Self.pollInterval(
            from: ProcessInfo.processInfo.environment["GREENDOT_POLL_SECONDS"],
            configured: monitor.pollSeconds
        ))
        Task { await self.pollAndRefresh() }
    }

    @MainActor
    func restartPollTimer(interval: TimeInterval) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollAndRefresh()
            }
        }
    }
```

`rebuild()` and `pollAndRefresh()` are `private` at file scope, so the extension in the same file reaches them.

- [ ] **Step 9: Run both test classes and watch them pass**

Run: `swift test --filter MenuBuilderTests`
Expected: PASS.
Run: `swift test --filter AppDelegateConfigMenuTests`
Expected: PASS (3 tests).

- [ ] **Step 10: Run the whole suite**

Run: `swift test`
Expected: PASS. `MenuBuilderTests.testMenuHasAboutGreendotImmediatelyAboveQuit` still passes: the new items sit above "Launch at Login", far from the About/Quit pair.

- [ ] **Step 11: Add the changelog line**

In `CHANGELOG.md`, under `## [Unreleased]` → `### Added`, add:

```markdown
- Reveal Config File and Reload Config in the status menu. Reveal Config File shows `config.json` in the Finder. Reload Config reads the file again, rebuilds the menu, restarts the poll timer, and polls once. A file that greendot cannot read shows an alert and keeps the pages on screen.
```

- [ ] **Step 12: Lint and commit**

```bash
swiftlint lint --strict
git add Sources/greendot/MenuBuilder.swift Sources/greendot/AppDelegate.swift \
        Tests/greendotTests/AppDelegateConfigMenuTests.swift Tests/greendotTests/MenuBuilderTests.swift \
        Tests/greendotTests/StatusMenuControllerTests.swift Tests/greendotTests/EmptyComponentMenuTests.swift \
        Tests/greendotTests/PerformanceHarnessTests.swift CHANGELOG.md
git commit -m "[FEATURE] Add Reveal Config File and Reload Config menu items"
```

---

### Task 6: Docs

**Files:**
- Modify: `README.md` (replace the whole `## Config` section, lines 34-38)
- Modify: `CHANGELOG.md` (reconcile the five `[Unreleased]` lines added by Tasks 1-5)

**Interfaces:**
- Consumes: everything Tasks 1-5 shipped. No production code changes in this task.

- [ ] **Step 1: Rewrite the README "Config" section**

In `README.md`, replace the section that runs from `## Config` to the line before `## License` with:

```markdown
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
```

- [ ] **Step 2: Reconcile the changelog**

Open `CHANGELOG.md`. Tasks 1-5 each added one line under `## [Unreleased]`. Check that the five lines below are present, that each sits under the right heading, and that the wording matches. Fix any line that drifted. Add nothing new.

`### Added`:

```markdown
- `state.json` holds the cached poll results and the launch-at-login flag. `config.json` holds only your settings, so you can copy it to another machine or send it to a colleague. greendot reads a version 1 file and splits it on the next save.
- `pollSeconds` in `config.json` sets the time between polls. The default is 60 seconds. `GREENDOT_POLL_SECONDS` still overrides the file.
- Reveal Config File and Reload Config in the status menu. Reveal Config File shows `config.json` in the Finder. Reload Config reads the file again, rebuilds the menu, restarts the poll timer, and polls once. A file that greendot cannot read shows an alert and keeps the pages on screen.
```

`### Changed`:

```markdown
- `config.json` is pretty-printed with sorted keys and plain slashes. `disabledComponentNames` is written as a sorted array. The same settings always produce the same bytes, so the file diffs cleanly.
- A hand-edited `config.json` loads. greendot gives a page without an `id` a new one, and gives a repeated `id` a new one. It rewrites the file only when it changed an `id`.
```

- [ ] **Step 3: Check the suite is still green**

Run: `swift test`
Expected: PASS. No production file changed in this task.

- [ ] **Step 4: Lint and commit**

```bash
swiftlint lint --strict
git add README.md CHANGELOG.md
git commit -m "[DOCS] Document the shareable config file"
```
