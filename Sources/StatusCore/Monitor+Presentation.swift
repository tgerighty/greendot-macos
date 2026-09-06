import Foundation

extension Monitor {
    public func displayedSeverity(at now: Date) -> Severity {
        let persistent: Severity
        let hasUnreachable: Bool
        (persistent, hasUnreachable) = withStateLock {
            (
                Aggregator.fromSeverities(config.pages.map(\.displaySeverity)),
                config.pages.contains { $0.snapshot?.isUnreachable == true }
            )
        }
        return GreyPulse.displayedSeverity(persistent: persistent, hasUnreachable: hasUnreachable, now: now)
    }
}
