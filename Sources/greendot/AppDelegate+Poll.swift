import StatusCore

extension AppDelegate {
    /// The network toast stands in for every page, so its arrival clears the page panels it replaces.
    /// A poll that is no longer offline clears a network toast whose recovery never reached the screen.
    @MainActor
    func reconcileNetworkToast(_ monitor: Monitor, toasts: [Toast]) {
        if toasts.contains(NetworkToast.lost) {
            monitor.pages.forEach { toastDelivery.clear(pageID: $0.id) }
        } else if !monitor.showingNetworkLoss {
            toastDelivery.clear(pageID: NetworkToast.pageID)
        }
    }

    func pollAndRefresh() async {
        guard let monitor else { return }
        await pollAndRefresh(monitor)
    }

    func pollAndRefresh(_ monitor: Monitor) async {
        // A failed reload must not let a poll write the old settings over the file the user is fixing.
        guard !configLoadFailed else { return }
        let invocation = await MainActor.run {
            pollRefreshState.latestInvocation &+= 1
            return pollRefreshState.latestInvocation
        }
        let outcome: (toasts: [Toast], error: Error?)
        do {
            outcome = (try await monitor.pollAll(), nil)
        } catch is CancellationError {
            return
        } catch {
            outcome = ([], error)
        }
        await MainActor.run {
            guard invocation == self.pollRefreshState.latestInvocation else { return }
            if let error = outcome.error {
                if error as? StoreError == .changedOnDisk {
                    self.handleStoreError(error)
                    return
                }
                if !self.pollRefreshState.presentedError {
                    self.pollRefreshState.presentedError = true
                    self.presentError(error)
                }
            } else {
                self.pollRefreshState.presentedError = false
                self.reconcileNetworkToast(monitor, toasts: outcome.toasts)
                outcome.toasts.forEach { self.toastDelivery.deliver($0) }
            }
            self.rebuild()
        }
    }
}
