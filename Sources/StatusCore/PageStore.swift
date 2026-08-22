import Foundation

public struct AppConfig: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var pages: [WatchedPage]
    public var didSetLaunchAtLogin: Bool

    public init(version: Int = currentVersion, pages: [WatchedPage] = [], didSetLaunchAtLogin: Bool = false) {
        self.version = version
        self.pages = pages
        self.didSetLaunchAtLogin = didSetLaunchAtLogin
    }
}

public enum StoreError: Error, Equatable, LocalizedError {
    case corrupt

    public var errorDescription: String? {
        switch self {
        case .corrupt:
            return "The saved status list could not be read."
        }
    }
}

public final class PageStore: @unchecked Sendable {
    public let configURL: URL
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
        self.configURL = directory.appendingPathComponent("config.json")
    }

    public static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["GREENDOT_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("greendot", isDirectory: true)
    }

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
        do {
            let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
            guard decoded.version <= AppConfig.currentVersion else { throw StoreError.corrupt }
            return decoded
        } catch {
            throw StoreError.corrupt
        }
    }

    public func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(config)
        try data.write(to: configURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }
}
