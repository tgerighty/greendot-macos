import AppKit
import StatusCore

private final class KeyablePanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PagePanelController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let urlField = NSTextField(string: "")
    private let nameField = NSTextField(string: "")
    private let tokenField = NSSecureTextField(string: "")
    private let onSave: (URL, String?, String?) -> Void
    private let onRemove: (() -> Void)?
    private var picker: ComponentPicker?

    init(
        page: WatchedPage?,
        onSave: @escaping (URL, String?, String?) -> Void,
        onToggleComponent: ((String) -> Bool)? = nil,
        onSetAll: ((Bool) -> Bool)? = nil,
        onRemove: (() -> Void)? = nil
    ) {
        self.onSave = onSave
        self.onRemove = onRemove
        if let page {
            self.picker = ComponentPicker(
                page: page,
                onToggleComponent: onToggleComponent ?? { _ in true },
                onSetAll: onSetAll ?? { _ in true }
            )
        }
        let editing = page != nil
        let componentCount = ComponentPicker.count(page?.snapshot?.components ?? [])
        let listHeight = CGFloat(min(max(componentCount, 1), 12) * 24 + 8)
        let height: CGFloat = editing ? 256 + listHeight + 48 : 216
        window = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = editing ? "Edit Status Page" : "Add Status Page"
        window.level = .floating
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self
        window.contentView = buildView(page: page, listHeight: listHeight)
        window.center()
        window.setAccessibilityIdentifier("status-page-panel")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(urlField)
    }

    func close() {
        window.delegate = nil
        window.orderOut(nil)
    }

    /// Same path as the window close button / Save / Cancel.
    func closeWindow() {
        window.close()
    }

    private func buildView(page: WatchedPage?, listHeight: CGFloat) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: window.frame.height))
        configureFields(page: page)
        let save = button(page == nil ? "Add" : "Save", id: "save-button", action: #selector(saveTapped))
        save.keyEquivalent = "\r"
        let cancel = button("Cancel", id: "cancel-button", action: #selector(cancelTapped))
        [urlField, nameField, tokenField, save, cancel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        var constraints = fieldConstraints(in: view)
        if page != nil, let picker {
            constraints.append(contentsOf: picker.install(in: view, below: tokenField, listHeight: listHeight))
            let remove = button("Remove Status Page", id: "remove-page-button", action: #selector(removeTapped))
            remove.bezelStyle = .rounded
            remove.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(remove)
            constraints.append(remove.leadingAnchor.constraint(equalTo: urlField.leadingAnchor))
            constraints.append(remove.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12))
        }
        constraints.append(contentsOf: [
            cancel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -8),
            save.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            save.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
        NSLayoutConstraint.activate(constraints)
        return view
    }

    private func configureFields(page: WatchedPage?) {
        urlField.placeholderString = "https://status.example.com"
        urlField.setAccessibilityIdentifier("url-field")
        urlField.setAccessibilityLabel("url-field")
        urlField.stringValue = page?.url.absoluteString ?? ""
        nameField.placeholderString = "Optional display name"
        nameField.setAccessibilityIdentifier("name-field")
        nameField.setAccessibilityLabel("name-field")
        nameField.stringValue = page?.name ?? ""
        tokenField.placeholderString = "Optional token for a private page"
        tokenField.setAccessibilityIdentifier("token-field")
        tokenField.setAccessibilityLabel("token-field")
        tokenField.stringValue = page?.token ?? ""
    }

    private func button(_ title: String, id: String, action: Selector) -> NSButton {
        let item = NSButton(title: title, target: self, action: action)
        item.setAccessibilityIdentifier(id)
        return item
    }

    private func fieldConstraints(in view: NSView) -> [NSLayoutConstraint] {
        let urlLabel = NSTextField(labelWithString: "Status page URL")
        let nameLabel = NSTextField(labelWithString: "Name")
        let tokenLabel = NSTextField(labelWithString: "Token")
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        tokenLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(urlLabel)
        view.addSubview(nameLabel)
        view.addSubview(tokenLabel)
        return [
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
            tokenLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 12),
            tokenLabel.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
            tokenField.topAnchor.constraint(equalTo: tokenLabel.bottomAnchor, constant: 4),
            tokenField.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
            tokenField.trailingAnchor.constraint(equalTo: urlField.trailingAnchor)
        ]
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
        let tokenRaw = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(url, nameField.stringValue, tokenRaw.isEmpty ? nil : tokenRaw)
        window.close()
    }

    @objc private func cancelTapped() {
        window.close()
    }

    @objc private func removeTapped() {
        onRemove?()
        window.close()
    }
}
