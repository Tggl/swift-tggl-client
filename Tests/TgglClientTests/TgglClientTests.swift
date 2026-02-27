import XCTest
import Combine
@testable import TgglClient

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol {
    struct Response {
        let statusCode: Int
        let headers: [String: String]?
        let data: Data
    }

    private static var currentResponse: Response?
    private static var requestHandler: ((URLRequest) -> Response?)?
    private static let lock = NSLock()
    static var recordedRequests: [URLRequest] = []

    static func setResponse(_ response: Response?) {
        lock.lock()
        currentResponse = response
        requestHandler = nil
        lock.unlock()
    }

    static func setJSON(_ jsonString: String, statusCode: Int = 200, headers: [String: String] = ["Content-Type": "application/json"]) {
        let data = Data(jsonString.utf8)
        setResponse(Response(statusCode: statusCode, headers: headers, data: data))
    }

    static func setHandler(_ handler: @escaping (URLRequest) -> Response?) {
        lock.lock()
        currentResponse = nil
        requestHandler = handler
        lock.unlock()
    }

    static func clear() {
        lock.lock()
        currentResponse = nil
        requestHandler = nil
        recordedRequests = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client = client else { return }

        Self.lock.lock()
        Self.recordedRequests.append(request)
        let handler = Self.requestHandler
        let fallback = Self.currentResponse
        Self.lock.unlock()

        let url = request.url!
        let resolved = handler?(request) ?? fallback

        if let next = resolved {
            let httpResponse = HTTPURLResponse(url: url, statusCode: next.statusCode, httpVersion: "HTTP/1.1", headerFields: next.headers)!
            client.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: next.data)
            client.urlProtocolDidFinishLoading(self)
        } else {
            let httpResponse = HTTPURLResponse(url: url, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!
            client.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: Data())
            client.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

final class TgglClientTests: XCTestCase {
    override func setUp() async throws {
        let storage = TgglStorage()
        storage.clear()
        MockURLProtocol.clear()
    }

    private func makeMockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    private func waitForFlagsCount(_ client: TgglClient, expected: Int, timeout: TimeInterval = 2.0, pollInterval: TimeInterval = 0.02, file: StaticString = #file, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let flags = await client.getFlags()
            if flags.count == expected {
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        let finalFlags = await client.getFlags()
        XCTFail("Timed out waiting for flags.count == \(expected). Final count: \(finalFlags.count)", file: file, line: line)
    }

    // MARK: - Original test

    func testFlagsAreUpdatedWhenContextChanges() async throws {
        let session = makeMockedSession()

        let initialJSON = """
        [[{"key":"bgColor","type":"string","stringValue":"#ff0000"}]]
        """
        let afterFirstContextJSON = """
        [[{"key":"bgColor","type":"string","stringValue":"#ff0000"},{"key":"eric","type":"string","stringValue":"flag"}]]
        """
        let afterSecondContextJSON = """
        [[{"key":"bgColor","type":"string","stringValue":"#ff0000"}]]
        """

        let client = TgglClient(apiKey: "test_api_key", session: session, maxRetries: 0, reporting: false, initialFetch: false)

        MockURLProtocol.setJSON(initialJSON)
        await client.startPolling(every: 3)

        await waitForFlagsCount(client, expected: 1, timeout: 1.0)
        let flagsAfterStart = await client.getFlags()
        XCTAssertEqual(flagsAfterStart.count, 1)

        MockURLProtocol.setJSON(afterFirstContextJSON)
        await client.setContext(context: ["email": "pierre.kopaczewski@scenies.com"])
        await waitForFlagsCount(client, expected: 2, timeout: 1.0)
        let flagsAfterFirstContext = await client.getFlags()
        XCTAssertEqual(flagsAfterFirstContext.count, 2)

        MockURLProtocol.setJSON(afterSecondContextJSON)
        await client.setContext(context: ["email": "zlobodan.debernardi@sadoma.so"])
        await waitForFlagsCount(client, expected: 1, timeout: 1.0)
        let flagsAfterSecondContext = await client.getFlags()
        XCTAssertEqual(flagsAfterSecondContext.count, 1)

        await client.stopPolling()
    }

    // MARK: - Ready state tests

    func testIsReadyAfterSuccessfulFetch() async throws {
        let session = makeMockedSession()
        MockURLProtocol.setJSON("[[]]")

        let client = TgglClient(apiKey: "key", session: session, maxRetries: 0, reporting: false, initialFetch: false)

        let readyBefore = await client.getIsReady()
        XCTAssertFalse(readyBefore)

        await client.setContext(context: [:])
        try await Task.sleep(nanoseconds: 200_000_000)

        let readyAfter = await client.getIsReady()
        XCTAssertTrue(readyAfter)
    }

    func testWaitReadyResolvesAfterFetch() async throws {
        let session = makeMockedSession()
        MockURLProtocol.setJSON("[[]]")

        let client = TgglClient(apiKey: "key", session: session, maxRetries: 0, reporting: false, initialFetch: false)

        await client.setContext(context: [:])

        await client.waitReady()
        let ready = await client.getIsReady()
        XCTAssertTrue(ready)
    }

    func testIsReadyAfterErrorStillBecomesTrue() async throws {
        let session = makeMockedSession()
        MockURLProtocol.setResponse(MockURLProtocol.Response(statusCode: 500, headers: nil, data: Data()))

        let client = TgglClient(apiKey: "key", session: session, maxRetries: 0, reporting: false, initialFetch: false)

        await client.setContext(context: [:])
        try await Task.sleep(nanoseconds: 200_000_000)

        let ready = await client.getIsReady()
        XCTAssertTrue(ready, "isReady should be true even after a failed fetch (first attempt completed)")
    }

    // MARK: - Error exposure tests

    func testGetErrorReturnsNilOnSuccess() async throws {
        let session = makeMockedSession()
        MockURLProtocol.setJSON("[[]]")

        let client = TgglClient(apiKey: "key", session: session, maxRetries: 0, reporting: false, initialFetch: false)

        await client.setContext(context: [:])
        try await Task.sleep(nanoseconds: 200_000_000)

        let error = await client.getError()
        XCTAssertNil(error)
    }

    func testGetErrorReturnsErrorOnFailure() async throws {
        let session = makeMockedSession()
        MockURLProtocol.setResponse(MockURLProtocol.Response(statusCode: 500, headers: nil, data: Data()))

        let client = TgglClient(apiKey: "key", session: session, maxRetries: 0, reporting: false, initialFetch: false)

        await client.setContext(context: [:])
        try await Task.sleep(nanoseconds: 200_000_000)

        let error = await client.getError()
        XCTAssertNotNil(error)
    }

    func testErrorClearedOnSubsequentSuccess() async throws {
        let session = makeMockedSession()

        MockURLProtocol.setResponse(MockURLProtocol.Response(statusCode: 500, headers: nil, data: Data()))
        let client = TgglClient(apiKey: "key", session: session, maxRetries: 0, reporting: false, initialFetch: false)

        await client.setContext(context: [:])
        try await Task.sleep(nanoseconds: 200_000_000)
        let errorBefore = await client.getError()
        XCTAssertNotNil(errorBefore)

        MockURLProtocol.setJSON("[[]]")
        await client.setContext(context: [:])
        try await Task.sleep(nanoseconds: 200_000_000)
        let errorAfter = await client.getError()
        XCTAssertNil(errorAfter)
    }

    // MARK: - Refetch and close tests

    func testRefetchReloadsFlags() async throws {
        let session = makeMockedSession()
        MockURLProtocol.setJSON("[[]]")

        let client = TgglClient(apiKey: "key", session: session, maxRetries: 0, reporting: false, initialFetch: false)

        await client.setContext(context: [:])
        try await Task.sleep(nanoseconds: 200_000_000)
        await waitForFlagsCount(client, expected: 0, timeout: 1.0)

        MockURLProtocol.setJSON("""
        [[{"key":"flag1","type":"boolean","booleanValue":true}]]
        """)
        await client.refetch()
        await waitForFlagsCount(client, expected: 1, timeout: 1.0)

        let flags = await client.getFlags()
        XCTAssertEqual(flags.count, 1)
        XCTAssertEqual(flags.first?.key, "flag1")
    }

    func testCloseStopsPolling() async throws {
        let session = makeMockedSession()
        MockURLProtocol.setJSON("[[]]")

        let client = TgglClient(apiKey: "key", session: session, maxRetries: 0, reporting: false, initialFetch: false)

        await client.startPolling(every: 100)
        try await Task.sleep(nanoseconds: 200_000_000)

        await client.close()

        let polling = await client.polling
        if case .disabled = polling {
            // expected
        } else {
            XCTFail("Polling should be disabled after close()")
        }
    }

    // MARK: - Failover tests

    func testFailoverToSecondURL() async throws {
        let session = makeMockedSession()
        MockURLProtocol.clear()

        MockURLProtocol.setHandler { request in
            let url = request.url!.absoluteString
            if url.contains("bad-server.example.com") {
                return MockURLProtocol.Response(statusCode: 500, headers: nil, data: Data())
            } else if url.contains("api.tggl.io") {
                return MockURLProtocol.Response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    data: Data("[[]]".utf8)
                )
            }
            return nil
        }

        let client = TgglClient(
            apiKey: "key",
            baseUrls: ["https://bad-server.example.com", "https://api.tggl.io"],
            session: session,
            maxRetries: 0,
            reporting: false,
            initialFetch: false
        )

        await client.setContext(context: [:])
        try await Task.sleep(nanoseconds: 300_000_000)

        let error = await client.getError()
        XCTAssertNil(error, "Should succeed via failover to second URL")

        let ready = await client.getIsReady()
        XCTAssertTrue(ready)
    }

    // MARK: - Get with default value

    func testGetReturnsDefaultWhenFlagMissing() async throws {
        let session = makeMockedSession()
        MockURLProtocol.setJSON("[[]]")

        let client = TgglClient(apiKey: "key", session: session, maxRetries: 0, reporting: false, initialFetch: false)

        await client.setContext(context: [:])
        try await Task.sleep(nanoseconds: 200_000_000)

        let defaultTggl = Tggl(key: "missing", value: .string("default"))
        let result = await client.get(slug: "missing", defaultValue: defaultTggl)
        XCTAssertEqual(result.value, .string("default"))
    }

    func testGetReturnsActualFlagWhenPresent() async throws {
        let session = makeMockedSession()
        MockURLProtocol.setJSON("""
        [[{"key":"myFlag","type":"boolean","booleanValue":true}]]
        """)

        let client = TgglClient(apiKey: "key", session: session, maxRetries: 0, reporting: false, initialFetch: false)

        await client.setContext(context: [:])
        try await Task.sleep(nanoseconds: 200_000_000)

        let defaultTggl = Tggl(key: "myFlag", value: .boolean(false))
        let result = await client.get(slug: "myFlag", defaultValue: defaultTggl)
        XCTAssertEqual(result.value, .boolean(true))
    }

    // MARK: - Init options

    func testInitialFetchFalseDoesNotFetch() async throws {
        let session = makeMockedSession()
        MockURLProtocol.setJSON("""
        [[{"key":"flag","type":"string","stringValue":"val"}]]
        """)

        let client = TgglClient(apiKey: "key", session: session, maxRetries: 0, reporting: false, initialFetch: false)

        try await Task.sleep(nanoseconds: 300_000_000)

        let flags = await client.getFlags()
        XCTAssertEqual(flags.count, 0, "With initialFetch: false and no explicit setContext/startPolling, no fetch should occur")
    }
}
