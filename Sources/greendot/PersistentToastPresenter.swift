import AppKit
import StatusCore

@MainActor
protocol PersistentToastPresenter: AnyObject {
    func present(_ toast: Toast)
    func clear(pageID: UUID)
}

/// App-owned toast. macOS UserNotifications banners always time out, and
/// `NSUserNotificationAlertStyle` does not apply to `UNUserNotificationCenter`.
@MainActor
final class PanelPersistentToastPresenter: PersistentToastPresenter {
    private let playSound: () -> Void
    private var items: [Item] = []
    private var pending: [Toast] = []

    init(playSound: @escaping () -> Void = { NSSound.beep() }) {
        self.playSound = playSound
    }

    func present(_ toast: Toast) {
        if items.contains(where: { $0.pageID == toast.pageID }) {
            items.filter { $0.pageID == toast.pageID }.forEach { removeWindow($0.window) }
            show(toast, play: true)
            return
        }
        if let index = pending.firstIndex(where: { $0.pageID == toast.pageID }) {
            pending[index] = toast
            playSound()
            return
        }
        while items.count >= maxVisiblePanels() {
            let oldest = items[0]
            pending.append(oldest.toast)
            removeWindow(oldest.window)
        }
        show(toast, play: true)
    }

    func clear(pageID: UUID) {
        items.filter { $0.pageID == pageID }.forEach { removeWindow($0.window) }
        pending.removeAll { $0.pageID == pageID }
        showNextPendingIfNeeded()
    }

    var windows: [NSWindow] {
        items.map(\.window)
    }

    var visibleCount: Int {
        items.map(\.window).filter(\.isVisible).count
    }
}

private struct Item {
    let window: NSWindow
    let toast: Toast

    var pageID: UUID { toast.pageID }
}

private enum PersistentToastLayout {
    static let size = NSSize(width: 320, height: 56)
    static let margin: CGFloat = 12
    static let gap: CGFloat = 8
    static let maxPanels = 8
}

private extension PanelPersistentToastPresenter {
    func makeWindow(for toast: Toast) -> NSPanel {
        let card = PersistentToastCard(toast: toast)
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: PersistentToastLayout.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentView = card
        window.setAccessibilityIdentifier("persistent-toast")
        card.onAcknowledge = { [weak self, weak window] in
            guard let self, let window else { return }
            self.dismiss(window)
        }
        return window
    }

    func show(_ toast: Toast, play: Bool) {
        let window = makeWindow(for: toast)
        items.append(Item(window: window, toast: toast))
        layoutWindows()
        window.orderFrontRegardless()
        if play { playSound() }
    }

    func removeWindow(_ window: NSWindow) {
        items.removeAll { $0.window === window }
        window.orderOut(nil)
    }

    func dismiss(_ window: NSWindow) {
        removeWindow(window)
        showNextPendingIfNeeded()
    }

    func showNextPendingIfNeeded() {
        guard !pending.isEmpty, items.count < maxVisiblePanels() else {
            layoutWindows()
            return
        }
        let next = pending.removeFirst()
        show(next, play: false)
    }

    func maxVisiblePanels() -> Int {
        guard let screen = NSScreen.main?.visibleFrame else { return PersistentToastLayout.maxPanels }
        let pitch = PersistentToastLayout.size.height + PersistentToastLayout.gap
        let capacity = max(1, Int((screen.height - PersistentToastLayout.margin) / pitch))
        return min(PersistentToastLayout.maxPanels, capacity)
    }

    func layoutWindows() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let size = PersistentToastLayout.size
        for (index, item) in items.enumerated() {
            let originX = screen.maxX - size.width - PersistentToastLayout.margin
            let originY = screen.maxY - size.height - PersistentToastLayout.margin
                - CGFloat(index) * (size.height + PersistentToastLayout.gap)
            item.window.setFrame(
                NSRect(x: originX, y: originY, width: size.width, height: size.height),
                display: true
            )
        }
    }
}

private final class PersistentToastCard: NSView {
    var onAcknowledge: () -> Void = {}

    init(toast: Toast) {
        super.init(frame: NSRect(origin: .zero, size: PersistentToastLayout.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 10
        let dot = NSImageView(image: StatusDot.image(toast.severity, size: 18))
        let title = NSTextField(labelWithString: toast.pageName)
        title.font = .boldSystemFont(ofSize: 13)
        let body = NSTextField(labelWithString: toast.body)
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        [dot, title, body].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 18),
            dot.heightAnchor.constraint(equalToConstant: 18),
            title.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            body.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2)
        ])
        setAccessibilityIdentifier("persistent-toast-card")
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(toast.pageName), \(toast.body)")
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with _: NSEvent) {
        onAcknowledge()
    }

    override func accessibilityPerformPress() -> Bool {
        onAcknowledge()
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
