import StatusCore

struct ComponentSelectionSummary: Equatable {
    let enabledCount: Int
    let totalCount: Int
}

struct ComponentSelectionIndex {
    let all: ComponentSelectionSummary
    private let summariesByID: [String: ComponentSelectionSummary]

    init(components: [ComponentStatus], disabledKeys: Set<String>) {
        var summariesByID: [String: ComponentSelectionSummary] = [:]
        var enabledCount = 0
        var totalCount = 0
        for component in components {
            let summary = Self.summarize(
                component,
                disabledKeys: disabledKeys,
                summariesByID: &summariesByID
            )
            enabledCount += summary.enabledCount
            totalCount += summary.totalCount
        }
        self.summariesByID = summariesByID
        self.all = ComponentSelectionSummary(enabledCount: enabledCount, totalCount: totalCount)
    }

    subscript(id: String) -> ComponentSelectionSummary? {
        summariesByID[id]
    }

    private static func summarize(
        _ component: ComponentStatus,
        disabledKeys: Set<String>,
        summariesByID: inout [String: ComponentSelectionSummary]
    ) -> ComponentSelectionSummary {
        var enabledCount = disabledKeys.contains(component.id) || disabledKeys.contains(component.name) ? 0 : 1
        var totalCount = 1
        for child in component.children {
            let childSummary = summarize(
                child,
                disabledKeys: disabledKeys,
                summariesByID: &summariesByID
            )
            enabledCount += childSummary.enabledCount
            totalCount += childSummary.totalCount
        }
        let summary = ComponentSelectionSummary(enabledCount: enabledCount, totalCount: totalCount)
        summariesByID[component.id] = summary
        return summary
    }
}
