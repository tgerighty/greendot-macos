import AppKit
import StatusCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var monitor: Monitor?
    private var pollTimer: Timer?
    private var pulseTimer: Timer?
    private var panel: PagePanelController?
    private var notifier: Notifier?
    var presentError: (Error) -> Void = { error in
        _ = NSAlert(error: error).runModal()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppEditMenu.install()

        let store = PageStore(directory: PageStore.defaultDirectory)
        let client: HTTPClient
        if let fixture = ProcessInfo.processInfo.environment["GREENDOT_FIXTURE_DIR"], !fixture.isEmpty {
            client = DirectoryHTTPClient(root: URL(fileURLWithPath: fixture, isDirectory: true))
        } else {
            client = URLSessionHTTPClient()
        }
        let monitor = Monitor(store: store, client: client)
        monitor.onLaunchAtLoginEnable = { LaunchAtLogin.enable() }
        let loadSucceeded = loadMonitor(monitor)
        self.monitor = monitor

        let notifier = Notifier()
        notifier.requestPermissionIfNeeded()
        self.notifier = notifier

        if loadSucceeded, ProcessInfo.processInfo.environment["GREENDOT_SKIP_LOGIN_ITEM"] == nil {
            monitor.enableLaunchAtLoginOnFirstRun()
        }

        let menuBar = MenuBarController()
        menuBar.menuProvider = { [weak self] in
            self?.buildMenu() ?? NSMenu()
        }
        self.menuBar = menuBar
        rebuild()
        installUITestHooks()

        Task {
            await self.maybeSeedOpenAI(monitor: monitor, loadSucceeded: loadSucceeded)
            if Self.shouldPoll(loadSucceeded: loadSucceeded) {
                await self.pollAndRefresh()
            }
        }

        if Self.shouldPoll(loadSucceeded: loadSucceeded) {
            let poll = TimeInterval(
                ProcessInfo.processInfo.environment["GREENDOT_POLL_SECONDS"].flatMap(Double.init) ?? 60
            )
            pollTimer = Timer.scheduledTimer(withTimeInterval: poll, repeats: true) { [weak self] _ in
                Task { await self?.pollAndRefresh() }
            }
        }
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let monitor = self.monitor else { return }
            let hasUnreachable = monitor.pages.contains { $0.snapshot?.isUnreachable == true }
            guard Self.shouldRefreshIconOnPulse(hasUnreachable: hasUnreachable) else { return }
            self.refreshIcon()
        }
    }

    func loadMonitor(_ monitor: Monitor) -> Bool {
        do {
            try monitor.load()
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    static func shouldSeedOpenAI(loadSucceeded: Bool, pagesEmpty: Bool, skipSeed: Bool) -> Bool {
        loadSucceeded && pagesEmpty && !skipSeed
    }

    static func shouldPoll(loadSucceeded: Bool) -> Bool {
        loadSucceeded
    }

    /// Pulse exists to flash grey while a page is unreachable. Today every tick
    /// still refreshes the icon; the harness counts that so we can skip it.
    static func shouldRefreshIconOnPulse(hasUnreachable: Bool) -> Bool {
        hasUnreachable
    }

    static func showAbout() {
        AboutPanel.show()
    }

    @discardableResult
    func performStoreChange(_ work: () throws -> Void) -> Bool {
        do {
            try work()
            rebuild()
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    private func maybeSeedOpenAI(monitor: Monitor, loadSucceeded: Bool) async {
        let skipSeed = ProcessInfo.processInfo.environment["GREENDOT_SKIP_SEED"] != nil
        guard Self.shouldSeedOpenAI(
            loadSucceeded: loadSucceeded,
            pagesEmpty: monitor.pages.isEmpty,
            skipSeed: skipSeed
        ), let url = URL(string: "https://status.openai.com") else { return }
        try? await monitor.add(url: url, name: "OpenAI")
    }

    private func pollAndRefresh() async {
        guard let monitor else { return }
        let toasts = await monitor.pollAll()
        await MainActor.run {
            toasts.forEach { notifier?.post($0) }
            rebuild()
        }
    }

    private func rebuild() {
        refreshIcon()
        menuBar?.reloadMenu()
    }

    private func refreshIcon() {
        guard let monitor else { return }
        let displayed = monitor.displayedSeverity(at: Date())
        menuBar?.setSeverity(displayed)
    }

    private func buildMenu() -> NSMenu {
        guard let monitor else { return NSMenu() }
        return MenuBuilder.build(
            pages: monitor.pages,
            launchAtLoginEnabled: LaunchAtLogin.isEnabled,
            actions: MenuActions(
                onAdd: { [weak self] in self?.openPanel(editing: nil) },
                onEdit: { [weak self] page in self?.openPanel(editing: page) },
                onRemove: { [weak self] id in
                    self?.performStoreChange { try self?.monitor?.remove(id: id) }
                },
                onToggleNotifications: { [weak self] id in
                    self?.performStoreChange { try self?.monitor?.toggleNotifications(id: id) }
                },
                onOpen: { url in
                    URLOpener.open(url)
                },
                onRefresh: { [weak self] in
                    Task { await self?.pollAndRefresh() }
                },
                onToggleLaunchAtLogin: { [weak self] in
                    LaunchAtLogin.toggle()
                    self?.rebuild()
                },
                onAbout: { AppDelegate.showAbout() },
                onQuit: { NSApp.terminate(nil) }
            )
        )
    }

    private func openPanel(editing: WatchedPage?) {
        let previous = panel
        previous?.close()
        let panel = PagePanelController(
            page: editing,
            onSave: { [weak self] url, name in
                guard let self, let monitor = self.monitor else { return }
                Task {
                    do {
                        if let editing {
                            try await monitor.edit(id: editing.id, url: url, name: name)
                        } else {
                            try await monitor.add(url: url, name: name)
                        }
                        await MainActor.run { self.rebuild() }
                    } catch {
                        await MainActor.run { self.presentError(error) }
                    }
                }
            },
            onToggleComponent: editing.map { page in
                { [weak self] name in
                    self?.performStoreChange { try self?.monitor?.toggleComponent(id: page.id, name: name) } ?? false
                }
            },
            onSetAll: editing.map { page in
                { [weak self] enabled in
                    self?.performStoreChange {
                        try self?.monitor?.setAllComponents(id: page.id, enabled: enabled)
                    } ?? false
                }
            },
            onRemove: editing.map { page in
                { [weak self] in
                    self?.performStoreChange { try self?.monitor?.remove(id: page.id) }
                }
            }
        )
        self.panel = panel
        // Releasing the previous dialog inside the status-item menu action
        // over-releases AppKit view arrays (SIGSEGV in NSArray dealloc).
        DispatchQueue.main.async { [weak self] in
            _ = previous
            self?.panel?.show()
        }
    }

    private func installUITestHooks() {
        guard ProcessInfo.processInfo.environment["GREENDOT_UI_TEST"] != nil else { return }
        guard let configDir = ProcessInfo.processInfo.environment["GREENDOT_CONFIG_DIR"],
              !configDir.isEmpty else { return }
        observe("showMenu") { [weak self] _ in
            self?.menuBar?.popMenuOnScreen()
        }
        observe("clickMenu") { [weak self] path in
            self?.menuBar?.performMenuPath(path)
        }
        observe("dumpMenu") { [weak self] _ in
            Self.writeDump("GREENDOT_MENU_DUMP", body: self?.menuBar?.dumpMenu() ?? "")
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

    private func observe(_ name: String, handle: @escaping (String) -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.tgerighty.greendot.\(name)"),
            object: nil,
            queue: .main
        ) { note in
            handle(note.object as? String ?? "")
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
