import AppKit
import StatusCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusMenu: StatusMenuController?
    var monitor: Monitor?
    var store: PageStore?
    var pollTimer: Timer?
    var startupTask: Task<Void, Never>?
    var configLoadFailed = false
    private var pulseTimer: Timer?
    var editor: StatusPageEditor?
    var reloadingConfig = false
    var toastDelivery: any ToastDelivery = SystemToastDelivery()
    var pollRefreshState = (presentedError: false, latestInvocation: UInt64(0))
    var appearanceObservation: NSKeyValueObservation?
    var presentError: @MainActor (Error) -> Void = { error in
        _ = NSAlert(error: error).runModal()
    }
    var revealConfigFile: @MainActor (URL) -> Void = { url in
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    var seedFailureDiagnostic: @MainActor (Error) -> Void = { error in
        NSLog("greendot: OpenAI seed failed: \(error.localizedDescription)")
    }

    @MainActor
    init(toastDelivery: any ToastDelivery) {
        self.toastDelivery = toastDelivery
        super.init()
    }

    override nonisolated init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppEditMenu.install()

        let store = PageStore(directory: PageStore.defaultDirectory)
        let reachability = PathNetworkReachability()
        let monitor = Monitor(store: store, client: Self.makeHTTPClient(), reachability: reachability)
        self.store = store
        monitor.onLaunchAtLoginEnable = { LaunchAtLogin.enable() }
        let loadSucceeded = loadMonitor(monitor)
        configLoadFailed = !loadSucceeded
        self.monitor = monitor
        observeNetworkReachability(reachability)

        toastDelivery.start()

        if loadSucceeded, ProcessInfo.processInfo.environment["GREENDOT_SKIP_LOGIN_ITEM"] == nil {
            monitor.enableLaunchAtLoginOnFirstRun()
        }

        statusMenu = StatusMenuController(
            state: makeStatusMenuState(monitor),
            handlers: makeStatusMenuHandlers()
        )
        observeSystemAppearance()
        installUITestHooks()

        startupTask = Task {
            await self.maybeSeedOpenAI(monitor: monitor, loadSucceeded: loadSucceeded)
            if loadSucceeded {
                await self.pollAndRefresh()
            }
        }

        if loadSucceeded {
            restartPollTimer(interval: Self.pollInterval(
                from: ProcessInfo.processInfo.environment["GREENDOT_POLL_SECONDS"],
                configured: monitor.pollSeconds
            ))
        }
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let monitor = self.monitor else { return }
                let hasUnreachable = monitor.pages.contains { $0.snapshot?.isUnreachable == true }
                guard hasUnreachable else { return }
                self.rebuild()
            }
        }
    }

    func loadMonitor(_ monitor: Monitor) -> Bool {
        do {
            try monitor.load()
            GreendotStyle.choice = monitor.interfaceStyle
            StatusDot.clearCache()
            GreendotStyle.refreshOpenWindows()
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    nonisolated static func shouldSeedOpenAI(loadSucceeded: Bool, pagesEmpty: Bool, skipSeed: Bool) -> Bool {
        loadSucceeded && pagesEmpty && !skipSeed
    }

    nonisolated static func pollInterval(from rawValue: String?, configured: TimeInterval) -> TimeInterval {
        if let rawValue, let interval = Double(rawValue), interval.isFinite, interval > 0 {
            return interval
        }
        return AppConfig.validPollSeconds(configured)
    }

    func maybeSeedOpenAI(monitor: Monitor, loadSucceeded: Bool, skipSeed: Bool? = nil) async {
        let skipSeed = skipSeed ?? (ProcessInfo.processInfo.environment["GREENDOT_SKIP_SEED"] != nil)
        guard Self.shouldSeedOpenAI(
            loadSucceeded: loadSucceeded,
            pagesEmpty: monitor.pages.isEmpty,
            skipSeed: skipSeed
        ), let url = URL(string: "https://status.openai.com") else { return }
        do {
            try await monitor.add(url: url, name: "OpenAI")
        } catch is CancellationError {
            return
        } catch {
            seedFailureDiagnostic(error)
        }
    }

    @MainActor
    func rebuild() {
        guard let monitor else { return }
        statusMenu?.update(makeStatusMenuState(monitor))
    }

    @MainActor
    private func makeStatusMenuState(_ monitor: Monitor) -> StatusMenuState {
        StatusMenuState(
            pages: monitor.pages,
            disabledManagedPages: monitor.disabledManagedPages,
            severity: monitor.displayedSeverity(at: Date()),
            launchAtLoginEnabled: LaunchAtLogin.isEnabled,
            interfaceStyle: monitor.interfaceStyle
        )
    }

    @MainActor
    private func makeStatusMenuHandlers() -> StatusMenuHandlers {
        StatusMenuHandlers(
            onAdd: { [weak self] in self?.openEditor(editingPageID: nil) },
            onEdit: { [weak self] id in self?.openEditor(editingPageID: id) },
            onRemove: { [weak self] id in
                guard let self else { return }
                if self.performStoreChange({ try self.monitor?.remove(id: id) }) {
                    self.toastDelivery.clear(pageID: id)
                }
            },
            onToggleNotifications: { [weak self] id in
                guard let self, let monitor = self.monitor else { return }
                self.toggleNotifications(id: id, monitor: monitor)
            },
            onEnableManagedPage: { [weak self] id in
                guard let self, let monitor = self.monitor else { return }
                _ = self.performStoreChange { try monitor.enableManagedPage(id: id) }
            },
            onOpen: { url in
                URLOpener.open(url)
            },
            onRefresh: { [weak self] in
                Task { await self?.pollAndRefresh() }
            },
            onRevealConfig: { [weak self] in self?.revealConfig() },
            onReloadConfig: { [weak self] in self?.reloadConfig() },
            onToggleLaunchAtLogin: { [weak self] in
                LaunchAtLogin.toggle()
                self?.rebuild()
            },
            onSetInterfaceStyle: { [weak self] style in
                self?.setInterfaceStyle(style)
            },
            onAbout: { AboutPanel.show() },
            onQuit: { NSApp.terminate(nil) }
        )
    }

    @MainActor
    func openEditor(editingPageID: UUID?) {
        Task { @MainActor [weak self] in
            guard let self, let monitor = self.monitor else { return }
            // The editor saves on change, so it must not open over a config the app could not read.
            guard !self.configLoadFailed else {
                self.presentError(ConfigMenuError.reloadRequired)
                return
            }
            let previous = self.editor
            previous?.close()
            let editor = StatusPageEditor(
                monitor: monitor,
                editingPageID: editingPageID,
                onChange: { [weak self] in
                    self?.rebuild()
                },
                presentError: { [weak self] error in
                    self?.handleStoreError(error)
                },
                clearToast: { [weak self] pageID in
                    self?.toastDelivery.clear(pageID: pageID)
                },
                refreshToast: { [weak self] pageID in
                    self?.refreshToast(pageID: pageID)
                },
                onUncommittedClose: { [weak self] in
                    self?.reloadIfConfigChanged()
                }
            )
            self.editor = editor
            // Releasing the previous dialog inside the status-item menu action
            // over-releases AppKit view arrays (SIGSEGV in NSArray dealloc).
            DispatchQueue.main.async { [weak self] in
                guard let self, self.editor === editor else { return }
                editor.show()
                _ = previous
            }
        }
    }

    @MainActor
    private func installUITestHooks() {
        guard ProcessInfo.processInfo.environment["GREENDOT_UI_TEST"] != nil else { return }
        guard let configDir = ProcessInfo.processInfo.environment["GREENDOT_CONFIG_DIR"],
              !configDir.isEmpty else { return }
        observe("showMenu") { [weak self] _ in
            self?.statusMenu?.popMenuOnScreen()
        }
        observe("clickMenu") { [weak self] path in
            self?.statusMenu?.performMenuPath(path)
        }
        observe("dumpMenu") { [weak self] _ in
            Self.writeDump("GREENDOT_MENU_DUMP", body: self?.statusMenu?.dumpMenu() ?? "")
        }
        observe("clickIdentifier") { identifier in
            UITestDriver.clickIdentifier(identifier)
        }
        observe("dumpIdentifiers") { _ in
            Self.writeDump("GREENDOT_ID_DUMP", body: UITestDriver.identifiers().joined(separator: "\n"))
        }
        observe("setField") { raw in
            let parts = raw.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            UITestDriver.setField(parts[0], value: parts[1])
        }
        observe("focusField") { identifier in
            UITestDriver.focusField(identifier)
        }
    }

    @MainActor
    private func observe(_ name: String, handle: @escaping @MainActor @Sendable (String) -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.tgerighty.greendot.\(name)"),
            object: nil,
            queue: .main
        ) { note in
            let value = note.object as? String ?? ""
            MainActor.assumeIsolated {
                handle(value)
            }
        }
    }

    private static func writeDump(_ key: String, body: String) {
        guard let path = ProcessInfo.processInfo.environment[key], !path.isEmpty else { return }
        guard let configDir = ProcessInfo.processInfo.environment["GREENDOT_CONFIG_DIR"],
              !configDir.isEmpty else { return }
        let file = URL(fileURLWithPath: path)
        let root = URL(fileURLWithPath: configDir, isDirectory: true)
        guard PathSafety.contained(file, under: root) != nil else { return }
        try? body.write(to: file, atomically: true, encoding: .utf8)
    }
}

extension AppDelegate {
    private static func makeHTTPClient() -> HTTPClient {
        if let fixture = ProcessInfo.processInfo.environment["GREENDOT_FIXTURE_DIR"], !fixture.isEmpty {
            return DirectoryHTTPClient(root: URL(fileURLWithPath: fixture, isDirectory: true))
        }
        return URLSessionHTTPClient()
    }

    /// Path updates arrive on a background queue. Hop to the main actor before touching app state.
    func observeNetworkReachability(_ reachability: any NetworkReachability) {
        reachability.onChange = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.configLoadFailed else { return }
                await self.pollAndRefresh()
            }
        }
        reachability.start()
    }

    @MainActor
    func refreshToast(pageID: UUID, monitor: Monitor? = nil) {
        let monitor = monitor ?? self.monitor
        // The network toast stands in for every page. Putting a page toast back beside it would
        // undo the collapse, and no later poll of the same outage takes that toast down again.
        guard monitor?.showingNetworkLoss != true else {
            toastDelivery.clear(pageID: pageID)
            return
        }
        let pages = monitor?.pages ?? []
        guard let page = pages.first(where: { $0.id == pageID }) else {
            toastDelivery.clear(pageID: pageID)
            return
        }
        guard page.notificationsEnabled else {
            toastDelivery.clear(pageID: pageID)
            return
        }
        toastDelivery.deliver(
            Toast(
                pageID: page.id,
                pageName: page.name,
                body: page.displaySeverity.displayName,
                severity: page.displaySeverity
            )
        )
    }

    @MainActor
    func toggleNotifications(id: UUID, monitor: Monitor) {
        let wasEnabled = monitor.pages.first { $0.id == id }?.notificationsEnabled == true
        if performStoreChange({ try monitor.toggleNotifications(id: id) }), wasEnabled {
            toastDelivery.clear(pageID: id)
        }
    }

    @discardableResult
    @MainActor
    func performStoreChange(_ work: () throws -> Void) -> Bool {
        // A failed reload must not let a menu change write the old settings over the file the user is fixing.
        guard !configLoadFailed else {
            presentError(ConfigMenuError.reloadRequired)
            return false
        }
        do {
            try work()
            rebuild()
            return true
        } catch {
            handleStoreError(error)
            return false
        }
    }

    /// A changed config file is loaded. There is no dialog. An open add, edit, or remove
    /// window waits until that window closes.
    @MainActor
    func handleStoreError(_ error: Error) {
        guard error as? StoreError == .changedOnDisk else {
            presentError(error)
            return
        }
        guard editor == nil else { return }
        reloadConfig()
    }

    @MainActor
    func reloadIfConfigChanged() {
        guard !reloadingConfig else { return }
        guard store?.hasConfigChangedOnDisk() == true else { return }
        reloadConfig()
    }

}
