import Foundation
import CryptoKit

public final class PageStore: @unchecked Sendable {
    public let configURL: URL
    public let stateURL: URL
    private let directory: URL
    private let managedConfigURL: URL
    private var managedRequiredIDs: Set<UUID> = []
    private var managedOptionalIDs: Set<UUID> = []
    private var didLoadManagedConfig = false
    private let knownConfigLock = NSLock()
    /// The config bytes this store last read or wrote. A file that no longer matches them is the user's.
    private var lastKnownConfigData: Data?

    public init(directory: URL, managedConfigURL: URL? = nil) {
        self.directory = directory
        self.configURL = directory.appendingPathComponent("config.json")
        self.stateURL = directory.appendingPathComponent("state.json")
        self.managedConfigURL = managedConfigURL ?? Self.defaultManagedConfigURL
    }

    public static var defaultManagedConfigURL: URL {
        URL(fileURLWithPath: "/Library/Application Support/greendot/config.json")
    }

    public static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["GREENDOT_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("greendot", isDirectory: true)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

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
            // No pages, so no snapshots attach. The launch flag still belongs to the user.
            var config = AppConfig()
            config = try mergingManagedConfig(config)
            setLastKnownConfigData(nil)
            tightenPermissions()
            applyState(to: &config)
            return config
        }
        setLastKnownConfigData(data)
        tightenPermissions()
        let decoded: AppConfig
        do {
            decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            throw StoreError.corrupt
        }
        guard decoded.version <= AppConfig.currentVersion else { throw StoreError.corrupt }
        var config = Self.uniquingPageIDs(Self.strippingLegacyState(decoded))
        config = try mergingManagedConfig(config)
        config.version = AppConfig.currentVersion
        applyState(to: &config)
        if Self.needsIDNormalisation(data) {
            // Best effort. The ids are already unique in memory; the next successful save persists them.
            try? save(config)
        }
        return config
    }

    /// A file copied in from another machine can carry a wider mode. A feed url can hold a token.
    /// Best effort: a read-only volume or a foreign owner must not fail the load.
    private func tightenPermissions() {
        if isRegularFile(configURL) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        }
        if isRegularFile(stateURL) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        }
    }

    /// Only files. A directory left at a path needs its execute bit so save can clear it.
    /// A `URL` caches its resource values, so ask the file system instead.
    private func isRegularFile(_ url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType == .typeRegular
    }

    /// A cache file that cannot be read is ignored. Settings never depend on it.
    private func applyState(to config: inout AppConfig) {
        let exists = FileManager.default.fileExists(atPath: stateURL.path)
        guard let data = try? Data(contentsOf: stateURL) else {
            // A file that exists but cannot be read still proves the app has run before.
            if exists { config.didSetLaunchAtLogin = true }
            return
        }
        guard let state = try? JSONDecoder().decode(StateFile.self, from: data) else {
            // A file that cannot be decoded can only exist when the app has run before.
            config.didSetLaunchAtLogin = true
            return
        }
        config.didSetLaunchAtLogin = state.didSetLaunchAtLogin
        for index in config.pages.indices {
            guard let entry = state.snapshots[config.pages[index].id.uuidString] else { continue }
            // A cached result belongs to the url it was polled from. A hand-edited url drops it.
            config.pages[index].snapshot = entry.url == config.pages[index].url ? entry.snapshot : nil
        }
    }

    /// Version 2 keeps machine-local data in state.json only. Inline copies in a shared file are stale.
    /// A version-1 file keeps its inline data, which `applyState` then migrates.
    private static func strippingLegacyState(_ config: AppConfig) -> AppConfig {
        guard config.version >= 2 else { return config }
        var next = config
        next.didSetLaunchAtLogin = false
        for index in next.pages.indices {
            next.pages[index].snapshot = nil
        }
        return next
    }

    /// Keeps every page. The second and later pages with a repeated id get a fresh one.
    /// This must agree with `needsIDNormalisation`. Both compare parsed `UUID`s. Change the two together.
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

    /// True when a page has no id, an id string that is not a UUID, or an id another page also uses.
    /// This must agree with `uniquingPageIDs`. Both compare parsed `UUID`s. Change the two together.
    private static func needsIDNormalisation(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = root["pages"] as? [[String: Any]] else { return false }
        var seen: Set<UUID> = []
        for page in pages {
            guard let raw = page["id"] as? String, let parsed = UUID(uuidString: raw) else { return true }
            guard seen.insert(parsed).inserted else { return true }
        }
        return false
    }

    /// True when config.json differs from the bytes this store last read or wrote.
    public func hasConfigChangedOnDisk() -> Bool {
        knownConfigLock.lock()
        let known = lastKnownConfigData
        knownConfigLock.unlock()
        guard let known, let disk = try? Data(contentsOf: configURL) else { return false }
        return disk != known
    }

    public func save(_ config: AppConfig) throws {
        let previousManagedIDs = managedPageIDs()
        let managedIDsFromConfig = Set(config.pages.filter { $0.required != nil }.map(\.id))
        let managedPages = (try? readManagedPages()) ?? []
        let currentPolicyIDs = Self.managedPageIDs(from: managedPages)
        let requiredIDs = previousManagedIDs.required.union(currentPolicyIDs.required)
        let optionalIDs = previousManagedIDs.optional.union(currentPolicyIDs.optional).subtracting(requiredIDs)
        try validate(config)
        let currentIDs = Set(config.pages.map(\.id))
        let knownIDs = currentIDs.union(previousManagedIDs.required).union(previousManagedIDs.optional)
            .union(config.disabledManagedPageIDs.union(config.disabledManagedPages.map(\.id)))
        let loadedManagedConfig = managedConfigWasLoaded()
        let currentRequiredIDs = loadedManagedConfig
            ? currentPolicyIDs.required.intersection(knownIDs)
            : currentPolicyIDs.required
        let requiredToKeep = previousManagedIDs.required.union(currentRequiredIDs)
        guard requiredToKeep.isSubset(of: currentIDs) else { throw StoreError.requiredManagedPage }
        let previousConfig: Data?
        do {
            previousConfig = try Data(contentsOf: configURL)
        } catch {
            // A file that exists but cannot be read cannot be rolled back. Refuse to write over it.
            guard !FileManager.default.fileExists(atPath: configURL.path) else { throw error }
            previousConfig = nil
        }
        try refuseWhenConfigChangedOnDisk(previousConfig)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        clearDirectoryAtStatePath()
        var localConfig = config
        let allManagedIDs = requiredIDs.union(optionalIDs).union(managedIDsFromConfig)
        let knownOptionalIDs = previousManagedIDs.optional.union(knownIDs)
        localConfig.disabledManagedPageIDs.formUnion(optionalIDs.subtracting(currentIDs).intersection(knownOptionalIDs))
        localConfig.pages = config.pages.filter { !allManagedIDs.contains($0.id) }
        let configData = try Self.encoder.encode(localConfig)
        try writeIfChanged(configData, to: configURL)
        let state = StateFile(
            didSetLaunchAtLogin: config.didSetLaunchAtLogin,
            snapshots: Self.snapshots(of: config)
        )
        do {
            try writeIfChanged(try Self.encoder.encode(state), to: stateURL)
        } catch {
            restoreConfig(previousConfig)
            throw error
        }
        setLastKnownConfigData(configData)
    }

    /// config.json belongs to the user. A file that changed under us is a copy or an edit we must keep.
    /// A store that never read the file writes freely; the first save owns it.
    private func refuseWhenConfigChangedOnDisk(_ previousConfig: Data?) throws {
        knownConfigLock.lock()
        defer { knownConfigLock.unlock() }
        guard let lastKnownConfigData, let previousConfig, previousConfig != lastKnownConfigData else { return }
        throw StoreError.changedOnDisk
    }

    private func setLastKnownConfigData(_ data: Data?) {
        knownConfigLock.lock()
        defer { knownConfigLock.unlock() }
        lastKnownConfigData = data
    }

    /// state.json is our cache; a directory in its place is junk we can clear.
    /// Best effort: a directory that stays fails the write below, which rolls the save back.
    private func clearDirectoryAtStatePath() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: stateURL.path)
        guard attributes?[.type] as? FileAttributeType == .typeDirectory else { return }
        try? FileManager.default.removeItem(at: stateURL)
    }

    /// A settings change must not stay on disk when the cache write fails; the app keeps its old
    /// in-memory state. Best effort: the original error is the one the caller sees.
    private func restoreConfig(_ previous: Data?) {
        guard let previous else {
            try? FileManager.default.removeItem(at: configURL)
            return
        }
        try? previous.write(to: configURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private static func snapshots(of config: AppConfig) -> [String: PageState] {
        var result: [String: PageState] = [:]
        for page in config.pages {
            guard let snapshot = page.snapshot else { continue }
            result[page.id.uuidString] = PageState(url: page.url, snapshot: snapshot)
        }
        return result
    }

    private func writeIfChanged(_ data: Data, to url: URL) throws {
        if (try? Data(contentsOf: url)) != data {
            try data.write(to: url, options: .atomic)
        }
        // Always. A file copied in from another machine can have identical bytes and a wider mode.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func validate(_ config: AppConfig) throws {
        guard config.version <= AppConfig.currentVersion else { throw StoreError.corrupt }
        let pageIDs = config.pages.map(\.id)
        guard Set(pageIDs).count == pageIDs.count else { throw StoreError.corrupt }
    }

    private func mergingManagedConfig(_ local: AppConfig) throws -> AppConfig {
        let localPages = local.pages.map { page -> WatchedPage in
            var page = page
            page.required = nil
            return page
        }
        var result = local
        result.pages = localPages
        guard FileManager.default.fileExists(atPath: managedConfigURL.path) else {
            setManagedPageIDs(from: [])
            return result
        }
        let managedPages = try readManagedPages()
        setManagedPageIDs(from: managedPages)
        let (requiredIDs, optionalIDs) = managedPageIDs()
        result.pages = managedPages.filter {
            $0.required == true || !local.disabledManagedPageIDs.contains($0.id)
        }
        result.disabledManagedPages = managedPages.filter {
            $0.required == false && local.disabledManagedPageIDs.contains($0.id)
        }
        result.pages.append(contentsOf: localPages.filter {
            !requiredIDs.contains($0.id) && !optionalIDs.contains($0.id)
        })
        return result
    }

    private func readManagedPages() throws -> [WatchedPage] {
        guard FileManager.default.fileExists(atPath: managedConfigURL.path) else { return [] }
        let data: Data
        do { data = try Data(contentsOf: managedConfigURL) } catch { throw StoreError.corrupt }
        let managed: AppConfig
        do {
            managed = try JSONDecoder().decode(AppConfig.self, from: data)
        } catch { throw StoreError.corrupt }
        guard managed.version <= AppConfig.currentVersion else { throw StoreError.corrupt }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StoreError.corrupt
        }
        let rawPages = root["pages"] as? [[String: Any]] ?? []
        guard rawPages.count == managed.pages.count else { throw StoreError.corrupt }
        let explicitIDs = rawPages.compactMap { rawPage -> UUID? in
            guard let rawID = rawPage["id"] as? String else { return nil }
            return UUID(uuidString: rawID)
        }
        guard Set(explicitIDs).count == explicitIDs.count else { throw StoreError.corrupt }
        var usedIDs = Set(explicitIDs)
        var occurrences: [String: Int] = [:]
        return managed.pages.enumerated().map { index, page in
            let rawID = rawPages[index]["id"] as? String
            guard rawID.flatMap(UUID.init(uuidString:)) == nil else {
                var page = page
                page.required = page.required != false
                return page
            }
            let identity = "\(page.url.absoluteString)\u{0}\(page.name)"
            let occurrence = occurrences[identity, default: 0]
            occurrences[identity] = occurrence + 1
            var candidate = Self.stableManagedPageID("\(identity)\u{0}\(occurrence)")
            while !usedIDs.insert(candidate).inserted {
                candidate = Self.stableManagedPageID("\(identity)\u{0}\(occurrence)\u{0}\(candidate.uuidString)")
            }
            var page = page
            page.id = candidate
            page.required = page.required != false
            return page
        }
    }

    private static func stableManagedPageID(_ identity: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(identity.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let uuid: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }

    private func setManagedPageIDs(from pages: [WatchedPage]) {
        let ids = Self.managedPageIDs(from: pages)
        knownConfigLock.lock()
        defer { knownConfigLock.unlock() }
        managedRequiredIDs = ids.required
        managedOptionalIDs = ids.optional
        didLoadManagedConfig = true
    }

    private func managedConfigWasLoaded() -> Bool {
        knownConfigLock.lock()
        defer { knownConfigLock.unlock() }
        return didLoadManagedConfig
    }

    private static func managedPageIDs(from pages: [WatchedPage]) -> (required: Set<UUID>, optional: Set<UUID>) {
        (
            Set(pages.filter { $0.required == true }.map(\.id)),
            Set(pages.filter { $0.required == false }.map(\.id))
        )
    }

    private func managedPageIDs() -> (required: Set<UUID>, optional: Set<UUID>) {
        knownConfigLock.lock()
        defer { knownConfigLock.unlock() }
        return (managedRequiredIDs, managedOptionalIDs)
    }
}
