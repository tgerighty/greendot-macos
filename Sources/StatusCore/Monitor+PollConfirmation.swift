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

    /// The timeout is a hard cap. A task group waits for its children, so a client that ignores
    /// cancellation could hold the poll past the cap. The probe therefore runs outside the group
    /// and reports through a stream. The poll can drop it, because the probe only reads a page and
    /// returns a Bool. It changes no monitor state.
    private func confirmationStillReachable(
        _ page: WatchedPage,
        result: WatchedPagePollResult
    ) async throws -> Bool {
        let (answers, answer) = AsyncStream<Bool>.makeStream()
        let probe = Task {
            defer { answer.finish() }
            answer.yield(try await self.probeConfirmation(page, result: result))
        }
        defer { probe.cancel() }
        return try await firstAnswer(from: answers)
    }

    private func firstAnswer(from answers: AsyncStream<Bool>) async throws -> Bool {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                var results = answers.makeAsyncIterator()
                guard let reached = await results.next() else {
                    // No answer means the probe threw or this poll is cancelled.
                    try Task.checkCancellation()
                    return true
                }
                return reached
            }
            group.addTask {
                // Giving up keeps the mixed results. A slow probe must not invent an outage.
                try await Task.sleep(nanoseconds: UInt64(self.confirmationTimeout * 1_000_000_000))
                return true
            }
            let reached = try await group.next() ?? true
            group.cancelAll()
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
                token: page.token,
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
