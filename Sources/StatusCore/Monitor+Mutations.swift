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

    /// Drops the results of polls that are already in flight. Reload uses this after a failed load.
    public func discardInFlightPolls() {
        withStateLock { latestPollIdentity &+= 1 }
    }

    /// Writes the current config. Reveal Config File uses this when no file exists yet.
    public func saveCurrentConfig() throws {
        try commitWatchedPageMutation { _ in }
    }

    public func enableLaunchAtLoginOnFirstRun() {
        let didChange: Bool = {
            transitionLock.lock()
            defer { transitionLock.unlock() }
            guard !withStateLock({ config.didSetLaunchAtLogin }) else { return false }
            do {
                try commitWatchedPageMutationLocked { $0.didSetLaunchAtLogin = true }
                return true
            } catch {
                return false
            }
        }()
        if didChange { onLaunchAtLoginEnable?() }
    }

    public func add(url: URL, name: String?, token: String? = nil) async throws {
        try Task.checkCancellation()
        let savedToken = trimmed(token)
        let snapshot = try await ProviderProbe.probe(pageURL: url, token: savedToken, client: client)
        try Task.checkCancellation()
        let page = WatchedPage(
            url: ProviderProbe.persistedPageURL(url),
            name: trimmed(name) ?? snapshot.name,
            notificationsEnabled: true,
            token: savedToken,
            snapshot: snapshot
        )
        try commitWatchedPageMutation {
            $0.pages.append(page)
            try Task.checkCancellation()
        }
    }

    public func edit(
        id: UUID,
        url: URL,
        name: String?,
        disabledComponentNames: Set<String>? = nil,
        enabledRegions: [String]? = nil
    ) async throws {
        let previous = withStateLock { config.pages.first { $0.id == id } }
        let token = previous.flatMap { RedirectPolicy.allows(url, from: $0.url) ? $0.token : nil }
        try await edit(
            id: id, url: url, name: name,
            disabledComponentNames: disabledComponentNames,
            enabledRegions: enabledRegions, token: token
        )
    }

    public func edit(
        id: UUID,
        url: URL,
        name: String?,
        disabledComponentNames: Set<String>? = nil,
        enabledRegions: [String]? = nil,
        token: String?
    ) async throws {
        try Task.checkCancellation()
        guard let previous = withStateLock({ config.pages.first { $0.id == id } }) else {
            throw MonitorError.pageNotFound(id)
        }
        let savedToken = trimmed(token)
        if savedToken != nil, savedToken == previous.token,
           !RedirectPolicy.allows(url, from: previous.url) {
            throw MonitorError.tokenRequiresReentry
        }
        let snapshot = try await ProviderProbe.probe(pageURL: url, token: savedToken, client: client)
        try Task.checkCancellation()
        try commitWatchedPageMutation(invalidatingBodyFor: id) { next in
            guard let index = next.pages.firstIndex(where: { $0.id == id }) else {
                throw MonitorError.pageNotFound(id)
            }
            next.pages[index].url = ProviderProbe.persistedPageURL(url)
            next.pages[index].name = trimmed(name) ?? snapshot.name
            next.pages[index].snapshot = snapshot
            next.pages[index].token = savedToken
            if let disabledComponentNames {
                next.pages[index].disabledComponentNames = disabledComponentNames
            }
            if let enabledRegions {
                next.pages[index].enabledRegions = enabledRegions
            }
            try Task.checkCancellation()
        }
    }

    public func remove(id: UUID) throws {
        try commitWatchedPageMutation(invalidatingBodyFor: id) { next in
            guard let index = next.pages.firstIndex(where: { $0.id == id }) else {
                throw MonitorError.pageNotFound(id)
            }
            let removed = next.pages.remove(at: index)
            if removed.required == false {
                next.disabledManagedPageIDs.insert(id)
                next.disabledManagedPages.append(removed)
            }
        }
    }

    public func enableManagedPage(id: UUID) throws {
        try commitWatchedPageMutation { next in
            guard let index = next.disabledManagedPages.firstIndex(where: { $0.id == id }) else {
                throw MonitorError.pageNotFound(id)
            }
            next.pages.append(next.disabledManagedPages.remove(at: index))
            next.disabledManagedPageIDs.remove(id)
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
            let persistKeys = nodes.isEmpty ? [name] : nodes.map(\.id)
            let allOn = nodes.isEmpty
                ? !next.pages[index].disabledComponentNames.contains(name)
                : nodes.allSatisfy { next.pages[index].isComponentEnabled($0) }
            if allOn {
                next.pages[index].disabledComponentNames.formUnion(persistKeys)
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

        try commitWatchedPageMutationLocked(invalidatingBodyFor: pageID, body)
    }

    private func commitWatchedPageMutationLocked(
        invalidatingBodyFor pageID: UUID? = nil,
        _ body: (inout AppConfig) throws -> Void
    ) throws {
        var next = withStateLock { config }
        try body(&next)
        let adoptedDisk: Bool
        do {
            try store.save(next)
            adoptedDisk = false
        } catch StoreError.changedOnDisk {
            // The file on disk is newer. Remember it before applying the edit, so a failed
            // edit cannot write the old pages back over that file.
            let loaded = try store.load()
            withStateLock {
                config = loaded
                lastBodies.removeAll()
            }
            next = loaded
            try body(&next)
            try store.save(next)
            adoptedDisk = true
        }
        let nextPageIDs = Set(next.pages.map(\.id))
        withStateLock {
            config = next
            if adoptedDisk { lastBodies.removeAll() }
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
