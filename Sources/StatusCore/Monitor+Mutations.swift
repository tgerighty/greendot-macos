import Foundation

extension Monitor {
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

    private func commitWatchedPageMutation(
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

    private func trimmed(_ name: String?) -> String? {
        guard let name else { return nil }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

extension Monitor {
    func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}
