import AppKit
import StatusCore

extension AppDelegate {
    /// Writes the config first when the file is missing, so the Finder can select it.
    @MainActor
    func revealConfig() {
        guard let store else { return }
        if !FileManager.default.fileExists(atPath: store.configURL.path), let monitor {
            guard performStoreChange({ try monitor.saveCurrentConfig() }) else { return }
        }
        revealConfigFile(store.configURL)
    }

    /// Reads the file again. On failure the in-memory config and the old timer stay.
    @MainActor
    func reloadConfig() {
        // A first-run seed still probing must not append OpenAI to the config the user just loaded.
        startupTask?.cancel()
        startupTask = nil
        // An open Add/Edit panel still probing must not save over the config the user just loaded.
        editor?.close()
        editor = nil
        guard let monitor else { return }
        let before = monitor.pages
        guard loadMonitor(monitor) else { return }
        clearObsoleteToasts(before: before)
        rebuild()
        restartPollTimer(interval: Self.pollInterval(
            from: ProcessInfo.processInfo.environment["GREENDOT_POLL_SECONDS"],
            configured: monitor.pollSeconds
        ))
        Task { [weak self] in await self?.pollAndRefresh() }
    }

    @MainActor
    func restartPollTimer(interval: TimeInterval) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollAndRefresh()
            }
        }
    }

    /// Clears the toasts of pages the reloaded config removed or muted.
    @MainActor
    private func clearObsoleteToasts(before: [WatchedPage]) {
        let current = monitor?.pages ?? []
        for page in before {
            let reloaded = current.first { $0.id == page.id }
            guard reloaded == nil || reloaded?.notificationsEnabled == false else { continue }
            toastDelivery.clear(pageID: page.id)
        }
    }
}
