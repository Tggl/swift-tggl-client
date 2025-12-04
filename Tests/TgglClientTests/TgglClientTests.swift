import XCTest
@testable import TgglClient

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol {
    struct Response {
        let statusCode: Int
        let headers: [String: String]?
        let data: Data
    }
    
    // Thread-safe single "current response" used for all upcoming requests
    private static var currentResponse: Response?
    private static let lock = NSLock()
    
    // Set a constant response for all upcoming requests
    static func setResponse(_ response: Response?) {
        lock.lock()
        currentResponse = response
        lock.unlock()
    }
    
    // Convenience for JSON payloads
    static func setJSON(_ jsonString: String, statusCode: Int = 200, headers: [String: String] = ["Content-Type": "application/json"]) {
        let data = Data(jsonString.utf8)
        setResponse(Response(statusCode: statusCode, headers: headers, data: data))
    }
    
    // Clear any configured response (subsequent calls will get a 500)
    static func clear() {
        lock.lock()
        currentResponse = nil
        lock.unlock()
    }
    
    override class func canInit(with request: URLRequest) -> Bool {
        // Intercept all requests from the test's URLSession
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    
    override func startLoading() {
        guard let client = client else { return }
        
        // Snapshot the current response under lock
        let responseSnapshot: Response? = {
            Self.lock.lock()
            let resp = Self.currentResponse
            Self.lock.unlock()
            return resp
        }()
        
        let url = request.url!
        if let next = responseSnapshot {
            let httpResponse = HTTPURLResponse(url: url, statusCode: next.statusCode, httpVersion: "HTTP/1.1", headerFields: next.headers)!
            client.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: next.data)
            client.urlProtocolDidFinishLoading(self)
        } else {
            // No response configured; return 500
            let httpResponse = HTTPURLResponse(url: url, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!
            client.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: Data())
            client.urlProtocolDidFinishLoading(self)
        }
    }
    
    override func stopLoading() {
        // Nothing to clean up for this simple mock
    }
}

final class TgglClientTests: XCTestCase {
    override func setUp() async throws {
        // Ensure clean storage between tests
        let storage = TgglStorage()
        storage.clear()
        MockURLProtocol.clear()
    }
    
    private func makeMockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        // Make sure no caching interferes
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }
    
    // Helper to wait until flags count matches expectation or timeout
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
    
    func testFlagsAreUpdatedWhenContextChanges() async throws {
        // Build session with our mock protocol
        let session = makeMockedSession()
        
        // Prepare three payloads: initial, after first context, after second context
        let initialJSON = """
        [[{"key":"bgColor","type":"string","stringValue":"#ff0000"}]]
        """
        let afterFirstContextJSON = """
        [[{"key":"bgColor","type":"string","stringValue":"#ff0000"},{"key":"eric","type":"string","stringValue":"flag"}]]
        """
        let afterSecondContextJSON = """
        [[{"key":"bgColor","type":"string","stringValue":"#ff0000"}]]
        """
        
        // Create client with injected session
        let client = TgglClient(apiKey: "test_api_key", session: session)
        
        // Set the initial response and start polling
        MockURLProtocol.setJSON(initialJSON)
        await client.startPolling(every: 3)
        
        // Wait for initial fetch to apply
        await waitForFlagsCount(client, expected: 1, timeout: 1.0)
        let flagsAfterStart = await client.getFlags()
        XCTAssertEqual(flagsAfterStart.count, 1)
        
        // First context change: update the mock for all upcoming calls, then change context
        MockURLProtocol.setJSON(afterFirstContextJSON)
        await client.setContext(context: ["email": "pierre.kopaczewski@scenies.com"])
        await waitForFlagsCount(client, expected: 2, timeout: 1.0)
        let flagsAfterFirstContext = await client.getFlags()
        XCTAssertEqual(flagsAfterFirstContext.count, 2)
        
        // Second context change: update the mock again, then change context
        MockURLProtocol.setJSON(afterSecondContextJSON)
        await client.setContext(context: ["email": "zlobodan.debernardi@sadoma.so"])
        await waitForFlagsCount(client, expected: 1, timeout: 1.0)
        let flagsAfterSecondContext = await client.getFlags()
        XCTAssertEqual(flagsAfterSecondContext.count, 1)
        
        await client.stopPolling()
    }
}

