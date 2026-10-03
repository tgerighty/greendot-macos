import Foundation

public struct AppConfig: Equatable, Sendable {
    public static let currentVersion = 2
    public static let defaultPollSeconds: TimeInterval = 60
    public var version: Int
    public var pollSeconds: TimeInterval
    public var pages: [WatchedPage]
    public var didSetLaunchAtLogin: Bool
    /// IDs of optional managed pages switched off by this user.
    public var disabledManagedPageIDs: Set<UUID>
    public var disabledManagedPages: [WatchedPage]
    /// Machine-local. `PageStore` keeps it in `state.json` and omits it from `config.json`.
    public var interfaceStyle: InterfaceStyle

    public init(
        version: Int = currentVersion,
        pollSeconds: TimeInterval = defaultPollSeconds,
        pages: [WatchedPage] = [],
        didSetLaunchAtLogin: Bool = false,
        disabledManagedPageIDs: Set<UUID> = [],
        disabledManagedPages: [WatchedPage] = [],
        interfaceStyle: InterfaceStyle = .system
    ) {
        self.version = version
        self.pollSeconds = pollSeconds
        self.pages = pages
        self.didSetLaunchAtLogin = didSetLaunchAtLogin
        self.disabledManagedPageIDs = disabledManagedPageIDs
        self.disabledManagedPages = disabledManagedPages
        self.interfaceStyle = interfaceStyle
    }

    /// Missing, non-finite, or zero and below becomes the default.
    public static func validPollSeconds(_ value: TimeInterval?) -> TimeInterval {
        guard let value, value.isFinite, value > 0 else { return defaultPollSeconds }
        return value
    }
}

public enum StoreError: Error, Equatable, LocalizedError {
    case corrupt
    case changedOnDisk
    case requiredManagedPage

    public var errorDescription: String? {
        switch self {
        case .corrupt:
            return "The saved status list could not be read."
        case .changedOnDisk:
            return "config.json changed on disk."
        case .requiredManagedPage:
            return "A required managed status page cannot be removed."
        }
    }
}
