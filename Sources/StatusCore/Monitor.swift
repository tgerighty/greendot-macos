import Foundation

public final class Monitor: @unchecked Sendable {
    private let store: PageStore
    private let client: HTTPClient
    private let lock = NSLock()
    private var config: AppConfig
    private var lastBodies: [UUID: Data] = [:]
    public var onLaunchAtLoginEnable: (() -> Void)?

    public init(store: PageStore, client: HTTPClient) {
        self.store = store
        self.client = client
        self.config = AppConfig()
    }

    public var pages: [WatchedPage] {
        withLock { config.pages }
    }

    public func load() throws {
        let loaded = try store.load()
        withLock {
            config = loaded
            lastBodies.removeAll()
        }
    }

    public func enableLaunchAtLoginOnFirstRun() {
        let already = withLock { config.didSetLaunchAtLogin }
        guard !already else { return }
        try? commit { $0.didSetLaunchAtLogin = true }
        onLaunchAtLoginEnable?()
    }

    public func add(url: URL, name: String?) async throws {
        let snapshot = try await ProviderProbe.probe(pageURL: url, client: client)
        let page = WatchedPage(
            url: ProviderProbe.normalizedBase(url),
            name: trimmed(name) ?? snapshot.name,
            notificationsEnabled: true,
            snapshot: snapshot
        )
        try commit { $0.pages.append(page) }
    }

    public func edit(id: UUID, url: URL, name: String?) async throws {
        let snapshot = try await ProviderProbe.probe(pageURL: url, client: client)
        withLock { lastBodies[id] = nil }
        try commit { next in
            guard let index = next.pages.firstIndex(where: { $0.id == id }) else { return }
            next.pages[index].url = ProviderProbe.normalizedBase(url)
            next.pages[index].name = trimmed(name) ?? snapshot.name
            next.pages[index].snapshot = snapshot
        }
    }

    public func remove(id: UUID) throws {
        withLock { lastBodies[id] = nil }
        try commit { $0.pages.removeAll { $0.id == id } }
    }

    public func toggleNotifications(id: UUID) throws {
        try commit { next in
            guard let index = next.pages.firstIndex(where: { $0.id == id }) else { return }
            next.pages[index].notificationsEnabled.toggle()
        }
    }

    public func toggleComponent(id: UUID, name: String) throws {
        try commit { next in
            guard let index = next.pages.firstIndex(where: { $0.id == id }) else { return }
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
        try commit { next in
            guard let index = next.pages.firstIndex(where: { $0.id == id }) else { return }
            if enabled {
                next.pages[index].disabledComponentNames.removeAll()
            } else {
                next.pages[index].disabledComponentNames = Set(
                    ComponentTree.componentKeys(next.pages[index].snapshot?.components ?? [])
                )
            }
        }
    }

    private func commit(_ body: (inout AppConfig) throws -> Void) throws {
        var next = withLock { config }
        try body(&next)
        try store.save(next)
        withLock { config = next }
    }

    public func pollAll() async -> [Toast] {
        let pages: [WatchedPage]
        let bodies: [UUID: Data]
        (pages, bodies) = withLock { (config.pages, lastBodies) }
        let hits: [UUID: (PageSnapshot, Data?)] = await withTaskGroup(of: (UUID, PageSnapshot, Data?).self) { group in
            for page in pages {
                let client = self.client
                let previousBody = bodies[page.id]
                group.addTask {
                    do {
                        let hit = try await ProviderProbe.probeHit(
                            pageURL: page.url,
                            client: client,
                            prefer: page.snapshot?.provider,
                            previousBody: previousBody,
                            previousSnapshot: page.snapshot
                        )
                        return (page.id, hit.snapshot, hit.body)
                    } catch {
                        let snapshot = PageSnapshot(
                            name: page.name,
                            url: page.url,
                            provider: page.snapshot?.provider ?? .statuspage,
                            overall: .grey,
                            components: page.snapshot?.components ?? [],
                            incidents: [],
                            isUnreachable: true
                        )
                        return (page.id, snapshot, nil)
                    }
                }
            }
            var collected: [UUID: (PageSnapshot, Data?)] = [:]
            for await (id, snapshot, body) in group {
                collected[id] = (snapshot, body)
            }
            return collected
        }

        let (changed, toSave, toasts): (Bool, AppConfig, [Toast]) = withLock {
            for (id, hit) in hits {
                if let body = hit.1 {
                    lastBodies[id] = body
                }
            }
            let beforeSave = config
            var toasts: [Toast] = []
            for index in config.pages.indices {
                let id = config.pages[index].id
                guard let snapshot = hits[id]?.0 else { continue }
                let page = config.pages[index]
                let previous = page.snapshot
                let previousDisplay = page.displaySeverity
                config.pages[index].snapshot = snapshot
                if previous != nil,
                   previousDisplay != config.pages[index].displaySeverity,
                   let toast = ToastPolicy.toast(
                    previous: previous.map { prev in
                        var copy = prev
                        copy.overall = previousDisplay
                        return copy
                    },
                    current: {
                        var copy = snapshot
                        copy.overall = config.pages[index].displaySeverity
                        copy.isUnreachable = snapshot.isUnreachable
                        return copy
                    }(),
                    notificationsEnabled: page.notificationsEnabled,
                    pageName: page.name
                   ) {
                    toasts.append(toast)
                }
            }
            return (config != beforeSave, config, toasts)
        }
        if changed {
            try? store.save(toSave)
        }
        return toasts
    }

    public func barSeverity() -> Severity {
        withLock { Aggregator.fromSeverities(config.pages.map(\.displaySeverity)) }
    }

    public func displayedSeverity(at now: Date) -> Severity {
        let persistent: Severity
        let hasUnreachable: Bool
        (persistent, hasUnreachable) = withLock {
            (
                Aggregator.fromSeverities(config.pages.map(\.displaySeverity)),
                config.pages.contains { $0.snapshot?.isUnreachable == true }
            )
        }
        return GreyPulse.displayedSeverity(persistent: persistent, hasUnreachable: hasUnreachable, now: now)
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func trimmed(_ name: String?) -> String? {
        guard let name else { return nil }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
