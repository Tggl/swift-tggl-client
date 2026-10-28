import Combine
import Foundation
#if os(iOS)
import UIKit
#endif

/// Tggl client for apps (remote evaluation).
///
/// The client sends the context to Tggl once per context change, keeps the evaluated
/// flags in memory, and answers ``get(_:default:)`` synchronously, from any thread.
///
/// ```swift
/// let tggl = TgglClient(apiKey: "CLIENT_API_KEY", context: ["userId": user.id])
///
/// if tggl.get("new-onboarding", default: false) { … }
/// let color = tggl.get("button-color", default: "#000000")
/// ```
///
/// Business rules (identical to the other Tggl SDKs):
/// - Only active flags are returned by the API. A flag that is inactive, archived, deleted,
///   not loaded yet, or of an unexpected type evaluates to the **default value**.
/// - The client never throws: network errors keep the last known flags and are exposed
///   through ``lastError`` / ``errorPublisher``.
/// - When the context changes, only the response for the latest context is applied.
public final class TgglClient: ObservableObject, @unchecked Sendable {
    public static let sdkVersion = "2.0.0"

    private struct State {
        var context: [String: TgglValue]
        var flags: [String: TgglValue]
        var isReady: Bool
        var lastError: TgglError?
        /// Incremented on each context change; responses for an older generation are discarded.
        var generation = 0
        var fetchTask: Task<Void, Never>?
        var pollingInterval: TimeInterval?
        var pollingTask: Task<Void, Never>?
        var isInBackground = false
        var isClosed = false
        var readyWaiters: [CheckedContinuation<Void, Never>] = []
        var observers: [NSObjectProtocol] = []
    }

    private let state: Locked<State>
    private let transport: TgglTransport
    private let storage: (any TgglStorage)?
    private let reporter: TgglReporter?

    private let flagsSubject: CurrentValueSubject<[String: TgglValue], Never>
    private let readySubject: CurrentValueSubject<Bool, Never>
    private let errorSubject = PassthroughSubject<TgglError, Never>()

    /// Client identifier shown in the Tggl dashboard, e.g. `swift-client:2.0.0/TgglClient/MyApp`.
    public let clientId: String

    // MARK: - Lifecycle

    /// Creates a client and, unless disabled in `options`, starts evaluating flags right away.
    ///
    /// - Parameters:
    ///   - apiKey: A **client** API key. Never ship a server key in an app.
    ///   - context: Initial context. When `nil`, the context cached from the previous launch is reused.
    ///     Cached flags are only used when they were evaluated for this same context.
    ///   - options: Network, polling, reporting and cache configuration.
    public init(apiKey: String, context: TgglContextInput? = nil, options: TgglOptions = TgglOptions()) {
        let storage = options.resolvedStorage(apiKey: apiKey)
        let snapshot = storage?.load().flatMap { try? JSONDecoder().decode(TgglSnapshot.self, from: $0) }

        let initialContext = context?.tgglContext ?? snapshot?.context ?? [:]
        // Cached flags are only reused for the context they were evaluated for
        // (never show the previous user's flags to a new user). They make the client ready immediately.
        let cachedFlags = snapshot.flatMap { $0.context == initialContext ? $0.flags : nil }
        let initialFlags = cachedFlags ?? [:]
        let isReady = cachedFlags != nil

        var clientId = "swift-client:\(TgglClient.sdkVersion)/TgglClient"
        if let appName = options.appName, !appName.isEmpty {
            clientId += "/\(appName)"
        }
        self.clientId = clientId

        let transport = TgglTransport(
            apiKey: apiKey,
            baseUrls: options.resolvedBaseUrls,
            session: options.session,
            maxRetries: options.maxRetries,
            timeout: options.timeout
        )
        self.transport = transport
        self.storage = storage
        self.state = Locked(State(context: initialContext, flags: initialFlags, isReady: isReady))
        self.reporter = options.reporting
            ? TgglReporter(transport: transport, clientId: clientId, interval: options.reportingInterval)
            : nil

        self.flagsSubject = CurrentValueSubject(initialFlags)
        self.readySubject = CurrentValueSubject(isReady)

        observeAppLifecycle()

        if options.initialFetch {
            state.withLock { state in
                state.fetchTask = makeFetchTask(generation: state.generation, context: state.context)
            }
        }
        if let interval = options.pollingInterval {
            startPolling(every: interval)
        }
    }

    deinit {
        let (tasks, observers) = state.withLock { state in
            ([state.fetchTask, state.pollingTask], state.observers)
        }
        tasks.forEach { $0?.cancel() }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Stops polling and network activity, then sends the pending reporting batch.
    /// Await it before the client is released (e.g. in tests or on logout).
    public func close() async {
        let (tasks, observers, waiters) = state.withLock { state in
            state.isClosed = true
            let result = ([state.fetchTask, state.pollingTask], state.observers, state.readyWaiters)
            state.fetchTask = nil
            state.pollingTask = nil
            state.pollingInterval = nil
            state.observers = []
            state.readyWaiters = []
            return result
        }
        tasks.forEach { $0?.cancel() }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        waiters.forEach { $0.resume() }
        await reporter?.close()
    }

    // MARK: - Reading flags

    /// Value of a flag, or `defaultValue` if the flag is inactive, unknown, not loaded yet,
    /// or not of type `T`. Never performs a network call.
    ///
    /// ```swift
    /// let enabled = tggl.get("my-feature", default: false)
    /// let limit = tggl.get("max-items", default: 10)
    /// let title = tggl.get("home-title", default: "Welcome")
    /// let tags = tggl.get("tags", default: [String]())
    /// ```
    ///
    /// Choose a default that keeps the app safe if Tggl is unreachable or the flag is deleted.
    public func get<T: TgglValueRepresentable>(_ slug: String, default defaultValue: T) -> T {
        let raw = state.withLock { $0.flags[slug] }
        reporter?.record(slug: slug, value: raw, defaultValue: defaultValue.tgglValue)
        return Self.resolve(raw, default: defaultValue)
    }

    /// Decodes a JSON flag into a `Decodable` type, or returns `defaultValue`.
    ///
    /// ```swift
    /// struct Banner: Decodable { let title: String; let color: String }
    /// let banner = tggl.decode("banner", as: Banner.self, default: Banner(title: "", color: "#000"))
    /// ```
    public func decode<T: Decodable>(_ slug: String, as type: T.Type = T.self, default defaultValue: T) -> T {
        let raw = state.withLock { $0.flags[slug] }
        reporter?.record(slug: slug, value: raw, defaultValue: Self.encodeToValue(defaultValue))
        guard let raw,
              let data = try? JSONEncoder().encode(raw),
              let decoded = try? JSONDecoder().decode(T.self, from: data)
        else { return defaultValue }
        return decoded
    }

    /// All flags active for the current context, keyed by slug. Not reported to Tggl.
    public var flags: [String: TgglValue] {
        state.withLock { $0.flags }
    }

    // MARK: - Context

    /// The context used for the current evaluation.
    public var context: [String: TgglValue] {
        state.withLock { $0.context }
    }

    /// Replaces the whole context and re-evaluates all flags (one network call).
    ///
    /// Returns once the new flags are applied (or the request failed). If another context
    /// is set in the meantime, only the latest one is applied.
    ///
    /// ```swift
    /// await tggl.setContext(["userId": user.id, "email": user.email, "plan": user.plan])
    /// await tggl.setContext([:]) // after logout
    /// ```
    public func setContext(_ context: TgglContextInput) async {
        await applyContext { _ in context.tgglContext }
    }

    /// Merges `partial` into the current context (other keys are kept) and re-evaluates flags.
    /// Set a key to `nil` to send it as `null`.
    public func updateContext(_ partial: TgglContextInput) async {
        await applyContext { current in
            current.merging(partial.tgglContext) { _, new in new }
        }
    }

    private func applyContext(_ transform: ([String: TgglValue]) -> [String: TgglValue]) async {
        let task: Task<Void, Never>? = state.withLock { state in
            guard !state.isClosed else { return nil }
            state.context = transform(state.context)
            state.generation += 1
            state.fetchTask?.cancel()
            let task = makeFetchTask(generation: state.generation, context: state.context)
            state.fetchTask = task
            return task
        }
        await task?.value
    }

    // MARK: - Refresh & polling

    /// Re-evaluates flags for the current context. Joins the in-flight request if there is one.
    public func refetch() async {
        let task: Task<Void, Never>? = state.withLock { state in
            guard !state.isClosed else { return nil }
            if let task = state.fetchTask { return task }
            let task = makeFetchTask(generation: state.generation, context: state.context)
            state.fetchTask = task
            return task
        }
        await task?.value
    }

    /// Re-evaluates flags every `interval` seconds. Calling it again changes the interval.
    /// Flag changes are not pushed by Tggl: polling is the way to pick them up without a context change.
    public func startPolling(every interval: TimeInterval) {
        guard interval > 0 else { return stopPolling() }
        state.withLock { state in
            guard !state.isClosed else { return }
            state.pollingInterval = interval
            state.pollingTask?.cancel()
            state.pollingTask = state.isInBackground ? nil : makePollingTask(interval: interval)
        }
    }

    public func stopPolling() {
        state.withLock { state in
            state.pollingInterval = nil
            state.pollingTask?.cancel()
            state.pollingTask = nil
        }
    }

    public var isPolling: Bool {
        state.withLock { $0.pollingInterval != nil }
    }

    private func makePollingTask(interval: TimeInterval) -> Task<Void, Never> {
        let nanoseconds = UInt64(interval * 1_000_000_000)
        return Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                guard let client = self else { return }
                await client.refetch()
            }
        }
    }

    // MARK: - Readiness & errors

    /// `true` once flags are known: after the first response (even a failed one)
    /// or immediately when flags were cached by a previous launch.
    /// Before that, ``get(_:default:)`` returns defaults.
    public var isReady: Bool {
        state.withLock { $0.isReady }
    }

    /// Suspends until ``isReady`` is `true`.
    public func waitReady() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = state.withLock { state -> Bool in
                if state.isReady || state.isClosed { return true }
                state.readyWaiters.append(continuation)
                return false
            }
            if resumeNow {
                continuation.resume()
            }
        }
    }

    /// Error of the last request, `nil` once a request succeeds.
    public var lastError: TgglError? {
        state.withLock { $0.lastError }
    }

    // MARK: - Local overrides

    /// Replaces flags locally without any network call (SwiftUI previews, tests, offline mode).
    /// An in-flight or future fetch will overwrite them.
    @MainActor
    public func setFlags(_ flags: [String: (any TgglValueRepresentable)?]) {
        let newFlags = flags.tgglContext
        objectWillChange.send()
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.flags = newFlags
            return markReady(&state)
        }
        flagsSubject.send(newFlags)
        readySubject.send(true)
        waiters.forEach { $0.resume() }
    }

    // MARK: - Reporting

    /// Sends pending evaluation statistics now (they are otherwise sent every few seconds).
    public func flushReporting() async {
        await reporter?.flush()
    }

    // MARK: - Fetch

    private func makeFetchTask(generation: Int, context: [String: TgglValue]) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            let result: Result<[String: TgglValue], TgglError>
            do {
                let body = try TgglTypedFlags.requestBody(context: context)
                let data = try await self.transport.post(path: "typed-flags", body: body)
                result = .success(try TgglTypedFlags.parse(data))
            } catch is CancellationError {
                return
            } catch let error as TgglError {
                result = .failure(error)
            } catch {
                result = .failure(.invalidResponse(String(describing: error)))
            }
            guard !Task.isCancelled else { return }
            await self.complete(generation: generation, context: context, result: result)
        }
    }

    @MainActor
    private func complete(generation: Int, context: [String: TgglValue], result fetchResult: Result<[String: TgglValue], TgglError>) {
        struct Outcome {
            var flagsChanged = false
            var errorChanged = false
            var becameReady = false
            var waiters: [CheckedContinuation<Void, Never>] = []
            var hasChanges: Bool { flagsChanged || errorChanged || becameReady }
        }

        let outcome: Outcome? = state.withLock { state in
            // A newer context was set meanwhile (or the client was closed): drop this response.
            guard state.generation == generation, !state.isClosed else { return nil }
            var result = Outcome()
            state.fetchTask = nil
            let previousError = state.lastError
            switch fetchResult {
            case .success(let flags):
                result.flagsChanged = state.flags != flags
                state.flags = flags
                state.lastError = nil
            case .failure(let error):
                state.lastError = error
            }
            result.errorChanged = previousError != state.lastError
            result.becameReady = !state.isReady
            result.waiters = markReady(&state)
            return result
        }
        guard let outcome else { return }

        if outcome.hasChanges {
            objectWillChange.send()
        }

        switch fetchResult {
        case .success(let flags):
            if let storage, let data = try? JSONEncoder().encode(TgglSnapshot(context: context, flags: flags)) {
                storage.save(data)
            }
            if outcome.flagsChanged {
                flagsSubject.send(flags)
            }
        case .failure(let error):
            errorSubject.send(error)
        }

        if outcome.becameReady {
            readySubject.send(true)
        }
        outcome.waiters.forEach { $0.resume() }
    }

    private func markReady(_ state: inout State) -> [CheckedContinuation<Void, Never>] {
        state.isReady = true
        let waiters = state.readyWaiters
        state.readyWaiters = []
        return waiters
    }

    // MARK: - App lifecycle

    private func observeAppLifecycle() {
        #if os(iOS)
        let center = NotificationCenter.default
        let background = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.didEnterBackground()
        }
        let foreground = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.willEnterForeground()
        }
        state.withLock { $0.observers = [background, foreground] }
        #endif
    }

    #if os(iOS)
    private func didEnterBackground() {
        state.withLock { state in
            state.isInBackground = true
            state.pollingTask?.cancel()
            state.pollingTask = nil
        }
        // Send the pending reporting batch before the app gets suspended.
        guard let reporter else { return }
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Tggl reporting flush") { expired in
            guard !expired else { return }
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await reporter.flush()
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 5)
        }
    }

    private func willEnterForeground() {
        let shouldRefresh: Bool = state.withLock { state in
            state.isInBackground = false
            guard !state.isClosed, let interval = state.pollingInterval else { return false }
            state.pollingTask?.cancel()
            state.pollingTask = makePollingTask(interval: interval)
            return true
        }
        // Flags may have changed while in background: refresh right away when polling is on.
        if shouldRefresh {
            Task { await refetch() }
        }
    }
    #endif

    // MARK: - Helpers

    static func resolve<T: TgglValueRepresentable>(_ raw: TgglValue?, default defaultValue: T) -> T {
        guard let raw, let value = T(tgglValue: raw) else { return defaultValue }
        return value
    }

    private static func encodeToValue<T>(_ value: T) -> TgglValue? {
        guard let encodable = value as? any Encodable,
              let data = try? JSONEncoder().encode(encodable)
        else { return nil }
        return try? JSONDecoder().decode(TgglValue.self, from: data)
    }
}

// MARK: - Combine

extension TgglClient {
    /// Emits the current value of a flag, then every time it changes.
    ///
    /// Emits `defaultValue` when the flag becomes inactive (it is then absent from the evaluation),
    /// so a feature switched off in Tggl is switched off in the app too.
    /// Updates are delivered on the main thread.
    ///
    /// ```swift
    /// tggl.publisher(for: "new-checkout", default: false)
    ///     .sink { [weak self] enabled in self?.showNewCheckout = enabled }
    ///     .store(in: &cancellables)
    /// ```
    public func publisher<T: TgglValueRepresentable & Equatable>(for slug: String, default defaultValue: T) -> AnyPublisher<T, Never> {
        flagsSubject
            .map { $0[slug] }
            .removeDuplicates()
            .handleEvents(receiveOutput: { [weak reporter = self.reporter] raw in
                reporter?.record(slug: slug, value: raw, defaultValue: defaultValue.tgglValue)
            })
            .map { Self.resolve($0, default: defaultValue) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// All active flags, emitted on subscription and whenever the evaluation changes.
    public var flagsPublisher: AnyPublisher<[String: TgglValue], Never> {
        flagsSubject.eraseToAnyPublisher()
    }

    /// Emits `false` then `true` once the client is ready.
    public var isReadyPublisher: AnyPublisher<Bool, Never> {
        readySubject.removeDuplicates().eraseToAnyPublisher()
    }

    /// Emits every failed request. Errors never interrupt flag reading.
    public var errorPublisher: AnyPublisher<TgglError, Never> {
        errorSubject.eraseToAnyPublisher()
    }
}
