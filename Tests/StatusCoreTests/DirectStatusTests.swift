import XCTest
@testable import StatusCore
import TestSupport

final class DirectStatusParserTests: XCTestCase {
    func testConcurNormalServiceIsGreen() throws {
        let data = Data("""
        {"data":{"Expense":{"Service":"Expense","Current Status":{"status":"normal","incidents":[]}}}}
        """.utf8)
        let group = try ConcurParser.serviceGroup(data: data, datacenter: "us2")
        XCTAssertEqual(group.name, "US2")
        XCTAssertEqual(group.children.map(\.name), ["Expense"])
        XCTAssertEqual(group.children[0].severity, .green)
    }

    func testConcurDisruptionIsRed() throws {
        let data = Data("""
        {"data":{"Travel":{"Service":"Travel","Current Status":{"status":"disruption","incidents":[{"id":"1"}]}}}}
        """.utf8)
        let group = try ConcurParser.serviceGroup(data: data, datacenter: "eu2")
        XCTAssertEqual(group.children[0].severity, .red)
        XCTAssertEqual(group.children[0].statusText, "Disruption")
    }

    func testAdobeClosedHistoryIsGreen() throws {
        let data = Data("""
        {"incidentEvent":{"incidents":{"1":{"products":{"9":{"id":"9","name":"Acrobat",\
        "history":{"10":{"status":"Closed","severity":"Major"}}}}}}}}
        """.utf8)
        let snap = try AdobeParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.adobe.com")!
        )
        XCTAssertEqual(snap.provider, .adobe)
        XCTAssertEqual(snap.name, "Adobe")
        XCTAssertEqual(snap.overall, .green)
        XCTAssertTrue(snap.components.isEmpty)
    }

    func testAdobeOpenMajorIncidentIsRed() throws {
        let data = Data("""
        {"incidentEvent":{"incidents":{"1":{"products":{"9":{"id":"9","name":"Acrobat","history":{
          "10":{"status":"Closed","severity":"Major"},
          "20":{"status":"Open","severity":"Major"}
        }}}}}}}
        """.utf8)
        let snap = try AdobeParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.adobe.com")!
        )
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components.map(\.name), ["Acrobat"])
    }

    func testAzureHealthyGeographyIsGreen() throws {
        let data = Data("""
        {"status":{"health":"healthy","message":"Everything is looking good"},
         "services":[{"id":"Repos","geographies":[{"id":"EU","name":"Europe","health":"healthy"}]}]}
        """.utf8)
        let snap = try AzureDevOpsParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.dev.azure.com")!
        )
        XCTAssertEqual(snap.provider, .azuredevops)
        XCTAssertEqual(snap.name, "Azure DevOps")
        XCTAssertEqual(snap.overall, .green)
        XCTAssertEqual(snap.components[0].name, "Repos")
        XCTAssertEqual(snap.components[0].children[0].name, "Europe")
    }

    func testAzureUnhealthyGeographyIsRed() throws {
        let data = Data("""
        {"status":{"health":"healthy","message":"ok"},
         "services":[{"id":"Pipelines","geographies":[{"id":"US","name":"United States","health":"unhealthy"}]}]}
        """.utf8)
        let snap = try AzureDevOpsParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.dev.azure.com")!
        )
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components[0].children[0].severity, .red)
    }

    func testN8nDangerMonitorIsRed() throws {
        let data = Data("""
        {"status":"ok","data":[{"name":"n8n.cloud","statusClass":"danger"},{"name":"API","statusClass":"success"}]}
        """.utf8)
        let snap = try N8nParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.n8n.cloud")!
        )
        XCTAssertEqual(snap.provider, .n8n)
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components.map(\.name), ["n8n.cloud", "API"])
    }

    func testZscalerNoneBannerIsGreen() throws {
        let data = Data("""
        {"data":{"severity":"none","title":"All Zscaler Services are functional","description":"online"}}
        """.utf8)
        let snap = try ZscalerParser.parse(
            data: data,
            sourceURL: URL(string: "https://trust.zscaler.com")!
        )
        XCTAssertEqual(snap.provider, .zscaler)
        XCTAssertEqual(snap.name, "Zscaler")
        XCTAssertEqual(snap.overall, .green)
        XCTAssertTrue(snap.components.isEmpty)
    }

    func testZscalerDisruptionBannerIsRed() throws {
        let data = Data("""
        {"data":{"severity":"disruption","title":"ZIA disruption","description":"investigating"}}
        """.utf8)
        let snap = try ZscalerParser.parse(
            data: data,
            sourceURL: URL(string: "https://trust.zscaler.com")!
        )
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components.map(\.name), ["ZIA disruption"])
    }
}

final class DirectStatusProbeTests: XCTestCase {
    func testConcurLandingReadsEachDatacenter() async throws {
        let body = Data("""
        {"data":{"Expense":{"Service":"Expense","Current Status":{"status":"normal","incidents":[]}}}}
        """.utf8)
        var inner = MapHTTPClient()
        for datacenter in ["us", "us2", "eu2", "apj1", "usg"] {
            let url = "https://open.concur.com/api/v2/status_history?data_center=\(datacenter)"
            inner.byURL[url] = (body, 200)
        }
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://open.concur.com")!,
            client: inner
        )
        XCTAssertEqual(snap.provider, .concur)
        XCTAssertEqual(snap.name, "SAP Concur")
        XCTAssertEqual(snap.overall, .green)
        XCTAssertEqual(snap.components.map(\.name), ["US", "US2", "EU2", "APJ1", "US Government"])
    }

    func testAdobeLandingReadsStatusEvents() async throws {
        let body = Data(#"{"incidentEvent":{"incidents":{}}}"#.utf8)
        var inner = MapHTTPClient()
        inner.byURL["https://data.status.adobe.com/adobestatus/StatusEvents"] = (body, 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.adobe.com/")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .adobe)
        XCTAssertEqual(recording.requested.map(\.absoluteString), [
            "https://data.status.adobe.com/adobestatus/StatusEvents"
        ])
    }

    func testAzureDevOpsLandingReadsHealth() async throws {
        let body = Data(#"{"status":{"health":"healthy","message":"ok"},"services":[]}"#.utf8)
        var inner = MapHTTPClient()
        inner.byURL["https://status.dev.azure.com/_apis/status/health"] = (body, 200)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.dev.azure.com")!,
            client: inner
        )
        XCTAssertEqual(snap.provider, .azuredevops)
        XCTAssertEqual(snap.overall, .green)
    }

    func testN8nLandingReadsMonitorListFromThePage() async throws {
        let html = Data(#"<html>https://status.n8n.cloud/api/getMonitorList/abc123</html>"#.utf8)
        let json = Data(#"{"status":"ok","data":[{"name":"API","statusClass":"success"}]}"#.utf8)
        var inner = MapHTTPClient()
        inner.byURL["https://status.n8n.cloud"] = (html, 200)
        inner.byURL["https://status.n8n.cloud/api/getMonitorList/abc123"] = (json, 200)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.n8n.cloud/")!,
            client: inner
        )
        XCTAssertEqual(snap.provider, .n8n)
        XCTAssertEqual(snap.components.map(\.name), ["API"])
    }

    func testZscalerLandingReadsBanner() async throws {
        let body = Data(#"{"data":{"severity":"none","title":"ok","description":"ok"}}"#.utf8)
        var inner = MapHTTPClient()
        inner.byURL["https://trust.zscaler.com/api/cloud-banner"] = (body, 200)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://trust.zscaler.com/")!,
            client: inner
        )
        XCTAssertEqual(snap.provider, .zscaler)
        XCTAssertEqual(snap.overall, .green)
    }

    func testQlikPublicPageReadsEmbeddedStatuspage() async throws {
        let json = Data("""
        {"page":{"name":"Qlik Cloud Status"},"status":{"indicator":"none"},"components":[],"incidents":[]}
        """.utf8)
        var inner = MapHTTPClient()
        inner.byURL["https://statusa-an5d9w.qlikcloud.com/api/v2/summary.json"] = (json, 200)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.qlikcloud.com")!,
            client: inner
        )
        XCTAssertEqual(snap.provider, .statuspage)
        XCTAssertEqual(snap.name, "Qlik Cloud Status")
        XCTAssertEqual(snap.url, URL(string: "https://status.qlikcloud.com")!)
    }
}
