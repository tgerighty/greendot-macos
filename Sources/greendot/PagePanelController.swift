import AppKit
import StatusCore

final class PagePanelController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let urlField = NSTextField(string: "")
    private let nameField = NSTextField(string: "")
    private let onSave: (URL, String?) -> Void

    init(page: WatchedPage?, onSave: @escaping (URL, String?) -> Void) {
        self.onSave = onSave
        let editing = page != nil
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = editing ? "Edit Status Page" : "Add Status Page"
        window.level = .floating
        super.init()
        window.delegate = self
        window.contentView = buildView(page: page)
        window.center()
        window.setAccessibilityIdentifier("status-page-panel")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func buildView(page: WatchedPage?) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        let urlLabel = NSTextField(labelWithString: "Status page URL")
        let nameLabel = NSTextField(labelWithString: "Name")
        urlField.placeholderString = "https://status.example.com"
        urlField.setAccessibilityIdentifier("url-field")
        urlField.setAccessibilityLabel("url-field")
        urlField.stringValue = page?.url.absoluteString ?? ""
        nameField.placeholderString = "Optional display name"
        nameField.setAccessibilityIdentifier("name-field")
        nameField.setAccessibilityLabel("name-field")
        nameField.stringValue = page?.name ?? ""

        let save = NSButton(title: page == nil ? "Add" : "Save", target: self, action: #selector(saveTapped))
        save.setAccessibilityIdentifier("save-button")
        save.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.setAccessibilityIdentifier("cancel-button")

        for item in [urlLabel, urlField, nameLabel, nameField, save, cancel] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }

        NSLayoutConstraint.activate([
            urlLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            urlLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            urlField.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 4),
            urlField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            urlField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            nameLabel.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
            nameField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            nameField.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: urlField.trailingAnchor),
            cancel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -8),
            save.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            save.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
        return view
    }

    @objc private func saveTapped() {
        let raw = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = raw
        if !text.contains("://") {
            text = "https://\(text)"
        }
        guard let url = URL(string: text), url.host != nil else {
            NSSound.beep()
            return
        }
        onSave(url, nameField.stringValue)
        window.close()
    }

    @objc private func cancelTapped() {
        window.close()
    }
}
