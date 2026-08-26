import Foundation
import StatusCore

public enum BenchmarkFixtures {
    public static let delayNanoseconds: UInt64 = 80_000_000

    public static func greenPage(
        host: String,
        name: String,
        provider: StatusProvider
    ) -> WatchedPage {
        let url = URL(string: "https://\(host)")!
        return WatchedPage(
            url: url,
            name: name,
            snapshot: PageSnapshot(
                name: name,
                url: url,
                provider: provider,
                overall: .green,
                components: [ComponentStatus(name: "API", severity: .green, statusText: "Operational")],
                incidents: [],
                isUnreachable: false
            )
        )
    }
}

public extension Duration {
    var milliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }
}
