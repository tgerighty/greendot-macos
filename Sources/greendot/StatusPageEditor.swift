import AppKit
import StatusCore

@MainActor
final class StatusPageEditor {
    private let monitor: Monitor
    private let editingPageID: UUID?
    private let onChange: () -> Void
    private let presentError: (Error) -> Void
    private var panel: PagePanelController?

    init(
        monitor: Monitor,
        editingPageID: UUID?,
        onChange: @escaping () -> Void,
        presentError: @escaping (Error) -> Void
    ) {
        self.monitor = monitor
        self.editingPageID = editingPageID
        self.onChange = onChange
        self.presentError = presentError
    }

    func show() {
        let previous = panel
        previous?.close()
        panel = nil

        let page: WatchedPage?
        if let editingPageID {
            guard let current = monitor.pages.first(where: { $0.id == editingPageID }) else {
                presentError(MonitorError.pageNotFound(editingPageID))
                return
            }
            page = current
        } else {
            page = nil
        }

        let currentPageID = page?.id
        let currentPanel = PagePanelController(
            page: page,
            onSave: { [weak self] url, name in
                guard let self else { return false }
                return await self.save(pageID: currentPageID, url: url, name: name)
            },
            onToggleComponent: toggleComponentHandler(pageID: currentPageID),
            onSetAll: setAllComponentsHandler(pageID: currentPageID),
            onRemove: currentPageID.map { pageID in
                { [weak self] in
                    guard let self else { return false }
                    return self.remove(pageID: pageID)
                }
            }
        )
        panel = currentPanel
        currentPanel.show()

        // Keep the old AppKit panel alive through the replacement operation.
        // AppDelegate also retains the previous editor when replacing panels
        // from a status-item menu action.
        _ = previous
    }

    func close() {
        panel?.close()
        // AppKit must not destroy a status-item panel during the menu action
        // that replaces it. AppDelegate retains this editor until the next
        // run-loop turn, so keep the closed panel attached until then.
    }
}

private extension StatusPageEditor {
    func toggleComponentHandler(pageID: UUID?) -> ((String) -> Bool)? {
        guard let pageID else { return nil }
        return { [weak self] name in
            guard let self else { return false }
            return self.performChange {
                try self.monitor.toggleComponent(id: pageID, name: name)
            }
        }
    }

    func setAllComponentsHandler(pageID: UUID?) -> ((Bool) -> Bool)? {
        guard let pageID else { return nil }
        return { [weak self] enabled in
            guard let self else { return false }
            return self.performChange {
                try self.monitor.setAllComponents(id: pageID, enabled: enabled)
            }
        }
    }

    func save(pageID: UUID?, url: URL, name: String?) async -> Bool {
        do {
            if let pageID {
                try await monitor.edit(id: pageID, url: url, name: name)
            } else {
                try await monitor.add(url: url, name: name)
            }
            onChange()
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            presentError(error)
            return false
        }
    }

    func performChange(_ work: () throws -> Void) -> Bool {
        do {
            try work()
            onChange()
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    func remove(pageID: UUID) -> Bool {
        performChange {
            try monitor.remove(id: pageID)
        }
    }
}
