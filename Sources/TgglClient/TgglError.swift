import Foundation

/// Errors reported by the client.
///
/// The client never throws while reading flags: on any error it keeps the last known
/// flags (or defaults) and exposes the error through ``TgglClient/lastError`` and
/// ``TgglClient/errorPublisher``.
public enum TgglError: Error, Equatable {
    /// 401: the API key is missing or invalid. Not retried.
    case invalidApiKey
    /// 400: the request was rejected by the API. Not retried.
    case badRequest(message: String?)
    /// Any other non-2xx HTTP status. 408, 429 and 5xx are retried.
    case httpStatus(Int)
    /// The transport failed (offline, timeout, DNS, TLS…). Retried.
    case network(URLError)
    /// The response body could not be decoded.
    case invalidResponse(String)

    var isRetryable: Bool {
        switch self {
        case .invalidApiKey, .badRequest, .invalidResponse:
            return false
        case .httpStatus(let status):
            return status == 408 || status == 429 || status >= 500
        case .network:
            return true
        }
    }
}

extension TgglError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidApiKey:
            return "Tggl: invalid or missing API key"
        case .badRequest(let message):
            return "Tggl: bad request" + (message.map { " (\($0))" } ?? "")
        case .httpStatus(let status):
            return "Tggl: unexpected HTTP status \(status)"
        case .network(let error):
            return "Tggl: network error (\(error.localizedDescription))"
        case .invalidResponse(let reason):
            return "Tggl: invalid response (\(reason))"
        }
    }
}
