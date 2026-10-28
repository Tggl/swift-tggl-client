import Combine
import XCTest
@testable import TgglClient

final class TgglClientTests: XCTestCase {
    static let proxy = URL(string: "https://proxy.example.com")!

    static let flagsJSON = """
    [[
      {"key": "bool-flag", "type": "boolean", "booleanValue": true},
      {"key": "string-flag", "type": "string", "stringValue": "blue"},
      {"key": "int-flag", "type": "number", "numberValue": 42},
      {"key": "double-flag", "type": "number", "numberValue": 1.5},
      {"key": "null-flag", "type": "null"},
      {"key": "json-flag", "type": "json", "jsonValue": {"title": "Hi", "tags": ["a", "b"]}}
    ]]
    """

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    private func makeOptions(
        baseUrls: [URL] = [TgglClientTests.proxy],
        fallbackToTgglApi: Bool = false,
        maxRetries: Int = 0,
        initialFetch: Bool = true,
        cache: TgglOptions.Cache = .disabled
    ) -> TgglOptions {
        TgglOptions(
            baseUrls: baseUrls,
            fallbackToTgglApi: fallbackToTgglApi,
            maxRetries: maxRetries,
            timeout: 2,
            initialFetch: initialFetch,
            reporting: false,
            cache: cache,
            session: MockURLProtocol.session()
        )
    }

    private func makeClient(
        context: TgglContextInput? = ["userId": "u1"],
        options: TgglOptions? = nil
    ) -> TgglClient {
        TgglClient(apiKey: "test-key", context: context, options: options ?? makeOptions())
    }

    private func userId(of request: MockURLProtocol.RecordedRequest) -> String? {
        ((request.jsonBody as? [[String: Any]])?.first)?["userId"] as? String
    }

    // MARK: - Reading flags

    func testReturnsDefaultsBeforeFirstResponse() async {
        MockURLProtocol.setHandler { _ in .json(Self.flagsJSON, delay: 0.3) }
        let client = makeClient()

        XCTAssertFalse(client.isReady)
        XCTAssertEqual(client.get("bool-flag", default: false), false)

        await client.refetch()

        XCTAssertTrue(client.isReady)
        XCTAssertEqual(client.get("bool-flag", default: false), true)
    }

    func testTypedValues() async {
        MockURLProtocol.setHandler { _ in .json(Self.flagsJSON) }
        let client = makeClient()
        await client.refetch()

        XCTAssertEqual(client.get("bool-flag", default: false), true)
        XCTAssertEqual(client.get("string-flag", default: "red"), "blue")
        XCTAssertEqual(client.get("int-flag", default: 0), 42)
        XCTAssertEqual(client.get("int-flag", default: 0.0), 42.0)
        XCTAssertEqual(client.get("double-flag", default: 0.0), 1.5)
        XCTAssertEqual(client.get("json-flag", default: TgglValue.null), ["title": "Hi", "tags": ["a", "b"]])
        XCTAssertEqual(client.get("json-flag", default: [String: TgglValue]())["title"], "Hi")
    }

    func testUnknownFlagReturnsDefault() async {
        MockURLProtocol.setHandler { _ in .json(Self.flagsJSON) }
        let client = makeClient()
        await client.refetch()

        XCTAssertEqual(client.get("unknown-flag", default: true), true)
        XCTAssertEqual(client.get("unknown-flag", default: "fallback"), "fallback")
    }

    func testTypeMismatchReturnsDefault() async {
        MockURLProtocol.setHandler { _ in .json(Self.flagsJSON) }
        let client = makeClient()
        await client.refetch()

        XCTAssertEqual(client.get("string-flag", default: false), false)
        XCTAssertEqual(client.get("bool-flag", default: "x"), "x")
        // 1.5 is not an Int.
        XCTAssertEqual(client.get("double-flag", default: 7), 7)
    }

    func testNullFlagIsActiveWithoutValue() async {
        MockURLProtocol.setHandler { _ in .json(Self.flagsJSON) }
        let client = makeClient()
        await client.refetch()

        XCTAssertEqual(client.get("null-flag", default: "x"), "x")
        XCTAssertEqual(client.get("null-flag", default: TgglValue.string("x")), .null)
        XCTAssertNil(client.get("null-flag", default: Optional("x")))
        XCTAssertEqual(client.get("unknown-flag", default: Optional("x")), "x")
    }

    func testDecodeJsonFlag() async {
        struct Banner: Codable, Equatable {
            let title: String
            let tags: [String]
        }
        MockURLProtocol.setHandler { _ in .json(Self.flagsJSON) }
        let client = makeClient()
        await client.refetch()

        let fallback = Banner(title: "", tags: [])
        XCTAssertEqual(client.decode("json-flag", as: Banner.self, default: fallback), Banner(title: "Hi", tags: ["a", "b"]))
        XCTAssertEqual(client.decode("string-flag", as: Banner.self, default: fallback), fallback)
        XCTAssertEqual(client.decode("unknown", as: Banner.self, default: fallback), fallback)
    }

    func testFlagThatBecomesInactiveFallsBackToDefault() async {
        MockURLProtocol.setHandler { _ in .json(Self.flagsJSON) }
        let client = makeClient()
        await client.refetch()
        XCTAssertEqual(client.get("bool-flag", default: false), true)

        // Inactive flags are not listed by /typed-flags.
        MockURLProtocol.setHandler { _ in .json("[[]]") }
        await client.refetch()

        XCTAssertEqual(client.get("bool-flag", default: false), false)
        XCTAssertTrue(client.flags.isEmpty)
    }

    // MARK: - Request & context

    func testRequestFormat() async throws {
        let client = makeClient(context: ["userId": "u1", "age": 30, "beta": true, "email": nil])
        await client.refetch()

        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://proxy.example.com/typed-flags")
        let apiKey = request.headers.first { $0.key.lowercased() == "x-tggl-api-key" }?.value
        XCTAssertEqual(apiKey, "test-key")

        let body = try XCTUnwrap(request.jsonBody as? [[String: Any]])
        XCTAssertEqual(body.count, 1, "/typed-flags expects an array of contexts")
        XCTAssertEqual(body[0]["userId"] as? String, "u1")
        XCTAssertEqual(body[0]["age"] as? Double, 30)
        XCTAssertEqual(body[0]["beta"] as? Bool, true)
        XCTAssertTrue(body[0]["email"] is NSNull)
    }

    func testSetContextReplacesAndUpdateContextMerges() async {
        let client = makeClient(context: nil)

        await client.setContext(["userId": "u1", "plan": "free"])
        XCTAssertEqual(client.context, ["userId": "u1", "plan": "free"])

        await client.updateContext(["plan": "premium", "country": "FR"])
        XCTAssertEqual(client.context, ["userId": "u1", "plan": "premium", "country": "FR"])

        await client.setContext(["userId": "u2"])
        XCTAssertEqual(client.context, ["userId": "u2"])
        XCTAssertEqual(MockURLProtocol.requests.last.flatMap(userId(of:)), "u2")
    }

    func testOnlyLatestContextIsApplied() async throws {
        MockURLProtocol.setHandler { request in
            let isSlow = ((request.jsonBody as? [[String: Any]])?.first?["userId"] as? String) == "slow"
            let variant = isSlow ? "slow" : "fast"
            return .json(#"[[{"key":"variant","type":"string","stringValue":"\#(variant)"}]]"#, delay: isSlow ? 0.5 : 0)
        }
        let client = makeClient(context: nil, options: makeOptions(initialFetch: false))

        let slow = Task { await client.setContext(["userId": "slow"]) }
        try await Task.sleep(nanoseconds: 100_000_000)
        await client.setContext(["userId": "fast"])
        await slow.value
        try await Task.sleep(nanoseconds: 700_000_000)

        XCTAssertEqual(client.get("variant", default: ""), "fast")
        XCTAssertEqual(client.context, ["userId": "fast"])
    }

    // MARK: - Network errors

    func testUnauthorizedIsNotRetried() async {
        MockURLProtocol.setHandler { _ in .status(401) }
        let client = makeClient(options: makeOptions(maxRetries: 3))
        await client.refetch()

        XCTAssertEqual(MockURLProtocol.requests.count, 1)
        XCTAssertEqual(client.lastError, .invalidApiKey)
        XCTAssertTrue(client.isReady, "the client is ready even when the first request fails")
    }

    func testServerErrorsAreRetriedPerUrl() async {
        MockURLProtocol.setHandler { _ in .status(500) }
        let client = makeClient(options: makeOptions(maxRetries: 2))
        await client.refetch()

        XCTAssertEqual(MockURLProtocol.requests.count, 3)
        XCTAssertEqual(client.lastError, .httpStatus(500))
    }

    func testFallsBackToTgglApi() async {
        MockURLProtocol.setHandler { request in
            request.url.host == "proxy.example.com" ? .status(503) : .json(Self.flagsJSON)
        }
        let client = makeClient(options: makeOptions(fallbackToTgglApi: true))
        await client.refetch()

        XCTAssertEqual(MockURLProtocol.requests.map(\.url.host), ["proxy.example.com", "api.tggl.io"])
        XCTAssertEqual(client.get("bool-flag", default: false), true)
        XCTAssertNil(client.lastError)
    }

    func testKeepsLastFlagsOnErrorAndClearsErrorOnSuccess() async {
        MockURLProtocol.setHandler { _ in .json(Self.flagsJSON) }
        let client = makeClient()
        await client.refetch()

        MockURLProtocol.setHandler { _ in .status(500) }
        await client.refetch()
        XCTAssertEqual(client.get("bool-flag", default: false), true)
        XCTAssertEqual(client.lastError, .httpStatus(500))

        MockURLProtocol.setHandler { _ in .json(Self.flagsJSON) }
        await client.refetch()
        XCTAssertNil(client.lastError)
    }

    func testInvalidResponseIsReported() async {
        MockURLProtocol.setHandler { _ in .json("not json") }
        let client = makeClient()
        await client.refetch()

        guard case .invalidResponse = client.lastError else {
            return XCTFail("expected invalidResponse, got \(String(describing: client.lastError))")
        }
    }

    // MARK: - Readiness

    func testWaitReady() async {
        MockURLProtocol.setHandler { _ in .json(Self.flagsJSON, delay: 0.2) }
        let client = makeClient()

        await client.waitReady()

        XCTAssertTrue(client.isReady)
        XCTAssertEqual(client.get("bool-flag", default: false), true)
    }

    func testInitialFetchDisabledDoesNotCallTheApi() async throws {
        let client = makeClient(options: makeOptions(initialFetch: false))
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
        XCTAssertFalse(client.isReady)
    }

    // MARK: - Cache

    func testCachedFlagsMakeTheClientReadyImmediately() async {
        let storage = TgglMemoryStorage()
        MockURLProtocol.setHandler { _ in .json(Self.flagsJSON) }
        let first = makeClient(options: makeOptions(cache: .custom(storage)))
        await first.refetch()
        await first.close()

        let second = makeClient(context: nil, options: makeOptions(initialFetch: false, cache: .custom(storage)))

        XCTAssertTrue(second.isReady)
        XCTAssertEqual(second.get("bool-flag", default: false), true)
        XCTAssertEqual(second.context, ["userId": "u1"])
    }

    func testCachedFlagsAreNotReusedForAnotherContext() async {
        let storage = TgglMemoryStorage()
        MockURLProtocol.setHandler { _ in .json(Self.flagsJSON) }
        let first = makeClient(context: ["userId": "u1"], options: makeOptions(cache: .custom(storage)))
        await first.refetch()

        let sameUser = makeClient(context: ["userId": "u1"], options: makeOptions(initialFetch: false, cache: .custom(storage)))
        XCTAssertTrue(sameUser.isReady)
        XCTAssertEqual(sameUser.get("bool-flag", default: false), true)

        let otherUser = makeClient(context: ["userId": "u2"], options: makeOptions(initialFetch: false, cache: .custom(storage)))
        XCTAssertEqual(otherUser.context, ["userId": "u2"])
        XCTAssertFalse(otherUser.isReady)
        XCTAssertEqual(otherUser.get("bool-flag", default: false), false)
    }

    func testUnauthorizedDoesNotFallBackToOtherUrls() async {
        MockURLProtocol.setHandler { _ in .status(401) }
        let client = makeClient(options: makeOptions(fallbackToTgglApi: true, maxRetries: 2))
        await client.refetch()

        XCTAssertEqual(MockURLProtocol.requests.map(\.url.host), ["proxy.example.com"])
        XCTAssertEqual(client.lastError, .invalidApiKey)
    }

    func testUserDefaultsCacheIsScopedPerApiKey() {
        XCTAssertNotEqual(
            TgglUserDefaultsStorage.fingerprint(of: "key-a"),
            TgglUserDefaultsStorage.fingerprint(of: "key-b")
        )
        XCTAssertEqual(
            TgglUserDefaultsStorage.fingerprint(of: "key-a"),
            TgglUserDefaultsStorage.fingerprint(of: "key-a")
        )
    }

    // MARK: - Publishers

    func testPublisherEmitsDefaultWhenFlagBecomesInactive() async {
        let client = makeClient(options: makeOptions(initialFetch: false))
        let values = Locked<[Bool]>([])
        let cancellable = client.publisher(for: "bool-flag", default: false)
            .sink { value in values.withLock { $0.append(value) } }

        MockURLProtocol.setHandler { _ in .json(Self.flagsJSON) }
        await client.refetch()
        MockURLProtocol.setHandler { _ in .json("[[]]") }
        await client.refetch()

        XCTAssertEqual(values.withLock { $0 }, [false, true, false])
        cancellable.cancel()
    }

    func testPublisherSkipsUnrelatedChanges() async {
        let client = makeClient(options: makeOptions(initialFetch: false))
        let values = Locked<[String]>([])
        let cancellable = client.publisher(for: "string-flag", default: "none")
            .sink { value in values.withLock { $0.append(value) } }

        MockURLProtocol.setHandler { _ in .json(Self.flagsJSON) }
        await client.refetch()
        MockURLProtocol.setHandler { _ in
            .json(#"[[{"key":"string-flag","type":"string","stringValue":"blue"},{"key":"other","type":"boolean","booleanValue":true}]]"#)
        }
        await client.refetch()

        XCTAssertEqual(values.withLock { $0 }, ["none", "blue"])
        cancellable.cancel()
    }

    func testErrorPublisher() async {
        let client = makeClient(options: makeOptions(initialFetch: false))
        let errors = Locked<[TgglError]>([])
        let cancellable = client.errorPublisher.sink { error in errors.withLock { $0.append(error) } }

        MockURLProtocol.setHandler { _ in .status(401) }
        await client.refetch()

        XCTAssertEqual(errors.withLock { $0 }, [.invalidApiKey])
        cancellable.cancel()
    }

    // MARK: - Polling

    func testPollingRefetchesAndStops() async throws {
        let client = makeClient()
        await client.refetch()
        let initialCount = MockURLProtocol.requests.count

        client.startPolling(every: 0.2)
        client.startPolling(every: 0.2) // must not start a second loop
        try await Task.sleep(nanoseconds: 700_000_000)

        let pollCount = MockURLProtocol.requests.count - initialCount
        XCTAssertGreaterThanOrEqual(pollCount, 2)
        XCTAssertLessThanOrEqual(pollCount, 4)

        client.stopPolling()
        let countAfterStop = MockURLProtocol.requests.count
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(MockURLProtocol.requests.count, countAfterStop)
    }

    // MARK: - Local overrides & close

    @MainActor
    func testSetFlagsLocally() {
        let client = makeClient(options: makeOptions(initialFetch: false))
        client.setFlags(["my-feature": true, "color": "red"])

        XCTAssertTrue(client.isReady)
        XCTAssertEqual(client.get("my-feature", default: false), true)
        XCTAssertEqual(client.get("color", default: ""), "red")
    }

    func testCloseStopsEverything() async throws {
        let client = makeClient()
        await client.refetch()
        client.startPolling(every: 0.1)
        await client.close()
        let count = MockURLProtocol.requests.count

        await client.setContext(["userId": "u2"])
        await client.refetch()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(MockURLProtocol.requests.count, count)
        XCTAssertFalse(client.isPolling)
    }

    // MARK: - Options

    func testBaseUrlsAreNormalizedAndTgglApiIsAppended() {
        let options = TgglOptions(baseUrls: [
            URL(string: "https://proxy.example.com/")!,
            URL(string: "https://proxy.example.com")!,
        ])
        XCTAssertEqual(options.resolvedBaseUrls.map(\.absoluteString), ["https://proxy.example.com", "https://api.tggl.io"])

        let proxyOnly = TgglOptions(baseUrls: [URL(string: "https://proxy.example.com")!], fallbackToTgglApi: false)
        XCTAssertEqual(proxyOnly.resolvedBaseUrls.map(\.absoluteString), ["https://proxy.example.com"])

        XCTAssertEqual(TgglOptions().resolvedBaseUrls.map(\.absoluteString), ["https://api.tggl.io"])
    }

    func testBackoff() {
        XCTAssertEqual(TgglTransport.backoffNanoseconds(attempt: 0), 100_000_000)
        XCTAssertEqual(TgglTransport.backoffNanoseconds(attempt: 1), 200_000_000)
        XCTAssertEqual(TgglTransport.backoffNanoseconds(attempt: 2), 400_000_000)
        XCTAssertEqual(TgglTransport.backoffNanoseconds(attempt: 3), 500_000_000)
        XCTAssertEqual(TgglTransport.backoffNanoseconds(attempt: 50), 500_000_000)
    }
}
