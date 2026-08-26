import Foundation

public struct Toast: Equatable, Sendable {
    public var pageName: String
    public var body: String
    public var severity: Severity

    public init(pageName: String, body: String, severity: Severity) {
        self.pageName = pageName
        self.body = body
        self.severity = severity
    }

    /// Seconds before the toast clears itself. `nil` means the user must click it away.
    public var autoDismissSeconds: TimeInterval? {
        severity == .green ? 6 : nil
    }
}

public enum ToastPolicy {
    public static func toast(
        previous: PageSnapshot?,
        current: PageSnapshot,
        notificationsEnabled: Bool,
        pageName: String
    ) -> Toast? {
        guard notificationsEnabled else { return nil }
        guard let previous else { return nil }
        guard previous.overall != current.overall else { return nil }
        return Toast(
            pageName: pageName,
            body: Self.body(for: current),
            severity: current.overall
        )
    }

    private static func body(for snapshot: PageSnapshot) -> String {
        if snapshot.isUnreachable { return "Unreachable" }
        return snapshot.overall.displayName
    }
}
