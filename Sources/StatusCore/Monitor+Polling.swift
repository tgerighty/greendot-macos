import Foundation

extension Monitor {
    public func pollAll() async throws -> [Toast] {
        try Task.checkCancellation()
        let pollStart = startPoll()
        let pollResults: [UUID: WatchedPagePollResult]
        if pollStart.systemOffline {
            // HTTP cannot succeed without a route. Mark every page unreachable here so the lost
            // toast can fire on this poll, including when only one page is watched.
            pollResults = unreachablePollResults(for: pollStart.pages)
        } else {
            pollResults = try await fetchPollResults(pages: pollStart.pages, bodies: pollStart.bodies)
        }
        try Task.checkCancellation()
        return try applyPollResults(pollResults, start: pollStart)
    }

    private func fetchPollResults(
        pages: [WatchedPage],
        bodies: [UUID: Data]
    ) async throws -> [UUID: WatchedPagePollResult] {
        try await withThrowingTaskGroup(of: WatchedPagePollResult.self) { group in
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
    }

    private func unreachablePollResults(for pages: [WatchedPage]) -> [UUID: WatchedPagePollResult] {
        var collected: [UUID: WatchedPagePollResult] = [:]
        for page in pages {
            collected[page.id] = WatchedPagePollResult(
                pageID: page.id,
                snapshot: unreachableSnapshot(for: page),
                body: nil
            )
        }
        return collected
    }

    /// A failed probe and a system-offline poll must produce the same snapshot, so the merge path stays one.
    private func unreachableSnapshot(for page: WatchedPage) -> PageSnapshot {
        PageSnapshot(
            name: page.name,
            url: page.url,
            provider: page.snapshot?.provider ?? .statuspage,
            overall: .grey,
            components: page.snapshot?.components ?? [],
            incidents: [],
            isUnreachable: true
        )
    }

    private func pollResult(
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
            return WatchedPagePollResult(
                pageID: page.id,
                snapshot: unreachableSnapshot(for: page),
                body: nil
            )
        }
    }

    private func startPoll() -> WatchedPagePollStart {
        transitionLock.lock()
        defer { transitionLock.unlock() }

        return withStateLock {
            latestPollIdentity &+= 1
            return WatchedPagePollStart(
                pages: config.pages,
                bodies: lastBodies,
                inputRevisions: pageInputRevisions,
                identity: latestPollIdentity,
                systemOffline: reachability?.isOnline == false
            )
        }
    }

    private func applyPollResults(
        _ pollResults: [UUID: WatchedPagePollResult],
        start: WatchedPagePollStart
    ) throws -> [Toast] {
        transitionLock.lock()
        defer { transitionLock.unlock() }
        try Task.checkCancellation()

        let (currentConfig, currentPollIdentity, currentInputRevisions) = withStateLock {
            (config, latestPollIdentity, pageInputRevisions)
        }
        guard start.identity == currentPollIdentity else { return [] }

        guard let merge = mergePollResults(
            currentConfig: currentConfig,
            pollResults: pollResults,
            start: start,
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
            networkLossFlag = merge.showingNetworkLoss
        }
        return merge.toasts
    }

    private func mergePollResults(
        currentConfig: AppConfig,
        pollResults: [UUID: WatchedPagePollResult],
        start: WatchedPagePollStart,
        currentInputRevisions: [UUID: UInt64]
    ) -> WatchedPagePollMerge? {
        guard let expectedByID = expectedPagesByID(start.pages) else { return nil }
        var next = currentConfig
        var acceptedIDs: Set<UUID> = []
        var toasts: [Toast] = []
        for index in next.pages.indices {
            let id = next.pages[index].id
            guard expectedByID[id] != nil,
                  let expectedInputRevision = start.inputRevisions[id],
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
        var showingLost = withStateLock { networkLossFlag }
        let merged = NetworkToast.apply(
            toasts, pages: next.pages, showingLost: &showingLost, systemOffline: start.systemOffline
        )
        return WatchedPagePollMerge(
            config: next,
            acceptedIDs: acceptedIDs,
            toasts: merged,
            showingNetworkLoss: showingLost
        )
    }

    private func pollToast(
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
            pageName: currentPage.name,
            pageID: currentPage.id
        )
    }

    private func expectedPagesByID(_ pages: [WatchedPage]) -> [UUID: WatchedPage]? {
        var pagesByID: [UUID: WatchedPage] = [:]
        for page in pages {
            guard pagesByID[page.id] == nil else { return nil }
            pagesByID[page.id] = page
        }
        return pagesByID
    }
}
