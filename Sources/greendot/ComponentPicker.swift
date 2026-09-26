import AppKit
import StatusCore

@MainActor
final class ComponentPicker: NSObject {
    private let onToggleComponent: (String) -> Bool
    private let onSetAll: (Bool) -> Bool
    private var disabledNames: Set<String>
    private var regionTokens: [String]?
    private var checkboxes: [String: NSButton] = [:]
    private var allCheckbox: NSButton?
    private let rootComponents: [ComponentStatus]

    init(
        page: WatchedPage,
        onToggleComponent: @escaping (String) -> Bool,
        onSetAll: @escaping (Bool) -> Bool
    ) {
        self.onToggleComponent = onToggleComponent
        self.onSetAll = onSetAll
        self.disabledNames = page.disabledComponentNames
        self.regionTokens = page.enabledRegions
        self.rootComponents = page.snapshot?.components ?? []
        super.init()
    }

    /// Region tokens to write. `nil` means this page does not filter by region.
    func selectedEnabledRegions() -> [String]? { regionTokens }

    /// Mutes inside an allowed region. Components hidden by the region filter are not included.
    func selectedDisabledNames() -> Set<String> {
        guard let regionTokens else { return disabledNames }
        let allowed = RegionFilter.allowedIDs(in: rootComponents, regions: regionTokens)
        return disabledNames.filter { allowed.contains($0) }
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
        if regionTokens != nil {
            let allowed = allowedNodes()
            let allOn = allowed.allSatisfy { !isUserOff($0) }
            let keys = allowed.flatMap { [$0.id, $0.name] }
            setEnabled(!allOn, keys: keys)
            refreshTreeStates()
            return
        }
        let nodes = rootComponents.flatMap(ComponentTree.collect)
        let allOn = nodes.allSatisfy { !isOff($0) }
        let enabled = !allOn
        guard onSetAll(enabled) else {
            refreshTreeStates()
            return
        }
        setEnabled(enabled, nodes: nodes)
        refreshTreeStates()
    }

    @objc private func componentClicked(_ sender: NSButton) {
        let key = sender.identifier?.rawValue ?? sender.title
        if toggleRegion(key) {
            refreshTreeStates()
            return
        }
        guard onToggleComponent(key) else {
            refreshTreeStates()
            return
        }
        let node = ComponentTree.find(key, in: rootComponents)
        let nodes = node.map(ComponentTree.collect) ?? []
        let allOn = nodes.isEmpty ? !disabledNames.contains(key) : nodes.allSatisfy { !isOff($0) }
        if nodes.isEmpty {
            setEnabled(!allOn, keys: [key])
        } else {
            setEnabled(!allOn, nodes: nodes)
        }
        refreshTreeStates()
    }

    private func setEnabled(_ enabled: Bool, nodes: [ComponentStatus]) {
        if enabled {
            setEnabled(true, keys: nodes.flatMap { [$0.id, $0.name] })
        } else {
            setEnabled(false, keys: nodes.map(\.id))
        }
    }

    private func setEnabled(_ enabled: Bool, keys: [String]) {
        if enabled {
            keys.forEach { disabledNames.remove($0) }
        } else {
            disabledNames.formUnion(keys)
        }
    }

    private func isOff(_ component: ComponentStatus) -> Bool {
        if let regionTokens,
           !RegionFilter.allowedIDs(in: rootComponents, regions: regionTokens).contains(component.id) {
            return true
        }
        return isUserOff(component)
    }

    private func isUserOff(_ component: ComponentStatus) -> Bool {
        disabledNames.contains(component.id) || disabledNames.contains(component.name)
    }

    private func allowedNodes() -> [ComponentStatus] {
        guard let regionTokens else { return rootComponents.flatMap(ComponentTree.collect) }
        let allowed = RegionFilter.allowedIDs(in: rootComponents, regions: regionTokens)
        return rootComponents.flatMap(ComponentTree.collect).filter { allowed.contains($0.id) }
    }

    /// Clicking a top-level row adds or removes that region. Child rows keep the mute list.
    private func toggleRegion(_ key: String) -> Bool {
        guard regionTokens != nil else { return false }
        guard let node = rootComponents.first(where: { $0.id == key || $0.name == key }) else {
            return false
        }
        if RegionFilter.matches(node, regions: regionTokens!) {
            regionTokens!.removeAll { token in
                node.name.range(of: token, options: .caseInsensitive) != nil
                    || node.id.range(of: token, options: .caseInsensitive) != nil
            }
        } else {
            regionTokens!.append(node.name)
        }
        return true
    }

    private func refreshTreeStates() {
        var keys = disabledNames
        if let regionTokens {
            let allowed = RegionFilter.allowedIDs(in: rootComponents, regions: regionTokens)
            for node in rootComponents.flatMap(ComponentTree.collect) where !allowed.contains(node.id) {
                keys.insert(node.id)
            }
        }
        let index = ComponentSelectionIndex(
            components: rootComponents,
            disabledKeys: keys
        )
        for (id, button) in checkboxes {
            guard let summary = index[id] else { continue }
            applyState(button, summary: summary)
        }
        if let allCheckbox {
            applyState(allCheckbox, summary: index.all)
        }
    }

    private func applyState(_ button: NSButton, summary: ComponentSelectionSummary) {
        let mixed = summary.enabledCount > 0 && summary.enabledCount < summary.totalCount
        if mixed {
            button.allowsMixedState = true
            button.state = .mixed
            return
        }
        if button.state == .mixed {
            button.state = .off
        }
        button.allowsMixedState = false
        button.state = summary.enabledCount == 0 ? .off : .on
    }
}
