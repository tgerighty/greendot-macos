import AppKit
import StatusCore

/// Refuses a menu change while the config on disk is unreadable.
enum ConfigMenuError: Error, LocalizedError {
    case reloadRequired

    var errorDescription: String? {
        "greendot could not read config.json. Correct the file, then click Reload Config."
    }
}

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

    /// Reads the file again.
    /// On failure the in-memory config stays, polling and settings changes stop,
    /// and nothing is written until a reload succeeds.
    @MainActor
    func reloadConfig() {
        guard !reloadingConfig else { return }
        reloadingConfig = true
        defer { reloadingConfig = false }
        // A first-run seed still probing must not append OpenAI to the config the user just loaded.
        startupTask?.cancel()
        startupTask = nil
        // An open Add/Edit panel still probing must not save over the config the user just loaded.
        // Releasing it inside the status-item menu action over-releases AppKit view arrays
        // (SIGSEGV in NSArray dealloc), so keep it alive until the next run-loop turn.
        let closingEditor = editor
        closingEditor?.close()
        editor = nil
        DispatchQueue.main.async { _ = closingEditor }
        guard let monitor else { return }
        // Drop polls already in flight before reading the file, so none of them can save the old settings over it.
        monitor.discardInFlightPolls()
        let before = monitor.pages
        guard loadMonitor(monitor) else {
            configLoadFailed = true
            pollTimer?.invalidate()
            pollTimer = nil
            return
        }
        configLoadFailed = false
        // A launch whose load failed skipped first-run setup. Do it now.
        if ProcessInfo.processInfo.environment["GREENDOT_SKIP_LOGIN_ITEM"] == nil {
            monitor.enableLaunchAtLoginOnFirstRun()
        }
        reconcileToasts(before: before)
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

    /// Matches each open toast against the reloaded config, as an editor change does.
    /// Clears the toast of a page the reload removed, muted, made green, or left without a
    /// cached result. Refreshes the toast of a page that changed colour or name but stays unhealthy.
    @MainActor
    private func reconcileToasts(before: [WatchedPage]) {
        let current = monitor?.pages ?? []
        for page in before {
            guard let reloaded = current.first(where: { $0.id == page.id }),
                  reloaded.notificationsEnabled,
                  reloaded.snapshot != nil,
                  reloaded.displaySeverity != .green else {
                toastDelivery.clear(pageID: page.id)
                continue
            }
            guard reloaded.displaySeverity != page.displaySeverity || reloaded.name != page.name else { continue }
            refreshToast(pageID: page.id)
        }
    }
}
