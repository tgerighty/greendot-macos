import XCTest
@testable import StatusCore

final class AwsParserTests: XCTestCase {
    private let sourceURL = URL(string: "https://health.aws.amazon.com/health/status")!

    func testTwoEventsBuildsTreeAndOverallRed() throws {
        let data = Data("""
        [{"arn":"arn:aws:health:me-central-1::event/A","region_name":"UAE","status":"3","service_name":"Multiple services","summary":"Increased Error Rates","impacted_services":{"s3-me-central-1":{"service_name":"Amazon S3","current":"3"}}},{"arn":"arn:aws:health:me-south-1::event/B","region_name":"Bahrain","status":"1","service_name":"Multiple services","impacted_services":{}}]
        """.utf8)
        let snap = try AwsParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.provider, .aws)
        XCTAssertEqual(snap.name, "AWS")
        XCTAssertEqual(snap.url, sourceURL)
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.incidents, [])
        XCTAssertFalse(snap.isUnreachable)
        XCTAssertEqual(snap.components.count, 2)

        let first = snap.components[0]
        XCTAssertEqual(first.id, "arn:aws:health:me-central-1::event/A")
        XCTAssertEqual(first.name, "Multiple services (UAE)")
        XCTAssertTrue(first.isGroup)
        XCTAssertEqual(first.severity, .red)
        XCTAssertEqual(first.statusText, "Major outage")
        XCTAssertEqual(first.children.count, 1)
        XCTAssertEqual(first.children[0].id, "s3-me-central-1")
        XCTAssertEqual(first.children[0].name, "Amazon S3")
        XCTAssertFalse(first.children[0].isGroup)
        XCTAssertEqual(first.children[0].severity, .red)
        XCTAssertEqual(first.children[0].statusText, "Major outage")

        let second = snap.components[1]
        XCTAssertEqual(second.id, "arn:aws:health:me-south-1::event/B")
        XCTAssertEqual(second.name, "Multiple services (Bahrain)")
        XCTAssertTrue(second.isGroup)
        XCTAssertTrue(second.children.isEmpty)
        XCTAssertEqual(second.severity, .yellow)
        XCTAssertEqual(second.statusText, "Degraded")
    }

    func testEmptyArrayIsGreenAWSPage() throws {
        let snap = try AwsParser.parse(data: Data("[]".utf8), sourceURL: sourceURL)
        XCTAssertEqual(snap.provider, .aws)
        XCTAssertEqual(snap.name, "AWS")
        XCTAssertEqual(snap.url, sourceURL)
        XCTAssertEqual(snap.overall, .green)
        XCTAssertTrue(snap.components.isEmpty)
        XCTAssertEqual(snap.incidents, [])
        XCTAssertFalse(snap.isUnreachable)
    }

    func testNumericStatusIsRed() throws {
        let data = Data("""
        [{"arn":"arn:aws:health:us-east-1::event/N","region_name":"N. Virginia","status":3,"service_name":"Amazon EC2","impacted_services":{}}]
        """.utf8)
        let snap = try AwsParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.components[0].severity, .red)
        XCTAssertEqual(snap.components[0].statusText, "Major outage")
        XCTAssertEqual(snap.overall, .red)
    }

    func testEventWithoutImpactedServicesIsGroupLeaf() throws {
        let data = Data("""
        [{"arn":"arn:aws:health:us-east-1::event/N","status":"3","service_name":"Amazon EC2"}]
        """.utf8)
        let snap = try AwsParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.components[0].name, "Amazon EC2")
        XCTAssertTrue(snap.components[0].isGroup)
        XCTAssertTrue(snap.components[0].children.isEmpty)
        XCTAssertEqual(snap.components[0].severity, .red)
        XCTAssertEqual(snap.overall, .red)
    }

    func testMissingChildCurrentIsYellow() throws {
        let data = Data("""
        [{"arn":"arn:a","service_name":"Multiple services","region_name":"UAE","status":"0","impacted_services":{"s3":{"service_name":"Amazon S3"}}}]
        """.utf8)
        let snap = try AwsParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.components[0].children[0].severity, .yellow)
        XCTAssertEqual(snap.components[0].children[0].statusText, "Degraded")
        XCTAssertEqual(snap.overall, .yellow)
    }

    func testEventWithoutArnIsSkipped() throws {
        let data = Data("""
        [{"service_name":"Ghost","status":"3"},{"arn":"arn:keep","service_name":"Kept","status":"0"}]
        """.utf8)
        let snap = try AwsParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.components.map(\.id), ["arn:keep"])
        XCTAssertEqual(snap.components.map(\.name), ["Kept"])
        XCTAssertEqual(snap.overall, .green)
    }

    func testUTF16BEWithBOMParses() throws {
        let json = """
        [{"arn":"arn:a","service_name":"Amazon S3","region_name":"UAE","status":"0"}]
        """
        var data = Data([0xFE, 0xFF])
        data.append(contentsOf: json.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] })
        let snap = try AwsParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.provider, .aws)
        XCTAssertEqual(snap.components[0].name, "Amazon S3 (UAE)")
        XCTAssertEqual(snap.overall, .green)
    }

    func testObjectJSONIsNotThisProvider() {
        XCTAssertThrowsError(
            try AwsParser.parse(data: Data("{}".utf8), sourceURL: sourceURL)
        ) { error in
            XCTAssertEqual(error as? ParserError, .notThisProvider)
        }
    }
}
