import Foundation

public final class Monitor: @unchecked Sendable {

    public static let defaultConfirmationTimeout: TimeInterval = 3
    /// The probe is an HTTP request. A longer wait than this holds up the poll for no gain.
    public static let maxConfirmationTimeout: TimeInterval = 60

    let store: PageStore
    let client: HTTPClient
    let reachability: (any NetworkReachability)?
    /// Caps a mixed-poll confirmation so a slow probe cannot stall the poll.
    let confirmationTimeout: TimeInterval
    let stateLock = NSLock()
    let transitionLock: any NSLocking
    var config: AppConfig
    var lastBodies: [UUID: Data] = [:]
    var pageInputRevisions: [UUID: UInt64] = [:]
    var latestPollIdentity: UInt64 = 0
    /// True while the lost network toast is on screen. Survives a config reload, so the toast can be cleared.
    var networkLossFlag = false

    /// The app clears a stale network toast when a poll lands and this is false.
    public var showingNetworkLoss: Bool {
        withStateLock { networkLossFlag }
    }
    /// The app polls at once when this changes, rather than waiting for the next timer tick.
    public var isSystemOnline: Bool { reachability?.isOnline ?? true }
    public var onLaunchAtLoginEnable: (() -> Void)?

    public convenience init(
        store: PageStore,
        client: HTTPClient,
        reachability: (any NetworkReachability)? = nil,
        confirmationTimeout: TimeInterval = defaultConfirmationTimeout
    ) {
        self.init(
            store: store,
            client: client,
            transitionLock: NSLock(),
            reachability: reachability,
            confirmationTimeout: confirmationTimeout
        )
    }

    init(
        store: PageStore,
        client: HTTPClient,
        transitionLock: any NSLocking,
        reachability: (any NetworkReachability)? = nil,
        confirmationTimeout: TimeInterval = defaultConfirmationTimeout
    ) {
        self.store = store
        self.client = client
        self.transitionLock = transitionLock
        self.reachability = reachability
        self.confirmationTimeout = Monitor.validConfirmationTimeout(confirmationTimeout)
        self.config = AppConfig()
    }

    /// The poll turns this timeout into nanoseconds, which traps on a negative, a NaN, or a value
    /// too large for UInt64. A caller can give any TimeInterval, so make it safe here.
    /// Non-finite or zero and below becomes the default. A larger value becomes the maximum.
    static func validConfirmationTimeout(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite, value > 0 else { return defaultConfirmationTimeout }
        return min(value, maxConfirmationTimeout)
    }

    public var pages: [WatchedPage] {
        withStateLock { config.pages }
    }

    public var disabledManagedPages: [WatchedPage] {
        withStateLock { config.disabledManagedPages }
    }

    public var pollSeconds: TimeInterval {
        withStateLock { config.pollSeconds }
    }

    func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}
