import Foundation

public final class Monitor: @unchecked Sendable {

    let store: PageStore
    let client: HTTPClient
    let stateLock = NSLock()
    let transitionLock: any NSLocking
    var config: AppConfig
    var lastBodies: [UUID: Data] = [:]
    var pageInputRevisions: [UUID: UInt64] = [:]
    var latestPollIdentity: UInt64 = 0
    public var onLaunchAtLoginEnable: (() -> Void)?

    public convenience init(store: PageStore, client: HTTPClient) {
        self.init(store: store, client: client, transitionLock: NSLock())
    }

    init(store: PageStore, client: HTTPClient, transitionLock: any NSLocking) {
        self.store = store
        self.client = client
        self.transitionLock = transitionLock
        self.config = AppConfig()
    }

    public var pages: [WatchedPage] {
        withStateLock { config.pages }
    }
}
