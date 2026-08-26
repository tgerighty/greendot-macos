@testable import StatusCore

struct ParseMetrics {
    let statuspage: Double
    let instatus: Double
    let statuspal: Double
}

struct PollMetrics {
    let elapsedMs: Double
    let getCount: Int
    let mixedGetCount: Int
}

struct PollPageMetrics {
    let elapsedMs: Double
    let toasts: [Toast]
    let snapshots: [PageSnapshot?]
}
