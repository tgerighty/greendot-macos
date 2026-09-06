import Foundation

public struct Toast: Equatable, Sendable {
    public var pageID: UUID
    public var pageName: String
    public var body: String
    public var severity: Severity

    public init(pageID: UUID, pageName: String, body: String, severity: Severity) {
        self.pageID = pageID
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
        pageName: String,
        pageID: UUID
    ) -> Toast? {
        guard notificationsEnabled else { return nil }
        guard let previous else { return nil }
        guard previous.overall != current.overall else { return nil }
        return Toast(
            pageID: pageID,
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

/// Collapses a poll where every page goes grey at once into one network toast,
/// and a poll that brings them back into one recovery toast.
public enum NetworkToast {
    public static let pageID = UUID(uuidString: "6E657477-6F72-6B00-0000-000000000000")!

    public static let lost = Toast(
        pageID: pageID,
        pageName: "Network",
        body: "Greendot has no network connectivity",
        severity: .grey
    )

    public static let regained = Toast(
        pageID: pageID,
        pageName: "Network",
        body: "Greendot has regained network connectivity",
        severity: .green
    )

    public static func apply(_ toasts: [Toast], previous: [WatchedPage], current: [WatchedPage]) -> [Toast] {
        let wasOffline = allUnreachable(previous)
        let isOffline = allUnreachable(current)
        guard wasOffline != isOffline, current.contains(where: \.notificationsEnabled) else { return toasts }
        if isOffline { return [lost] }
        return [regained] + toasts.filter { $0.severity != .green }
    }

    /// One page down cannot tell a site outage from a network outage, so two or more are required.
    private static func allUnreachable(_ pages: [WatchedPage]) -> Bool {
        pages.count > 1 && pages.allSatisfy { $0.snapshot?.isUnreachable == true }
    }
}
