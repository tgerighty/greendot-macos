import Foundation

extension Monitor {
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

    private func startPoll() -> WatchedPagePollStart {
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

    private func applyPollResults(
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

    private func mergePollResults(
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
        return WatchedPagePollMerge(
            config: next,
            acceptedIDs: acceptedIDs,
            toasts: NetworkToast.apply(toasts, previous: currentConfig.pages, current: next.pages)
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
