import Foundation

/// Configuration of a ``TgglClient``. Every property has a sensible default.
public struct TgglOptions {
    /// Where cached flags are persisted between launches.
    public enum Cache {
        /// `UserDefaults`, one entry per API key (default).
        case userDefaults
        /// No persistence: the client starts with defaults until the first response.
        case disabled
        /// Your own storage (Keychain, file, memory…).
        case custom(any TgglStorage)
    }

    /// Tggl API or Tggl Proxy URLs, tried in order. Each URL gets its own retries.
    public var baseUrls: [URL]
    /// Append `https://api.tggl.io` as the last fallback when absent from `baseUrls` (default `true`).
    /// Set to `false` if your context must never leave your own proxy.
    public var fallbackToTgglApi: Bool
    /// Retries per URL, with exponential backoff (100 ms, 200 ms, 400 ms, capped at 500 ms).
    /// 400 and 401 responses are never retried, nor sent to the other URLs.
    public var maxRetries: Int
    /// Timeout of each individual request.
    public var timeout: TimeInterval
    /// Fetch flags as soon as the client is created (default `true`).
    public var initialFetch: Bool
    /// Re-evaluate flags periodically. `nil` (default) disables polling.
    /// On iOS, polling pauses while the app is in background.
    public var pollingInterval: TimeInterval?
    /// Send evaluation statistics to Tggl (default `true`).
    public var reporting: Bool
    /// Interval between two reporting batches (default 5 s).
    public var reportingInterval: TimeInterval
    /// Appended to the client identifier shown in the Tggl dashboard.
    public var appName: String?
    /// Flags persistence (default ``Cache/userDefaults``).
    public var cache: Cache
    public var session: URLSession

    public init(
        baseUrls: [URL] = [],
        fallbackToTgglApi: Bool = true,
        maxRetries: Int = 3,
        timeout: TimeInterval = 8,
        initialFetch: Bool = true,
        pollingInterval: TimeInterval? = nil,
        reporting: Bool = true,
        reportingInterval: TimeInterval = 5,
        appName: String? = nil,
        cache: Cache = .userDefaults,
        session: URLSession = .shared
    ) {
        self.baseUrls = baseUrls
        self.fallbackToTgglApi = fallbackToTgglApi
        self.maxRetries = maxRetries
        self.timeout = timeout
        self.initialFetch = initialFetch
        self.pollingInterval = pollingInterval
        self.reporting = reporting
        self.reportingInterval = reportingInterval
        self.appName = appName
        self.cache = cache
        self.session = session
    }

    static let tgglApiUrl = URL(string: "https://api.tggl.io")!

    var resolvedBaseUrls: [URL] {
        var urls: [URL] = []
        for url in baseUrls {
            let normalized = Self.normalize(url)
            if !urls.contains(normalized) {
                urls.append(normalized)
            }
        }
        if fallbackToTgglApi, !urls.contains(Self.tgglApiUrl) {
            urls.append(Self.tgglApiUrl)
        }
        return urls
    }

    func resolvedStorage(apiKey: String) -> (any TgglStorage)? {
        switch cache {
        case .userDefaults: return TgglUserDefaultsStorage(apiKey: apiKey)
        case .disabled: return nil
        case .custom(let storage): return storage
        }
    }

    /// Removes trailing slashes so that `https://proxy.example.com/` and `https://proxy.example.com` match.
    static func normalize(_ url: URL) -> URL {
        var string = url.absoluteString
        while string.hasSuffix("/") {
            string.removeLast()
        }
        return URL(string: string) ?? url
    }
}
