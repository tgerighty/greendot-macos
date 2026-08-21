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
        config.pages.append(page)
        try store.save(config)
    }

    public func edit(id: UUID, url: URL, name: String?) async throws {
        guard let index = config.pages.firstIndex(where: { $0.id == id }) else { return }
        let snapshot = try await ProviderProbe.probe(pageURL: url, client: client)
        config.pages[index].url = ProviderProbe.normalizedBase(url)
        config.pages[index].name = trimmed(name) ?? snapshot.name
        config.pages[index].snapshot = snapshot
        try store.save(config)
    }

    public func remove(id: UUID) throws {
        config.pages.removeAll { $0.id == id }
        try store.save(config)
    }

    public func toggleNotifications(id: UUID) throws {
        guard let index = config.pages.firstIndex(where: { $0.id == id }) else { return }
        config.pages[index].notificationsEnabled.toggle()
        try store.save(config)
    }

    public func toggleComponent(id: UUID, name: String) throws {
        guard let index = config.pages.firstIndex(where: { $0.id == id }) else { return }
        let tree = config.pages[index].snapshot?.components ?? []
        let node = ComponentTree.find(name, in: tree)
        let nodes = node.map(ComponentTree.collect) ?? []
        let keys = nodes.isEmpty ? [name] : nodes.flatMap { [$0.id, $0.name] }
        let allOn = nodes.isEmpty
            ? !config.pages[index].disabledComponentNames.contains(name)
            : nodes.allSatisfy { config.pages[index].isComponentEnabled($0) }
        if allOn {
            config.pages[index].disabledComponentNames.formUnion(keys)
        } else {
            keys.forEach { config.pages[index].disabledComponentNames.remove($0) }
        }
        try store.save(config)
    }

    public func setAllComponents(id: UUID, enabled: Bool) throws {
        guard let index = config.pages.firstIndex(where: { $0.id == id }) else { return }
        if enabled {
            config.pages[index].disabledComponentNames.removeAll()
        } else {
            config.pages[index].disabledComponentNames = Set(
                ComponentTree.componentKeys(config.pages[index].snapshot?.components ?? [])
            )
        }
        try store.save(config)
    }

    public func pollAll() async -> [Toast] {
        var toasts: [Toast] = []
        for index in config.pages.indices {
            let page = config.pages[index]
            let previous = page.snapshot
            let previousDisplay = page.displaySeverity
            let snapshot: PageSnapshot
            do {
                snapshot = try await ProviderProbe.probe(pageURL: page.url, client: client)
            } catch {
                snapshot = PageSnapshot(
                    name: page.name,
                    url: page.url,
                    provider: previous?.provider ?? .statuspage,
                    overall: .grey,
                    components: previous?.components ?? [],
                    incidents: [],
                    isUnreachable: true
                )
            }
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
