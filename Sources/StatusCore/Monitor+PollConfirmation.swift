import Foundation

extension Monitor {
    /// A mixed poll can mean the network dropped while requests were still in flight. One extra
    /// probe of a page that just answered tells those two cases apart. If that probe now fails,
    /// treat the whole poll as a network outage so the pages collapse to one lost toast.
    func confirmedPollResults(
        _ pollResults: [UUID: WatchedPagePollResult],
        pages: [WatchedPage]
    ) async throws -> [UUID: WatchedPagePollResult] {
        try Task.checkCancellation()
        guard shouldConfirmPoll(pollResults, pages: pages),
              let page = pages.first(where: { pollResults[$0.id]?.snapshot.isUnreachable == false }),
              let result = pollResults[page.id] else {
            return pollResults
        }
        guard try await confirmationStillReachable(page, result: result) else {
            return unreachablePollResults(for: pages)
        }
        return pollResults
    }

    private func shouldConfirmPoll(
        _ pollResults: [UUID: WatchedPagePollResult],
        pages: [WatchedPage]
    ) -> Bool {
        guard pages.count > 1 else { return false }
        var reachable = false
        var unreachable = false
        var freshlyUnreachable = false
        for page in pages {
            guard let snapshot = pollResults[page.id]?.snapshot else { continue }
            if snapshot.isUnreachable {
                unreachable = true
                if page.snapshot?.isUnreachable != true {
                    freshlyUnreachable = true
                }
            } else {
                reachable = true
            }
        }
        return reachable && unreachable && freshlyUnreachable
    }

    private func confirmationStillReachable(
        _ page: WatchedPage,
        result: WatchedPagePollResult
    ) async throws -> Bool {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                try await self.probeConfirmation(page, result: result)
            }
            group.addTask {
                // Giving up keeps the mixed results. A slow probe must not invent an outage.
                try await Task.sleep(nanoseconds: UInt64(self.confirmationTimeout * 1_000_000_000))
                return true
            }
            let reached = try await group.next() ?? true
            group.cancelAll()
            while await group.nextResult() != nil {
                if Task.isCancelled { throw CancellationError() }
            }
            return reached
        }
    }

    private func probeConfirmation(
        _ page: WatchedPage,
        result: WatchedPagePollResult
    ) async throws -> Bool {
        do {
            _ = try await ProviderProbe.probeHit(
                pageURL: page.url,
                client: client,
                prefer: result.snapshot.provider,
                previousBody: result.body,
                previousSnapshot: result.snapshot
            )
            return true
        } catch {
            try ProviderProbe.throwIfCancelled(error)
            // Anything other than a network failure is not evidence the link dropped.
            return (error as? ProbeError) != .unreachable
        }
    }
}
