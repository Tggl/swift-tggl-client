import Foundation

/// Intercepts every request of a session built with ``MockURLProtocol/session()``.
final class MockURLProtocol: URLProtocol {
    struct Response {
        var statusCode: Int = 200
        var body: Data = Data()
        /// Simulated server latency.
        var delay: TimeInterval = 0

        static func json(_ string: String, status: Int = 200, delay: TimeInterval = 0) -> Response {
            Response(statusCode: status, body: Data(string.utf8), delay: delay)
        }

        static func status(_ code: Int) -> Response {
            Response(statusCode: code, body: Data(#"{"error":"mock"}"#.utf8))
        }
    }

    struct RecordedRequest {
        let url: URL
        let headers: [String: String]
        let body: Data

        var path: String { url.path }

        var jsonBody: Any? {
            try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed])
        }
    }

    typealias Handler = (RecordedRequest) -> Response

    private static let lock = NSLock()
    private static var handler: Handler = { _ in .json("[[]]") }
    private static var recorded: [RecordedRequest] = []

    static func setHandler(_ handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
    }

    static var requests: [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    static func requests(path: String) -> [RecordedRequest] {
        requests.filter { $0.path.hasSuffix(path) }
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        handler = { _ in .json("[[]]") }
        recorded = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    // MARK: - URLProtocol

    private var workItem: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let recordedRequest = RecordedRequest(
            url: request.url!,
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.readBody(of: request)
        )

        Self.lock.lock()
        Self.recorded.append(recordedRequest)
        let handler = Self.handler
        Self.lock.unlock()

        let response = handler(recordedRequest)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let httpResponse = HTTPURLResponse(
                url: recordedRequest.url,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            self.client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: response.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        self.workItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + response.delay, execute: workItem)
    }

    override func stopLoading() {
        workItem?.cancel()
    }

    /// URLSession moves `httpBody` into `httpBodyStream` before handing the request to the protocol.
    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
