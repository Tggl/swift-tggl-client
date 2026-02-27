import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

public actor TgglClient: ObservableObject {
    let apiKey: String
    let baseUrls: [URL]
    let storage: TgglStorage
    let session: URLSession
    let maxRetries: Int
    let timeoutInterval: TimeInterval
    let appName: String?

    let reporting: TgglReporting?
    private let clientId: String

    @Published private var flags: [[Tggl]] = []
    @Published private var _lastError: Error?
    @Published private var _isReady: Bool = false

    private var context: [String: Any] = [:]
    var polling: Polling = .disabled
    var requestTask: Task<Void, Never>?
    private var readyContinuations: [CheckedContinuation<Void, Never>] = []

    public init(
        apiKey: String,
        baseUrls: [String] = ["https://api.tggl.io"],
        session: URLSession = .shared,
        maxRetries: Int = 3,
        timeoutMs: Int = 8_000,
        appName: String? = nil,
        reporting: Bool = true,
        initialFetch: Bool = true
    ) {
        self.apiKey = apiKey
        self.storage = TgglStorage()
        self.session = session
        self.maxRetries = maxRetries
        self.timeoutInterval = TimeInterval(timeoutMs) / 1000.0
        self.appName = appName

        var urls = baseUrls.compactMap { URL(string: $0) }
        let tgglURL = URL(string: "https://api.tggl.io")!
        if !urls.contains(tgglURL) {
            urls.append(tgglURL)
        }
        self.baseUrls = urls

        var id = "swift-client:1.0.0/TgglClient"
        if let appName, !appName.isEmpty {
            id += "/\(appName)"
        }
        self.clientId = id

        if reporting {
            self.reporting = TgglReporting(
                apiKey: apiKey,
                baseUrls: baseUrls,
                session: session
            )
        } else {
            self.reporting = nil
        }

        if initialFetch {
            Task { [weak self] in
                guard let self else { return }

                let initialFlags = storage.getFlags()
                let initialContext = storage.getContext()
                await setContext(context: initialContext)

                if !(initialFlags.first ?? []).isEmpty {
                    await setFlags(initialFlags)
                    await markReady()
                }
            }
        }

        self.subscribeToAppStateNotifications()
    }

    public func getFlags() -> [Tggl] {
        flags.first ?? []
    }

    func setFlags(_ newFlags: [[Tggl]]) {
        flags = newFlags
    }

    public func get(slug: String, defaultValue: TgglValue) -> TgglValue {
        let result = self.flags.first?.first(where: { $0.key == slug })

        if let reporting {
            Task {
                await reporting.reportFlag(
                    slug: slug,
                    value: result?.value,
                    defaultValue: defaultValue,
                    clientId: clientId
                )
            }
        }

        return result?.value ?? defaultValue
    }

    public func startPolling(every interval: TimeInterval) {
        polling = .enabled(interval: interval)
        fetch(trigger: .polling)
    }

    public func stopPolling() {
        polling = .disabled
        cancelCurrentRequest()
    }

    public func refetch() {
        fetch(trigger: .polling)
    }

    public func close() async {
        stopPolling()
        if let reporting {
            await reporting.stop()
            await reporting.flush()
        }
    }

    public func publisher(for flag: String) -> AnyPublisher<Tggl, Never> {
        $flags
            .compactMap({ tggl in
                guard let flags = tggl.first else { return nil }
                guard let flag = flags.first(where: { $0.key == flag }) else { return nil }
                return flag
            })
            .removeDuplicates(by: { $0.value == $1.value })
            .eraseToAnyPublisher()
    }

    public func errorPublisher() -> AnyPublisher<Error, Never> {
        $_lastError
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    public func getError() -> Error? {
        _lastError
    }

    public func isReadyPublisher() -> AnyPublisher<Bool, Never> {
        $_isReady.eraseToAnyPublisher()
    }

    public func getIsReady() -> Bool {
        _isReady
    }

    public func waitReady() async {
        if _isReady { return }
        await withCheckedContinuation { continuation in
            if _isReady {
                continuation.resume()
            } else {
                readyContinuations.append(continuation)
            }
        }
    }

    func setLastError(_ error: Error?) {
        _lastError = error
    }

    func markReady() {
        guard !_isReady else { return }
        _isReady = true
        for continuation in readyContinuations {
            continuation.resume()
        }
        readyContinuations.removeAll()
    }

    public func getContext() -> [String: Any] {
        context
    }

    public func setContext(context: [String: Any]) {
        self.context = context
        self.storage.save(context: context)
        fetch(trigger: .contextChange)
    }
}

extension TgglClient {
    nonisolated func subscribeToAppStateNotifications() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                if case .enabled = await polling {
                    await cancelCurrentRequest()
                }
            }
        }

        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                if case .enabled = await polling {
                    await fetch(trigger: .polling)
                }
            }
        }
        #endif
    }
}
