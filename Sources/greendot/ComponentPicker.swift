import AppKit
import StatusCore

final class ComponentPicker: NSObject {
    private let onToggleComponent: (String) -> Void
    private let onSetAll: (Bool) -> Void
    private var disabledNames: Set<String>
    private var checkboxes: [String: NSButton] = [:]
    private var allCheckbox: NSButton?
    private let rootComponents: [ComponentStatus]

    init(
        page: WatchedPage,
        onToggleComponent: @escaping (String) -> Void,
        onSetAll: @escaping (Bool) -> Void
    ) {
        self.onToggleComponent = onToggleComponent
        self.onSetAll = onSetAll
        self.disabledNames = page.disabledComponentNames
        self.rootComponents = page.snapshot?.components ?? []
        super.init()
    }

    static func count(_ items: [ComponentStatus]) -> Int {
        items.reduce(0) { $0 + 1 + count($1.children) }
    }

    func install(in view: NSView, below anchor: NSView, listHeight: CGFloat) -> [NSLayoutConstraint] {
        let components = rootComponents
        guard !components.isEmpty else { return [] }

        let label = NSTextField(labelWithString: "Components")
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        let all = NSButton(checkboxWithTitle: "All", target: self, action: #selector(allClicked(_:)))
        all.setAccessibilityIdentifier("component-all")
        all.imagePosition = .imageLeading
        all.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(all)
        allCheckbox = all

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addCheckboxes(components, indent: 0, stack: stack)
        refreshTreeStates()

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = stack
        scroll.setAccessibilityIdentifier("component-list")
        view.addSubview(scroll)

        return [
            label.topAnchor.constraint(equalTo: anchor.bottomAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: anchor.leadingAnchor),
            all.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            all.leadingAnchor.constraint(equalTo: anchor.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: all.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: anchor.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scroll.heightAnchor.constraint(equalToConstant: listHeight),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ]
    }

    private func addCheckboxes(_ components: [ComponentStatus], indent: Int, stack: NSStackView) {
        for component in components {
            let pad = String(repeating: "    ", count: indent)
            let title: String
            if component.isGroup || !component.children.isEmpty {
                title = "\(pad)\(component.name)"
            } else {
                title = "\(pad)\(component.name)  —  \(component.statusText)"
            }
            let button = NSButton(
                checkboxWithTitle: title,
                target: self,
                action: #selector(componentClicked(_:))
            )
            button.identifier = NSUserInterfaceItemIdentifier(component.id)
            button.setAccessibilityIdentifier("component-\(component.id)")
            button.imagePosition = .imageLeading
            checkboxes[component.id] = button
            stack.addArrangedSubview(button)
            addCheckboxes(component.children, indent: indent + 1, stack: stack)
        }
    }

    @objc private func allClicked(_: NSButton) {
        let nodes = rootComponents.flatMap(ComponentTree.collect)
        let allOn = nodes.allSatisfy { !isOff($0) }
        setEnabled(!allOn, nodes: nodes)
        refreshTreeStates()
        onSetAll(!allOn)
    }

    @objc private func componentClicked(_ sender: NSButton) {
        let key = sender.identifier?.rawValue ?? sender.title
        let node = ComponentTree.find(key, in: rootComponents)
        let nodes = node.map(ComponentTree.collect) ?? []
        let allOn = nodes.isEmpty ? !disabledNames.contains(key) : nodes.allSatisfy { !isOff($0) }
        if nodes.isEmpty {
            setEnabled(!allOn, keys: [key])
        } else {
            setEnabled(!allOn, nodes: nodes)
        }
        refreshTreeStates()
        onToggleComponent(key)
    }

    private func setEnabled(_ enabled: Bool, nodes: [ComponentStatus]) {
        setEnabled(enabled, keys: nodes.flatMap { [$0.id, $0.name] })
    }

    private func setEnabled(_ enabled: Bool, keys: [String]) {
        if enabled {
            keys.forEach { disabledNames.remove($0) }
        } else {
            disabledNames.formUnion(keys)
        }
    }

    private func isOff(_ component: ComponentStatus) -> Bool {
        disabledNames.contains(component.id) || disabledNames.contains(component.name)
    }

    private func refreshTreeStates() {
        let nodes = rootComponents.flatMap(ComponentTree.collect)
        for component in nodes {
            guard let button = checkboxes[component.id] else { continue }
            applyState(button, nodes: ComponentTree.collect(component))
        }
        if let allCheckbox {
            applyState(allCheckbox, nodes: nodes)
        }
    }

    private func applyState(_ button: NSButton, nodes: [ComponentStatus]) {
        let onCount = nodes.filter { !isOff($0) }.count
        let mixed = onCount > 0 && onCount < nodes.count
        if mixed {
            button.allowsMixedState = true
            button.state = .mixed
            return
        }
        if button.state == .mixed {
            button.state = .off
        }
        button.allowsMixedState = false
        button.state = onCount == 0 ? .off : .on
    }
}
