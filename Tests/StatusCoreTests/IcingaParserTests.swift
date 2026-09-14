import XCTest
@testable import StatusCore

final class IcingaParserTests: XCTestCase {
    private let sourceURL = URL(string: "https://tg_alert_monitor:s3cret@icinga.example:5665/v1")!

    func testHostAndServiceTreeUsesHostCheckChild() throws {
        let hosts = Data("""
        {"results":[{
          "name":"web-1",
          "type":"Host",
          "attrs":{
            "name":"web-1",
            "display_name":"Web 1",
            "state":1.0,
            "downtime_depth":0.0
          }
        }]}
        """.utf8)
        let services = Data("""
        {"results":[{
          "name":"web-1!http",
          "type":"Service",
          "attrs":{
            "name":"http",
            "display_name":"HTTP",
            "host_name":"web-1",
            "__name":"web-1!http",
            "state":0.0,
            "downtime_depth":0.0
          }
        }]}
        """.utf8)
        let snap = try IcingaParser.parse(hosts: hosts, services: services, sourceURL: sourceURL)
        XCTAssertEqual(snap.provider, .icinga)
        XCTAssertEqual(snap.name, "icinga.example")
        XCTAssertEqual(snap.url, URL(string: "https://icinga.example:5665/v1"))
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.incidents, [])
        XCTAssertFalse(snap.isUnreachable)
        XCTAssertEqual(snap.components.count, 1)

        let host = snap.components[0]
        XCTAssertEqual(host.id, "web-1")
        XCTAssertEqual(host.name, "Web 1")
        XCTAssertTrue(host.isGroup)
        XCTAssertEqual(host.children.count, 2)
        XCTAssertEqual(host.children[0].id, "web-1!__host")
        XCTAssertEqual(host.children[0].name, "Host")
        XCTAssertFalse(host.children[0].isGroup)
        XCTAssertEqual(host.children[0].severity, .red)
        XCTAssertEqual(host.children[0].statusText, "Major outage")
        XCTAssertEqual(host.children[1].id, "web-1!http")
        XCTAssertEqual(host.children[1].name, "HTTP")
        XCTAssertEqual(host.children[1].severity, .green)
        XCTAssertEqual(host.children[1].statusText, "Operational")
    }

    func testEmptyResultsAreGreenIcingaPage() throws {
        let empty = Data("{\"results\":[]}".utf8)
        let snap = try IcingaParser.parse(hosts: empty, services: empty, sourceURL: sourceURL)
        XCTAssertEqual(snap.provider, .icinga)
        XCTAssertEqual(snap.name, "icinga.example")
        XCTAssertEqual(snap.overall, .green)
        XCTAssertTrue(snap.components.isEmpty)
        XCTAssertEqual(snap.incidents, [])
        XCTAssertFalse(snap.isUnreachable)
    }

    func testWarningUnknownUnreachableAndDowntime() throws {
        let hosts = Data("""
        {"results":[
          {"attrs":{"name":"a","display_name":"A","state":0.0,"downtime_depth":0.0}},
          {"attrs":{"name":"b","display_name":"B","state":2.0,"downtime_depth":0.0}},
          {"attrs":{"name":"c","display_name":"C","state":0.0,"downtime_depth":1.0}}
        ]}
        """.utf8)
        let services = Data("""
        {"results":[
          {"attrs":{"name":"warn","display_name":"Warn","host_name":"a","__name":"a!warn","state":1.0,"downtime_depth":0.0}},
          {"attrs":{"name":"unknown","display_name":"Unk","host_name":"a","__name":"a!unknown","state":3.0,"downtime_depth":0.0}},
          {"attrs":{"name":"crit","display_name":"Crit","host_name":"a","__name":"a!crit","state":2.0,"downtime_depth":2.0}}
        ]}
        """.utf8)
        let snap = try IcingaParser.parse(hosts: hosts, services: services, sourceURL: sourceURL)
        XCTAssertEqual(snap.components.map(\.id), ["a", "b", "c"])

        let a = snap.components[0]
        XCTAssertEqual(a.children[0].statusText, "Operational")
        XCTAssertEqual(child(a, "a!warn")?.severity, .yellow)
        XCTAssertEqual(child(a, "a!warn")?.statusText, "Degraded")
        XCTAssertEqual(child(a, "a!unknown")?.severity, .yellow)
        XCTAssertEqual(child(a, "a!unknown")?.statusText, "Unknown")
        XCTAssertEqual(child(a, "a!crit")?.severity, .yellow)
        XCTAssertEqual(child(a, "a!crit")?.statusText, "Maintenance")

        XCTAssertEqual(snap.components[1].children[0].severity, .yellow)
        XCTAssertEqual(snap.components[1].children[0].statusText, "Unreachable")
        XCTAssertEqual(snap.components[2].children[0].severity, .yellow)
        XCTAssertEqual(snap.components[2].children[0].statusText, "Maintenance")
        XCTAssertEqual(snap.overall, .yellow)
    }

    func testRejectsNonIcingaJSON() {
        XCTAssertThrowsError(
            try IcingaParser.parse(
                hosts: Data("{}".utf8),
                services: Data("{\"results\":[]}".utf8),
                sourceURL: sourceURL
            )
        )
    }

    private func child(_ host: ComponentStatus, _ id: String) -> ComponentStatus? {
        host.children.first { $0.id == id }
    }
}
