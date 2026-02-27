import Foundation

public actor TgglReporting {

    private struct AggregationKey: Hashable {
        let valueJSON: String
        let defaultJSON: String
    }

    private struct FlagEntry {
        let value: Any?
        let defaultValue: Any?
        var count: Int
    }

    // clientId -> slug -> aggregationKey -> FlagEntry
    private var reportFlags: [String: [String: [AggregationKey: FlagEntry]]] = [:]

    private let apiKey: String?
    private let baseUrls: [String]
    private let session: URLSession
    private var flushIntervalMs: Int
    private var flushTask: Task<Void, Never>?

    public init(
        apiKey: String? = nil,
        baseUrls: [String] = ["https://api.tggl.io"],
        session: URLSession = .shared,
        flushIntervalMs: Int = 5_000
    ) {
        self.apiKey = apiKey
        self.session = session
        self.flushIntervalMs = flushIntervalMs

        var urls = baseUrls
        if !urls.contains("https://api.tggl.io") {
            urls.append("https://api.tggl.io")
        }
        self.baseUrls = urls
    }

    public func reportFlag(
        slug: String,
        value: TgglValue?,
        defaultValue: TgglValue?,
        count: Int = 1,
        clientId: String = ""
    ) {
        let rawValue = value.flatMap { Self.toRawJSON($0) }
        let rawDefault = defaultValue.flatMap { Self.toRawJSON($0) }

        let valueJSON = Self.jsonString(rawValue) ?? "null"
        let defaultJSON = Self.jsonString(rawDefault) ?? "null"
        let key = AggregationKey(valueJSON: valueJSON, defaultJSON: defaultJSON)

        reportFlags[clientId, default: [:]][slug, default: [:]][key, default: FlagEntry(value: rawValue, defaultValue: rawDefault, count: 0)].count += count

        scheduleNextFlush()
    }

    public func flush() async {
        flushTask?.cancel()
        flushTask = nil

        guard !reportFlags.isEmpty else {
            scheduleNextFlush()
            return
        }

        let flagsToReport = reportFlags
        reportFlags = [:]

        var clients: [[String: Any]] = []
        for (clientId, slugs) in flagsToReport {
            var flagsDict: [String: Any] = [:]
            for (slug, entries) in slugs {
                var flagArray: [[String: Any]] = []
                for (_, entry) in entries {
                    var item: [String: Any] = ["count": entry.count]
                    item["value"] = entry.value ?? NSNull()
                    item["default"] = entry.defaultValue ?? NSNull()
                    flagArray.append(item)
                }
                flagsDict[slug] = flagArray
            }
            var clientDict: [String: Any] = ["flags": flagsDict]
            if !clientId.isEmpty {
                clientDict["id"] = clientId
            }
            clients.append(clientDict)
        }

        let report: [String: Any] = ["clients": clients]

        guard let postData = try? JSONSerialization.data(withJSONObject: report) else {
            scheduleNextFlush()
            return
        }

        var headers: [String: String] = ["Content-Type": "application/json"]
        if let apiKey {
            headers["x-tggl-api-key"] = apiKey
        }

        for baseUrl in baseUrls {
            guard let url = URL(string: baseUrl + "/report") else { continue }

            var success = false
            for attempt in 0..<2 {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.allHTTPHeaderFields = headers
                    request.httpBody = postData
                    request.timeoutInterval = 10

                    let (_, response) = try await session.data(for: request)
                    if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                        success = true
                        break
                    }
                } catch {
                    if attempt < 1 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }
            }

            if success { break }
        }

        scheduleNextFlush()
    }

    public func start(flushIntervalMs: Int = 5_000) {
        self.flushIntervalMs = max(0, flushIntervalMs)

        if flushIntervalMs <= 0 {
            flushTask?.cancel()
            flushTask = nil
        }

        scheduleNextFlush()
    }

    public func stop() {
        start(flushIntervalMs: 0)
    }

    public func isActive() -> Bool {
        flushIntervalMs > 0
    }

    // MARK: - Private

    private func scheduleNextFlush() {
        guard flushIntervalMs > 0, flushTask == nil, !reportFlags.isEmpty else { return }

        let interval = flushIntervalMs
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000)
            await self?.flush()
        }
    }

    private static func toRawJSON(_ value: TgglValue) -> Any {
        switch value {
        case .string(let s): return s
        case .number(let n): return n
        case .boolean(let b): return b
        case .array(let arr): return arr.map { toRawJSON($0) }
        case .object(let obj): return obj.mapValues { toRawJSON($0) }
        case .null: return NSNull()
        }
    }

    private static func jsonString(_ value: Any?) -> String? {
        guard let value else { return nil }
        if value is NSNull { return "null" }
        if let s = value as? String { return "\"\(s)\"" }
        if let n = value as? Int { return "\(n)" }
        if let d = value as? Double { return "\(d)" }
        if let b = value as? Bool { return b ? "true" : "false" }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else {
            return "\(value)"
        }
        return String(data: data, encoding: .utf8)
    }
}
