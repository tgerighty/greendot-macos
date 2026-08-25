import Foundation

private struct WatchedPagePollResult: Sendable {
    let pageID: UUID
    let snapshot: PageSnapshot
    let body: Data?
}

private struct WatchedPagePollStart {
    let pages: [WatchedPage]
    let bodies: [UUID: Data]
    let inputRevisions: [UUID: UInt64]
    let identity: UInt64
}

private struct WatchedPagePollMerge {
    let config: AppConfig
    let acceptedIDs: Set<UUID>
    let toasts: [Toast]
}

public final class Monitor: @unchecked Sendable {

    private let store: PageStore
    private let client: HTTPClient
    private let stateLock = NSLock()
    private let transitionLock: any NSLocking
    private var config: AppConfig
    private var lastBodies: [UUID: Data] = [:]
    private var pageInputRevisions: [UUID: UInt64] = [:]
    private var latestPollIdentity: UInt64 = 0
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

    public func load() throws {
        transitionLock.lock()
        defer { transitionLock.unlock() }

        let loaded = try store.load()
        withStateLock {
            config = loaded
            lastBodies.removeAll()
            pageInputRevisions = Dictionary(uniqueKeysWithValues: loaded.pages.map { ($0.id, 0) })
            latestPollIdentity &+= 1
        }
    }

    public func enableLaunchAtLoginOnFirstRun() {
        let already = withStateLock { config.didSetLaunchAtLogin }
        guard !already else { return }
        do {
            try commitWatchedPageMutation { $0.didSetLaunchAtLogin = true }
        } catch {
            return
        }
        onLaunchAtLoginEnable?()
    }

    public func add(url: URL, name: String?) async throws {
        try Task.checkCancellation()
        let snapshot = try await ProviderProbe.probe(pageURL: url, client: client)
        try Task.checkCancellation()
        let page = WatchedPage(
            url: ProviderProbe.normalizedBase(url),
            name: trimmed(name) ?? snapshot.name,
            notificationsEnabled: true,
            snapshot: snapshot
        )
        try commitWatchedPageMutation {
            $0.pages.append(page)
            try Task.checkCancellation()
        }
    }

    public func edit(id: UUID, url: URL, name: String?) async throws {
        try Task.checkCancellation()
        guard withStateLock({ config.pages.contains { $0.id == id } }) else {
            throw MonitorError.pageNotFound(id)
        }
        let snapshot = try await ProviderProbe.probe(pageURL: url, client: client)
        try Task.checkCancellation()
        try commitWatchedPageMutation(invalidatingBodyFor: id) { next in
            guard let index = next.pages.firstIndex(where: { $0.id == id }) else {
                throw MonitorError.pageNotFound(id)
            }
            next.pages[index].url = ProviderProbe.normalizedBase(url)
            next.pages[index].name = trimmed(name) ?? snapshot.name
            next.pages[index].snapshot = snapshot
            try Task.checkCancellation()
        }
    }

    public func remove(id: UUID) throws {
        try commitWatchedPageMutation(invalidatingBodyFor: id) { next in
            guard let index = next.pages.firstIndex(where: { $0.id == id }) else {
                throw MonitorError.pageNotFound(id)
            }
            next.pages.remove(at: index)
        }
    }

    public func toggleNotifications(id: UUID) throws {
        try commitWatchedPageMutation { next in
            guard let index = next.pages.firstIndex(where: { $0.id == id }) else {
                throw MonitorError.pageNotFound(id)
            }
            next.pages[index].notificationsEnabled.toggle()
        }
    }

    public func toggleComponent(id: UUID, name: String) throws {
        try commitWatchedPageMutation { next in
            guard let index = next.pages.firstIndex(where: { $0.id == id }) else {
                throw MonitorError.pageNotFound(id)
            }
            let tree = next.pages[index].snapshot?.components ?? []
            let node = ComponentTree.find(name, in: tree)
            let nodes = node.map(ComponentTree.collect) ?? []
            let keys = nodes.isEmpty ? [name] : nodes.flatMap { [$0.id, $0.name] }
            let allOn = nodes.isEmpty
                ? !next.pages[index].disabledComponentNames.contains(name)
                : nodes.allSatisfy { next.pages[index].isComponentEnabled($0) }
            if allOn {
                next.pages[index].disabledComponentNames.formUnion(keys)
            } else {
                keys.forEach { next.pages[index].disabledComponentNames.remove($0) }
            }
        }
    }

    public func setAllComponents(id: UUID, enabled: Bool) throws {
        try commitWatchedPageMutation { next in
            guard let index = next.pages.firstIndex(where: { $0.id == id }) else {
                throw MonitorError.pageNotFound(id)
            }
            if enabled {
                next.pages[index].disabledComponentNames.removeAll()
            } else {
                next.pages[index].disabledComponentNames = Set(
                    ComponentTree.componentKeys(next.pages[index].snapshot?.components ?? [])
                )
            }
        }
    }

    public func pollAll() async throws -> [Toast] {
        try Task.checkCancellation()
        let pollStart = startPoll()
        let pages = pollStart.pages
        let bodies = pollStart.bodies
        let pollIdentity = pollStart.identity
        let pollResults: [UUID: WatchedPagePollResult] = try await withThrowingTaskGroup(
            of: WatchedPagePollResult.self
        ) { group in
            for page in pages {
                let client = self.client
                let previousBody = bodies[page.id]
                group.addTask {
                    try await self.pollResult(for: page, client: client, previousBody: previousBody)
                }
            }
            var collected: [UUID: WatchedPagePollResult] = [:]
            for try await result in group {
                collected[result.pageID] = result
            }
            return collected
        }

        try Task.checkCancellation()
        return try applyPollResults(
            pollResults, for: pollIdentity, expectedPages: pages, expectedInputRevisions: pollStart.inputRevisions
        )
    }

    public func barSeverity() -> Severity {
        withStateLock { Aggregator.fromSeverities(config.pages.map(\.displaySeverity)) }
    }

    public func displayedSeverity(at now: Date) -> Severity {
        let persistent: Severity
        let hasUnreachable: Bool
        (persistent, hasUnreachable) = withStateLock {
            (
                Aggregator.fromSeverities(config.pages.map(\.displaySeverity)),
                config.pages.contains { $0.snapshot?.isUnreachable == true }
            )
        }
        return GreyPulse.displayedSeverity(persistent: persistent, hasUnreachable: hasUnreachable, now: now)
    }

}

private extension Monitor {
    func pollResult(
        for page: WatchedPage,
        client: HTTPClient,
        previousBody: Data?
    ) async throws -> WatchedPagePollResult {
        do {
            let hit = try await ProviderProbe.probeHit(
                pageURL: page.url,
                client: client,
                prefer: page.snapshot?.provider,
                previousBody: previousBody,
                previousSnapshot: page.snapshot
            )
            return WatchedPagePollResult(
                pageID: page.id,
                snapshot: hit.snapshot,
                body: hit.body
            )
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            let snapshot = PageSnapshot(
                name: page.name,
                url: page.url,
                provider: page.snapshot?.provider ?? .statuspage,
                overall: .grey,
                components: page.snapshot?.components ?? [],
                incidents: [],
                isUnreachable: true
            )
            return WatchedPagePollResult(
                pageID: page.id,
                snapshot: snapshot,
                body: nil
            )
        }
    }

    func startPoll() -> WatchedPagePollStart {
        transitionLock.lock()
        defer { transitionLock.unlock() }

        return withStateLock {
            latestPollIdentity &+= 1
            return WatchedPagePollStart(
                pages: config.pages,
                bodies: lastBodies,
                inputRevisions: pageInputRevisions,
                identity: latestPollIdentity
            )
        }
    }

    func commitWatchedPageMutation(
        invalidatingBodyFor pageID: UUID? = nil,
        _ body: (inout AppConfig) throws -> Void
    ) throws {
        transitionLock.lock()
        defer { transitionLock.unlock() }

        var next = withStateLock { config }
        try body(&next)
        try store.save(next)
        let nextPageIDs = Set(next.pages.map(\.id))
        withStateLock {
            config = next
            pageInputRevisions = pageInputRevisions.filter { nextPageIDs.contains($0.key) }
            for pageID in nextPageIDs where pageInputRevisions[pageID] == nil {
                pageInputRevisions[pageID] = 0
            }
            if let pageID {
                lastBodies[pageID] = nil
                if nextPageIDs.contains(pageID) {
                    pageInputRevisions[pageID, default: 0] &+= 1
                }
            }
        }
    }

    func applyPollResults(
        _ pollResults: [UUID: WatchedPagePollResult],
        for pollIdentity: UInt64,
        expectedPages: [WatchedPage],
        expectedInputRevisions: [UUID: UInt64]
    ) throws -> [Toast] {
        transitionLock.lock()
        defer { transitionLock.unlock() }
        try Task.checkCancellation()

        let (currentConfig, currentPollIdentity, currentInputRevisions) = withStateLock {
            (config, latestPollIdentity, pageInputRevisions)
        }
        guard pollIdentity == currentPollIdentity else { return [] }

        guard let merge = mergePollResults(
            currentConfig: currentConfig,
            pollResults: pollResults,
            expectedPages: expectedPages,
            expectedInputRevisions: expectedInputRevisions,
            currentInputRevisions: currentInputRevisions
        ) else { return [] }
        if merge.config != currentConfig {
            try store.save(merge.config)
        }
        withStateLock {
            for id in merge.acceptedIDs {
                if let body = pollResults[id]?.body {
                    lastBodies[id] = body
                }
            }
            config = merge.config
        }
        return merge.toasts
    }

    func mergePollResults(
        currentConfig: AppConfig,
        pollResults: [UUID: WatchedPagePollResult],
        expectedPages: [WatchedPage],
        expectedInputRevisions: [UUID: UInt64],
        currentInputRevisions: [UUID: UInt64]
    ) -> WatchedPagePollMerge? {
        guard let expectedByID = expectedPagesByID(expectedPages) else { return nil }
        var next = currentConfig
        var acceptedIDs: Set<UUID> = []
        var toasts: [Toast] = []
        for index in next.pages.indices {
            let id = next.pages[index].id
            guard expectedByID[id] != nil,
                  let expectedInputRevision = expectedInputRevisions[id],
                  currentInputRevisions[id] == expectedInputRevision,
                  let result = pollResults[id] else { continue }
            acceptedIDs.insert(id)
            let page = next.pages[index]
            let previous = page.snapshot
            let previousDisplay = page.displaySeverity
            next.pages[index].snapshot = result.snapshot
            if let toast = pollToast(
                from: previous,
                to: result.snapshot,
                currentPage: next.pages[index],
                previousDisplay: previousDisplay
            ) {
                toasts.append(toast)
            }
        }
        return WatchedPagePollMerge(config: next, acceptedIDs: acceptedIDs, toasts: toasts)
    }

    func pollToast(
        from previous: PageSnapshot?,
        to current: PageSnapshot,
        currentPage: WatchedPage,
        previousDisplay: Severity
    ) -> Toast? {
        guard let previous,
              previousDisplay != currentPage.displaySeverity else { return nil }
        return ToastPolicy.toast(
            previous: {
                var copy = previous
                copy.overall = previousDisplay
                return copy
            }(),
            current: {
                var copy = current
                copy.overall = currentPage.displaySeverity
                copy.isUnreachable = current.isUnreachable
                return copy
            }(),
            notificationsEnabled: currentPage.notificationsEnabled,
            pageName: currentPage.name
        )
    }

    func expectedPagesByID(_ pages: [WatchedPage]) -> [UUID: WatchedPage]? {
        var pagesByID: [UUID: WatchedPage] = [:]
        for page in pages {
            guard pagesByID[page.id] == nil else { return nil }
            pagesByID[page.id] = page
        }
        return pagesByID
    }

    func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    func trimmed(_ name: String?) -> String? {
        guard let name else { return nil }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
