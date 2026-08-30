import Foundation
@testable import StatusCore
import TestSupport
import XCTest

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

struct MenuMetrics {
    var uncachedBuildMs: Double
    var cachedBuildMs: Double
    var uniqueCount: Int
}

struct RemainingMetrics {
    var statuspalGets: Int
    var regexCompiles: Int
    var secondParseCount: Int
    var pulseWhenReachable: Int
}

struct BenchmarkRunMetrics {
    let parse: ParseMetrics
    let poll: PollMetrics
    let menu: MenuMetrics
    let componentPicker80: Double
    let componentPicker160: Double
    let displaySeverity: Double
    let iconElapsedMs: Double
    let iconUniqueCount: Int
    let storeSaveMs: Double
    let unchangedWrites: Int
    let remaining: RemainingMetrics
}

extension PerformanceHarnessTests {
    func benchmarkLines(_ metrics: BenchmarkRunMetrics) -> [String] {
        [
            "BENCH parse_statuspage_ms=\(fmt(metrics.parse.statuspage))",
            "BENCH parse_instatus_ms=\(fmt(metrics.parse.instatus))",
            "BENCH parse_statuspal_ms=\(fmt(metrics.parse.statuspal))",
            "BENCH pollAll_3page_delay_ms=\(fmt(metrics.poll.elapsedMs))",
            "BENCH pollAll_3page_delay_expected_sequential_ms=\(fmt(3 * Self.delayMs))",
            "BENCH pollAll_3page_get_count=\(metrics.poll.getCount)",
            "BENCH pollAll_mixed_get_count=\(metrics.poll.mixedGetCount)",
            "BENCH menu_build_ms=\(fmt(metrics.menu.uncachedBuildMs))",
            "BENCH menu_build_cached_ms=\(fmt(metrics.menu.cachedBuildMs))",
            "BENCH component_picker_local_nested_80_clicks_20_ms=\(fmt(metrics.componentPicker80))",
            "BENCH component_picker_local_nested_160_clicks_20_ms=\(fmt(metrics.componentPicker160))",
            "BENCH display_severity_840_components_reads_500_ms=\(fmt(metrics.displaySeverity))",
            "BENCH status_dot_ms=\(fmt(metrics.iconElapsedMs))",
            "BENCH status_dot_unique_images=\(metrics.iconUniqueCount)",
            "BENCH store_save_ms=\(fmt(metrics.storeSaveMs))",
            "BENCH pollAll_unchanged_config_rewrites=\(metrics.unchangedWrites)",
            "BENCH statuspal_first_probe_gets=\(metrics.remaining.statuspalGets)",
            "BENCH menu_unique_objects=\(metrics.menu.uniqueCount)",
            "BENCH statuspal_regex_compiles=\(metrics.remaining.regexCompiles)",
            "BENCH poll_second_parse_count=\(metrics.remaining.secondParseCount)",
            "BENCH pulse_refresh_when_reachable=\(metrics.remaining.pulseWhenReachable)"
        ]
    }

    func assertBenchmarkMetrics(_ metrics: BenchmarkRunMetrics) {
        XCTAssertGreaterThan(metrics.parse.statuspage, 0)
        XCTAssertGreaterThan(metrics.poll.elapsedMs, 0)
        XCTAssertGreaterThan(metrics.menu.uncachedBuildMs, 0)
        XCTAssertGreaterThan(metrics.menu.cachedBuildMs, 0)
        XCTAssertGreaterThan(metrics.componentPicker80, 0)
        XCTAssertGreaterThan(metrics.componentPicker160, 0)
        XCTAssertGreaterThan(metrics.displaySeverity, 0)
        XCTAssertEqual(metrics.poll.getCount, 3, "Known-provider poll must use one GET per page")
        XCTAssertEqual(metrics.poll.mixedGetCount, 3, "Mixed-provider poll must use one GET per page")
        XCTAssertEqual(metrics.menu.uniqueCount, 1, "Repeated cached builds must reuse one menu")
        XCTAssertGreaterThan(metrics.iconElapsedMs, 0)
        XCTAssertEqual(metrics.iconUniqueCount, 4, "Status-dot cache must reuse one image per severity")
        XCTAssertEqual(metrics.unchangedWrites, 0, "Unchanged polls must not rewrite configuration")
        XCTAssertEqual(metrics.remaining.statuspalGets, 3, "Known Statuspal host must skip HTML discovery")
        XCTAssertEqual(metrics.remaining.regexCompiles, 1, "Statuspal regex must be compiled once")
        XCTAssertEqual(metrics.remaining.secondParseCount, 0, "Unchanged response must not be parsed twice")
        XCTAssertEqual(metrics.remaining.pulseWhenReachable, 0, "Reachable pages must not refresh pulse icon")
    }

    func elapsedMs(iterations: Int, _ body: () throws -> Void) -> Double {
        do {
            let start = ContinuousClock.now
            for _ in 0..<iterations {
                try body()
            }
            return start.duration(to: .now).milliseconds
        } catch {
            XCTFail("harness body failed: \(error)")
            return -1
        }
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
