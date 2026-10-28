import Foundation

/// Persists the last known flags so that the app starts with them on the next launch
/// (the client is then ready immediately, before the network answers).
///
/// The client handles serialization; a storage only stores opaque bytes.
public protocol TgglStorage: Sendable {
    func load() -> Data?
    func save(_ data: Data)
}

/// Default storage, backed by `UserDefaults`.
///
/// Each API key gets its own entry, so two clients (e.g. two projects, or dev and prod)
/// never share their cache.
///
/// - Note: The cached snapshot contains the evaluation context (user id, email…).
///   Provide your own ``TgglStorage`` (e.g. Keychain or an encrypted file) if your
///   context holds sensitive data, or disable caching with ``TgglOptions/Cache/disabled``.
public final class TgglUserDefaultsStorage: TgglStorage, @unchecked Sendable {
    // UserDefaults is documented as thread-safe.
    private let defaults: UserDefaults
    private let key: String

    public init(key: String, defaults: UserDefaults = UserDefaults(suiteName: "io.tggl.client") ?? .standard) {
        self.key = key
        self.defaults = defaults
    }

    /// Storage dedicated to a given API key.
    public convenience init(apiKey: String) {
        self.init(key: "tggl.v2.\(Self.fingerprint(of: apiKey))")
    }

    public func load() -> Data? {
        defaults.data(forKey: key)
    }

    public func save(_ data: Data) {
        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }

    /// Stable, non-reversible fingerprint (FNV-1a 64) so the raw API key is not used as a key.
    static func fingerprint(of string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

/// In-memory storage: useful for tests, previews, or sharing state between clients.
public final class TgglMemoryStorage: TgglStorage, @unchecked Sendable {
    private let data: Locked<Data?>

    public init(data: Data? = nil) {
        self.data = Locked(data)
    }

    public func load() -> Data? {
        data.withLock { $0 }
    }

    public func save(_ data: Data) {
        self.data.withLock { $0 = data }
    }
}

/// What the client persists: the context used for the last successful evaluation and its result.
struct TgglSnapshot: Codable, Equatable {
    var context: [String: TgglValue]
    var flags: [String: TgglValue]
}
