import Foundation

public final class Monitor: @unchecked Sendable {
    private let store: PageStore
    private let client: HTTPClient
    private var config: AppConfig
    public var onLaunchAtLoginEnable: (() -> Void)?

    public init(store: PageStore, client: HTTPClient) {
        self.store = store
        self.client = client
        self.config = AppConfig()
    }

    public var pages: [WatchedPage] { config.pages }

    public func load() throws {
        config = try store.load()
    }

    public func enableLaunchAtLoginOnFirstRun() {
        guard !config.didSetLaunchAtLogin else { return }
        config.didSetLaunchAtLogin = true
        try? store.save(config)
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
        try commit { next in
            guard let index = next.pages.firstIndex(where: { $0.id == id }) else { return }
            next.pages[index].url = ProviderProbe.normalizedBase(url)
            next.pages[index].name = trimmed(name) ?? snapshot.name
            next.pages[index].snapshot = snapshot
        }
    }

    public func remove(id: UUID) throws {
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
        var next = config
        try body(&next)
        try store.save(next)
        config = next
    }

    public func pollAll() async -> [Toast] {
        let pages = config.pages
        let snapshots: [PageSnapshot] = await withTaskGroup(of: (Int, PageSnapshot).self) { group in
            for (index, page) in pages.enumerated() {
                let client = self.client
                group.addTask {
                    let snapshot: PageSnapshot
                    do {
                        snapshot = try await ProviderProbe.probe(
                            pageURL: page.url,
                            client: client,
                            prefer: page.snapshot?.provider
                        )
                    } catch {
                        snapshot = PageSnapshot(
                            name: page.name,
                            url: page.url,
                            provider: page.snapshot?.provider ?? .statuspage,
                            overall: .grey,
                            components: page.snapshot?.components ?? [],
                            incidents: [],
                            isUnreachable: true
                        )
                    }
                    return (index, snapshot)
                }
            }
            var collected = [PageSnapshot?](repeating: nil, count: pages.count)
            for await (index, snapshot) in group {
                collected[index] = snapshot
            }
            return collected.map { $0! }
        }

        var toasts: [Toast] = []
        for index in pages.indices {
            let page = config.pages[index]
            let previous = page.snapshot
            let previousDisplay = page.displaySeverity
            let snapshot = snapshots[index]
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
        try? store.save(config)
        return toasts
    }

    public func barSeverity() -> Severity {
        Aggregator.fromSeverities(config.pages.map(\.displaySeverity))
    }

    public func displayedSeverity(at now: Date) -> Severity {
        let persistent = barSeverity()
        let hasUnreachable = config.pages.contains { $0.snapshot?.isUnreachable == true }
        return GreyPulse.displayedSeverity(persistent: persistent, hasUnreachable: hasUnreachable, now: now)
    }

    private func trimmed(_ name: String?) -> String? {
        guard let name else { return nil }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
