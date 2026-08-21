import AppKit
import StatusCore

final class PagePanelController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let urlField = NSTextField(string: "")
    private let nameField = NSTextField(string: "")
    private let onSave: (URL, String?) -> Void
    private let onToggleComponent: ((String) -> Void)?
    private let onRemove: (() -> Void)?
    private var disabledNames: Set<String>
    private var checkboxes: [String: NSButton] = [:]

    init(
        page: WatchedPage?,
        onSave: @escaping (URL, String?) -> Void,
        onToggleComponent: ((String) -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) {
        self.onSave = onSave
        self.onToggleComponent = onToggleComponent
        self.onRemove = onRemove
        self.disabledNames = page?.disabledComponentNames ?? []
        let editing = page != nil
        let componentCount = page?.snapshot?.components.count ?? 0
        let listHeight = CGFloat(min(max(componentCount, 1), 12) * 24 + 8)
        let height: CGFloat = editing ? 200 + listHeight + 48 : 160
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = editing ? "Edit Status Page" : "Add Status Page"
        window.level = .floating
        super.init()
        window.delegate = self
        window.contentView = buildView(page: page, listHeight: listHeight)
        window.center()
        window.setAccessibilityIdentifier("status-page-panel")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func buildView(page: WatchedPage?, listHeight: CGFloat) -> NSView {
        let height = window.frame.height
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: height))
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

        let views: [NSView] = [urlLabel, urlField, nameLabel, nameField, save, cancel]
        for item in views {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }

        var constraints: [NSLayoutConstraint] = [
            urlLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            urlLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            urlField.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 4),
            urlField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            urlField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            nameLabel.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
            nameField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            nameField.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: urlField.trailingAnchor)
        ]

        if let page, let components = page.snapshot?.components, !components.isEmpty {
            let componentsLabel = NSTextField(labelWithString: "Components")
            componentsLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(componentsLabel)
            constraints.append(contentsOf: [
                componentsLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 14),
                componentsLabel.leadingAnchor.constraint(equalTo: urlField.leadingAnchor)
            ])

            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 2
            stack.translatesAutoresizingMaskIntoConstraints = false

            for component in components {
                let button = NSButton(
                    checkboxWithTitle: "\(component.name)  —  \(component.statusText)",
                    target: self,
                    action: #selector(componentClicked(_:))
                )
                button.identifier = NSUserInterfaceItemIdentifier(component.name)
                button.state = page.isComponentEnabled(component.name) ? .on : .off
                button.setAccessibilityIdentifier("component-\(component.name)")
                button.imagePosition = .imageLeading
                checkboxes[component.name] = button
                stack.addArrangedSubview(button)
            }

            let scroll = NSScrollView()
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false
            scroll.documentView = stack
            scroll.setAccessibilityIdentifier("component-list")
            view.addSubview(scroll)
            constraints.append(contentsOf: [
                scroll.topAnchor.constraint(equalTo: componentsLabel.bottomAnchor, constant: 6),
                scroll.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: urlField.trailingAnchor),
                scroll.heightAnchor.constraint(equalToConstant: listHeight),
                stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
                stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
                stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
            ])
        }

        if page != nil {
            let remove = NSButton(title: "Remove Status Page", target: self, action: #selector(removeTapped))
            remove.setAccessibilityIdentifier("remove-page-button")
            remove.bezelStyle = .rounded
            remove.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(remove)
            constraints.append(contentsOf: [
                remove.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
                remove.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
            ])
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

    @objc private func componentClicked(_ sender: NSButton) {
        let name = sender.identifier?.rawValue ?? sender.title
        if disabledNames.contains(name) {
            disabledNames.remove(name)
            sender.state = .on
        } else {
            disabledNames.insert(name)
            sender.state = .off
        }
        onToggleComponent?(name)
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

    @objc private func removeTapped() {
        onRemove?()
        window.close()
    }
}
