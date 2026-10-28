import Foundation

/// HTTP layer shared by flag evaluation and reporting: URL fallback, retries, error mapping.
final class TgglTransport: @unchecked Sendable {
    let apiKey: String
    let baseUrls: [URL]
    let session: URLSession
    let maxRetries: Int
    let timeout: TimeInterval

    init(apiKey: String, baseUrls: [URL], session: URLSession, maxRetries: Int, timeout: TimeInterval) {
        self.apiKey = apiKey
        self.baseUrls = baseUrls
        self.session = session
        self.maxRetries = max(0, maxRetries)
        self.timeout = timeout
    }

    /// POSTs `body` to `path` on each base URL in turn until one succeeds.
    ///
    /// - Throws: `CancellationError` if the task is cancelled, otherwise the last ``TgglError``.
    func post(path: String, body: Data) async throws -> Data {
        var lastError = TgglError.invalidResponse("no base URL configured")

        for baseUrl in baseUrls {
            let url = baseUrl.appendingPathComponent(path)

            attempts: for attempt in 0...maxRetries {
                try Task.checkCancellation()
                do {
                    return try await send(url: url, body: body)
                } catch let error as TgglError {
                    lastError = error
                    switch error {
                    case .invalidApiKey, .badRequest:
                        // Same key and context everywhere: fail now instead of sending them to other URLs.
                        throw error
                    default:
                        // Try the next URL right away when retrying this one cannot help.
                        guard error.isRetryable else { break attempts }
                    }
                }
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: Self.backoffNanoseconds(attempt: attempt))
                }
            }
        }

        throw lastError
    }

    /// 100 ms, 200 ms, 400 ms, then capped at 500 ms.
    static func backoffNanoseconds(attempt: Int) -> UInt64 {
        let milliseconds = min(100 * (1 << min(attempt, 10)), 500)
        return UInt64(milliseconds) * 1_000_000
    }

    private func send(url: URL, body: Data) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Tggl-Api-Key")

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw TgglError.network(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TgglError.network(URLError(.unknown))
        }

        let (data, response) = result
        guard let http = response as? HTTPURLResponse else {
            throw TgglError.invalidResponse("not an HTTP response")
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw TgglError.invalidApiKey
        case 400:
            throw TgglError.badRequest(message: Self.errorMessage(in: data))
        default:
            throw TgglError.httpStatus(http.statusCode)
        }
    }

    private static func errorMessage(in data: Data) -> String? {
        struct ErrorBody: Decodable { let error: String? }
        return (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
    }
}

// MARK: - /typed-flags wire format

enum TgglTypedFlags {
    /// One flag as returned by `POST /typed-flags`.
    /// Only active flags are listed; `type: "null"` is an active flag without value.
    private struct WireFlag: Decodable {
        let key: String
        /// `nil` when the type is unknown to this SDK version: the flag is then ignored
        /// instead of failing the whole response.
        let value: TgglValue?

        enum CodingKeys: String, CodingKey {
            case key, type, stringValue, numberValue, booleanValue, jsonValue
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try container.decode(String.self, forKey: .key)
            switch try container.decode(String.self, forKey: .type) {
            case "string": value = .string(try container.decode(String.self, forKey: .stringValue))
            case "number": value = .number(try container.decode(Double.self, forKey: .numberValue))
            case "boolean": value = .boolean(try container.decode(Bool.self, forKey: .booleanValue))
            case "json": value = try container.decode(TgglValue.self, forKey: .jsonValue)
            case "null": value = .null
            default: value = nil
            }
        }
    }

    /// Request body: `/typed-flags` only accepts an array of contexts.
    static func requestBody(context: [String: TgglValue]) throws -> Data {
        try JSONEncoder().encode([context])
    }

    /// Flags of the first (and only) evaluated context, keyed by slug.
    static func parse(_ data: Data) throws -> [String: TgglValue] {
        let response: [[WireFlag]]
        do {
            response = try JSONDecoder().decode([[WireFlag]].self, from: data)
        } catch {
            throw TgglError.invalidResponse(String(describing: error))
        }
        guard let flags = response.first else {
            throw TgglError.invalidResponse("empty response")
        }
        var result: [String: TgglValue] = [:]
        for flag in flags {
            if let value = flag.value {
                result[flag.key] = value
            }
        }
        return result
    }
}
