import Foundation

public struct Toast: Equatable, Sendable {
    public var pageID: UUID
    public var pageName: String
    public var body: String
    public var severity: Severity
    /// True when the page was already unhealthy. An open panel takes the new colour, and a page
    /// the user has already cleared stays cleared. One unhealthy spell announces itself once.
    public var silent: Bool

    public init(pageID: UUID, pageName: String, body: String, severity: Severity, silent: Bool = false) {
        self.pageID = pageID
        self.pageName = pageName
        self.body = body
        self.severity = severity
        self.silent = silent
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
            severity: current.overall,
            silent: previous.overall != .green && current.overall != .green
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

    /// `showingLost` carries the network state across polls. Without it a page removed or added
    /// during the outage would strand the lost toast on screen with nothing left to clear it.
    /// `systemOffline` is true when the system itself reports no route. One page is then enough
    /// to claim an outage, because a site outage is no longer an alternative.
    public static func apply(
        _ toasts: [Toast],
        pages: [WatchedPage],
        showingLost: inout Bool,
        systemOffline: Bool = false
    ) -> [Toast] {
        if showingLost {
            // The claim stands only while the pages still support it. Withdraw it as soon as they
            // do not, including when too few are left to claim an outage at all.
            guard !allUnreachable(pages, systemOffline: systemOffline) else { return [] }
            showingLost = false
            // The lost toast stood in for every page, so a page that is still not green needs its own toast now.
            let stillNotGreen = pages.filter { $0.notificationsEnabled && $0.displaySeverity != .green }
            // Announce a recovery only when a page answered. Withdrawing the claim because the pages
            // no longer support it is not a recovery, and the app clears the toast on the same poll.
            guard pages.contains(where: { $0.snapshot?.isUnreachable == false }) else {
                return stillNotGreen.map(pageToast)
            }
            return [regained] + stillNotGreen.map(pageToast)
        }
        guard allUnreachable(pages, systemOffline: systemOffline),
              pages.contains(where: \.notificationsEnabled) else { return toasts }
        showingLost = true
        return [lost]
    }

    /// The page was unhealthy under the lost toast and still is, so its spell never ended.
    private static func pageToast(_ page: WatchedPage) -> Toast {
        Toast(
            pageID: page.id,
            pageName: page.name,
            body: page.displaySeverity.displayName,
            severity: page.displaySeverity,
            silent: true
        )
    }

    /// One page down cannot tell a site outage from a network outage, so two or more are required
    /// unless the system has already said there is no route.
    private static func allUnreachable(_ pages: [WatchedPage], systemOffline: Bool) -> Bool {
        guard !pages.isEmpty else { return false }
        guard pages.allSatisfy({ $0.snapshot?.isUnreachable == true }) else { return false }
        return systemOffline || pages.count > 1
    }
}
