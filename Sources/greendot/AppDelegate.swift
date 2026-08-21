import AppKit
import StatusCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var monitor: Monitor?
    private var pollTimer: Timer?
    private var pulseTimer: Timer?
    private var panel: PagePanelController?
    private var notifier: Notifier?

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
        try? monitor.load()
        self.monitor = monitor

        let notifier = Notifier()
        notifier.requestPermissionIfNeeded()
        self.notifier = notifier

        if ProcessInfo.processInfo.environment["GREENDOT_SKIP_LOGIN_ITEM"] == nil {
            monitor.enableLaunchAtLoginOnFirstRun()
        }

        let menuBar = MenuBarController()
        menuBar.menuProvider = { [weak self] in
            self?.buildMenu() ?? NSMenu()
        }
        self.menuBar = menuBar
        rebuild()
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.tgerighty.greendot.showMenu"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.menuBar?.popMenuOnScreen()
        }

        Task {
            if ProcessInfo.processInfo.environment["GREENDOT_SKIP_SEED"] == nil,
               monitor.pages.isEmpty,
               let url = URL(string: "https://status.openai.com") {
                try? await monitor.add(url: url, name: "OpenAI")
            }
            await self.pollAndRefresh()
        }

        let poll = TimeInterval(
            ProcessInfo.processInfo.environment["GREENDOT_POLL_SECONDS"].flatMap(Double.init) ?? 60
        )
        pollTimer = Timer.scheduledTimer(withTimeInterval: poll, repeats: true) { [weak self] _ in
            Task { await self?.pollAndRefresh() }
        }
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refreshIcon()
        }
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
            barSeverity: monitor.barSeverity(),
            onAdd: { [weak self] in self?.openPanel(editing: nil) },
            onEdit: { [weak self] page in self?.openPanel(editing: page) },
            onRemove: { [weak self] id in
                try? self?.monitor?.remove(id: id)
                self?.rebuild()
            },
            onToggleNotifications: { [weak self] id in
                try? self?.monitor?.toggleNotifications(id: id)
                self?.rebuild()
            },
            onOpen: { url in
                NSWorkspace.shared.open(url)
            },
            onRefresh: { [weak self] in
                Task { await self?.pollAndRefresh() }
            },
            launchAtLoginEnabled: LaunchAtLogin.isEnabled,
            onToggleLaunchAtLogin: { [weak self] in
                _ = LaunchAtLogin.toggle()
                self?.rebuild()
            },
            onQuit: { NSApp.terminate(nil) }
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
                        await MainActor.run {
                            let alert = NSAlert(error: error)
                            _ = alert.runModal()
                        }
                    }
                }
            },
            onToggleComponent: editing.map { page in
                { [weak self] name in
                    try? self?.monitor?.toggleComponent(id: page.id, name: name)
                    self?.rebuild()
                }
            },
            onSetAll: editing.map { page in
                { [weak self] enabled in
                    try? self?.monitor?.setAllComponents(id: page.id, enabled: enabled)
                    self?.rebuild()
                }
            },
            onRemove: editing.map { page in
                { [weak self] in
                    try? self?.monitor?.remove(id: page.id)
                    self?.rebuild()
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
}
