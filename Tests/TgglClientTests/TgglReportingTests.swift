import XCTest
@testable import TgglClient

final class TgglReportingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    private func makeClient(reporting: Bool = true, appName: String? = nil) -> TgglClient {
        TgglClient(
            apiKey: "test-key",
            context: ["userId": "u1"],
            options: TgglOptions(
                baseUrls: [URL(string: "https://proxy.example.com")!],
                fallbackToTgglApi: false,
                maxRetries: 0,
                reporting: reporting,
                reportingInterval: 3600, // flushed manually in tests
                appName: appName,
                cache: .disabled,
                session: MockURLProtocol.session()
            )
        )
    }

    private func reportedFlags(_ request: MockURLProtocol.RecordedRequest) throws -> (id: String?, flags: [String: [[String: Any]]]) {
        let body = try XCTUnwrap(request.jsonBody as? [String: Any])
        let clients = try XCTUnwrap(body["clients"] as? [[String: Any]])
        XCTAssertEqual(clients.count, 1)
        let flags = try XCTUnwrap(clients[0]["flags"] as? [String: [[String: Any]]])
        return (clients[0]["id"] as? String, flags)
    }

    func testReportPayloadFollowsTheApiSchema() async throws {
        MockURLProtocol.setHandler { request in
            request.path.hasSuffix("/report") ? .json(#"{"success":true}"#) : .json(TgglClientTests.flagsJSON)
        }
        let client = makeClient(appName: "MyApp")
        await client.refetch()

        _ = client.get("bool-flag", default: false)
        _ = client.get("bool-flag", default: false)
        _ = client.get("unknown-flag", default: "fallback")
        _ = client.get("null-flag", default: true)
        await client.flushReporting()

        let request = try XCTUnwrap(MockURLProtocol.requests(path: "/report").first)
        let (id, flags) = try reportedFlags(request)
        XCTAssertEqual(id, "swift-client:\(TgglClient.sdkVersion)/TgglClient/MyApp")

        let boolEntry = try XCTUnwrap(flags["bool-flag"]?.first)
        XCTAssertEqual(boolEntry["value"] as? Bool, true)
        XCTAssertEqual(boolEntry["default"] as? Bool, false)
        XCTAssertEqual(boolEntry["count"] as? Int, 2)

        // Inactive / unknown flag: `value` must be omitted.
        let unknownEntry = try XCTUnwrap(flags["unknown-flag"]?.first)
        XCTAssertNil(unknownEntry["value"])
        XCTAssertEqual(unknownEntry["default"] as? String, "fallback")
        XCTAssertEqual(unknownEntry["count"] as? Int, 1)

        // Active flag with a null value: `value` is present and null.
        let nullEntry = try XCTUnwrap(flags["null-flag"]?.first)
        XCTAssertTrue(nullEntry["value"] is NSNull)
        XCTAssertEqual(nullEntry["default"] as? Bool, true)

        let apiKey = request.headers.first { $0.key.lowercased() == "x-tggl-api-key" }?.value
        XCTAssertEqual(apiKey, "test-key")
    }

    func testEvaluationsAreKeptWhenReportingFails() async throws {
        let reportCalls = Locked(0)
        MockURLProtocol.setHandler { request in
            guard request.path.hasSuffix("/report") else { return .json(TgglClientTests.flagsJSON) }
            let call = reportCalls.withLock { count -> Int in
                count += 1
                return count
            }
            return call == 1 ? .status(503) : .json(#"{"success":true}"#)
        }
        let client = makeClient()
        await client.refetch()

        _ = client.get("bool-flag", default: false)
        await client.flushReporting()
        _ = client.get("bool-flag", default: false)
        await client.flushReporting()

        let reports = MockURLProtocol.requests(path: "/report")
        XCTAssertEqual(reports.count, 2)
        let (_, flags) = try reportedFlags(reports[1])
        XCTAssertEqual(flags["bool-flag"]?.first?["count"] as? Int, 2)
    }

    func testCloseFlushesPendingEvaluations() async {
        let client = makeClient()
        _ = client.get("my-flag", default: false)
        await client.close()

        XCTAssertEqual(MockURLProtocol.requests(path: "/report").count, 1)
    }

    func testReportingCanBeDisabled() async {
        let client = makeClient(reporting: false)
        _ = client.get("my-flag", default: false)
        await client.flushReporting()
        await client.close()

        XCTAssertTrue(MockURLProtocol.requests(path: "/report").isEmpty)
    }

    func testNothingIsSentWithoutEvaluations() async {
        let client = makeClient()
        await client.flushReporting()

        XCTAssertTrue(MockURLProtocol.requests(path: "/report").isEmpty)
    }
}
