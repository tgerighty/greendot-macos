import Foundation

public final class Monitor: @unchecked Sendable {

    let store: PageStore
    let client: HTTPClient
    let reachability: (any NetworkReachability)?
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
        reachability: (any NetworkReachability)? = nil
    ) {
        self.init(store: store, client: client, transitionLock: NSLock(), reachability: reachability)
    }

    init(
        store: PageStore,
        client: HTTPClient,
        transitionLock: any NSLocking,
        reachability: (any NetworkReachability)? = nil
    ) {
        self.store = store
        self.client = client
        self.transitionLock = transitionLock
        self.reachability = reachability
        self.config = AppConfig()
    }

    public var pages: [WatchedPage] {
        withStateLock { config.pages }
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
