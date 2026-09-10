import Foundation

struct WatchedPagePollResult: Sendable {
    let pageID: UUID
    let snapshot: PageSnapshot
    let body: Data?
}

struct WatchedPagePollStart {
    let pages: [WatchedPage]
    let bodies: [UUID: Data]
    let inputRevisions: [UUID: UInt64]
    let identity: UInt64
    /// Captured at the start of the poll so a path change mid-request cannot rewrite the merge.
    let systemOffline: Bool
}

struct WatchedPagePollMerge {
    let config: AppConfig
    let acceptedIDs: Set<UUID>
    let toasts: [Toast]
    let showingNetworkLoss: Bool
}
