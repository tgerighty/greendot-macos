import Foundation

public enum GreyPulse {
    public static let interval: TimeInterval = 30
    public static let length: TimeInterval = 1

    /// Flash grey for `length` seconds every `interval` when some page is
    /// unreachable and the persistent bar colour is not already grey.
    public static func displayedSeverity(
        persistent: Severity,
        hasUnreachable: Bool,
        now: Date
    ) -> Severity {
        if persistent == .grey { return .grey }
        guard hasUnreachable, interval > 0 else { return persistent }
        let phase = now.timeIntervalSince1970.truncatingRemainder(dividingBy: interval)
        if phase >= 0 && phase < length { return .grey }
        return persistent
    }
}
