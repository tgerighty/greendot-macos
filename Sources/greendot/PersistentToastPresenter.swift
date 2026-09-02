import AppKit
import StatusCore

@MainActor
protocol PersistentToastPresenter: AnyObject {
    func present(_ toast: Toast)
}

/// App-owned toast. macOS UserNotifications banners always time out, and
/// `NSUserNotificationAlertStyle` does not apply to `UNUserNotificationCenter`.
@MainActor
final class PanelPersistentToastPresenter: PersistentToastPresenter {
    private let playSound: () -> Void
    private(set) var windows: [NSWindow] = []

    init(playSound: @escaping () -> Void = { NSSound.beep() }) {
        self.playSound = playSound
    }

    func present(_ toast: Toast) {
        let window = makeWindow(for: toast)
        windows.append(window)
        layoutWindows()
        window.orderFrontRegardless()
        playSound()
    }

    var visibleCount: Int {
        windows.filter(\.isVisible).count
    }
}

private enum PersistentToastLayout {
    static let size = NSSize(width: 320, height: 56)
    static let margin: CGFloat = 12
    static let gap: CGFloat = 8
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

    func dismiss(_ window: NSWindow) {
        windows.removeAll { $0 === window }
        window.orderOut(nil)
        layoutWindows()
    }

    func layoutWindows() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let size = PersistentToastLayout.size
        for (index, window) in windows.enumerated() {
            let originX = screen.maxX - size.width - PersistentToastLayout.margin
            let originY = screen.maxY - size.height - PersistentToastLayout.margin
                - CGFloat(index) * (size.height + PersistentToastLayout.gap)
            window.setFrame(
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

    override func mouseDown(with _: NSEvent) {
        onAcknowledge()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
