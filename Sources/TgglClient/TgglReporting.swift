import Foundation

/// Aggregates flag evaluations and sends them to `POST /report` in batches.
///
/// Wire format (one entry per distinct value/default pair):
/// ```json
/// {"clients":[{"id":"swift-client:2.0.0/TgglClient","flags":{"my-flag":[{"value":true,"default":false,"count":3}]}}]}
/// ```
/// `value` is omitted when the flag was not active (missing from the evaluation), as required by the API.
final class TgglReporter: @unchecked Sendable {
    struct Key: Hashable {
        let slug: String
        /// `nil` when the flag was inactive / unknown.
        let value: TgglValue?
        /// `nil` when the default could not be represented as JSON.
        let defaultValue: TgglValue?
    }

    private struct State {
        var pending: [Key: Int] = [:]
        var flushTask: Task<Void, Never>?
        var interval: TimeInterval
        var isClosed = false
    }

    let clientId: String
    private let transport: TgglTransport
    private let state: Locked<State>

    init(transport: TgglTransport, clientId: String, interval: TimeInterval) {
        self.transport = transport
        self.clientId = clientId
        self.state = Locked(State(interval: interval))
    }

    func record(slug: String, value: TgglValue?, defaultValue: TgglValue?) {
        state.withLock { state in
            guard !state.isClosed else { return }
            state.pending[Key(slug: slug, value: value, defaultValue: defaultValue), default: 0] += 1
            scheduleFlushIfNeeded(&state)
        }
    }

    /// Sends everything pending now. Evaluations are kept for the next batch if the network fails.
    func flush() async {
        let batch: [Key: Int] = state.withLock { state in
            let batch = state.pending
            state.pending = [:]
            return batch
        }
        guard !batch.isEmpty else { return }

        do {
            let body = try Self.body(for: batch, clientId: clientId)
            _ = try await transport.post(path: "report", body: body)
        } catch let error as TgglError where !error.isRetryable {
            // Invalid key or rejected payload: retrying would fail the same way.
        } catch {
            state.withLock { state in
                for (key, count) in batch {
                    state.pending[key, default: 0] += count
                }
            }
        }

        state.withLock { scheduleFlushIfNeeded(&$0) }
    }

    /// Stops the timer and sends the last batch.
    func close() async {
        state.withLock { state in
            state.isClosed = true
            state.flushTask?.cancel()
            state.flushTask = nil
        }
        await flush()
    }

    private func scheduleFlushIfNeeded(_ state: inout State) {
        guard !state.isClosed, state.flushTask == nil, state.interval > 0, !state.pending.isEmpty else { return }
        let nanoseconds = UInt64(state.interval * 1_000_000_000)
        state.flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.state.withLock { $0.flushTask = nil }
            await self.flush()
        }
    }

    // MARK: - Payload

    private struct Body: Encodable {
        struct Client: Encodable {
            let id: String
            let flags: [String: [Entry]]
        }

        struct Entry: Encodable {
            let value: TgglValue?
            let defaultValue: TgglValue?
            let count: Int

            enum CodingKeys: String, CodingKey {
                case value
                case defaultValue = "default"
                case count
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                // `.some(.null)` encodes as `null`; `nil` (inactive flag) omits the key.
                try container.encodeIfPresent(value, forKey: .value)
                try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
                try container.encode(count, forKey: .count)
            }
        }

        let clients: [Client]
    }

    static func body(for batch: [Key: Int], clientId: String) throws -> Data {
        var flags: [String: [Body.Entry]] = [:]
        for (key, count) in batch {
            flags[key.slug, default: []].append(Body.Entry(value: key.value, defaultValue: key.defaultValue, count: count))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Body(clients: [Body.Client(id: clientId, flags: flags)]))
    }
}
