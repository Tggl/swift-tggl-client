# Tggl Swift client

Feature flags for iOS and macOS apps, powered by [Tggl](https://tggl.io).

- **Synchronous, typed reads**: `tggl.get("my-feature", default: false)` from any thread, no `await`.
- **Safe by design**: any inactive, deleted or unknown flag (or a network error) gives your default value.
- **SwiftUI ready**: `TgglClient` is an `ObservableObject`; Combine publishers are also available.
- **Offline first**: last flags are cached and used on the next launch, for the same context.
- iOS 16+, macOS 14+, Swift 5.9+.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/Tggl/swift-tggl-client", from: "2.0.0")
]
```

## Quick start

```swift
import TgglClient

let tggl = TgglClient(apiKey: "YOUR_CLIENT_API_KEY", context: ["userId": user.id, "plan": user.plan])

if tggl.get("new-checkout", default: false) {
    showNewCheckout()
}
```

> Use a **client** API key. Never ship a server key in an app.

## How Tggl evaluates flags

The client uses [remote evaluation](https://tggl.io/developers/evaluating-flags/remote-evaluation):

1. The context (user id, plan, country…) is sent to Tggl **once per context change**.
2. Tggl returns the value of every flag **active** for this context.
3. `get` reads that result in memory. It never calls the network.

A flag gives the **default value** you pass to `get` when it is inactive for the context,
archived or deleted, not loaded yet, or of an unexpected type. The default also applies when Tggl is unreachable.
Pick defaults that keep the app safe in all those cases.

Tggl does not push changes: call `refetch()` or enable polling to pick them up without a context change.

## Reading flags

```swift
let enabled = tggl.get("my-feature", default: false)         // Bool
let color   = tggl.get("button-color", default: "#000000")   // String
let limit   = tggl.get("max-items", default: 10)             // Int (exact integers only)
let ratio   = tggl.get("ratio", default: 0.5)                // Double
let tags    = tggl.get("tags", default: [String]())          // [String]
let raw     = tggl.get("config", default: TgglValue.null)    // TgglValue
```

The type of the default decides the expected type. A flag of another type returns the default.

### JSON flags

```swift
struct Banner: Codable { let title: String; let color: String }

let banner = tggl.decode("banner", as: Banner.self, default: Banner(title: "", color: "#000"))
```

### Null values

A flag can be active with a `null` value. It is read as `nil` with an optional default:

```swift
let coupon = tggl.get("coupon", default: Optional("WELCOME")) // nil if the flag is active with null
```

With a non-optional default, `null` is a type mismatch and returns the default.

### All flags

```swift
let all: [String: TgglValue] = tggl.flags
```

## Context

```swift
// Replace the whole context (e.g. on login)
await tggl.setContext(["userId": user.id, "email": user.email, "plan": "premium", "seats": 3])

// Merge some keys into the current context
await tggl.updateContext(["plan": "enterprise"])

// Logout
await tggl.setContext([:])
```

- Values can be `String`, `Int`, `Double`, `Bool`, arrays, dictionaries, `TgglValue`, or `nil`. A `nil` value is sent as `null`.
- Each change triggers one network call. The method returns once the new flags are applied.
- If contexts change quickly, only the response for the **latest** context is applied.
- When `context` is omitted at init, the context of the previous launch is reused.

## Readiness

The client is ready after the first response, even a failed one. It is also ready
immediately when flags were cached by a previous launch for the same context. Before that, `get` returns defaults.

```swift
await tggl.waitReady()
if tggl.isReady { … }
```

## SwiftUI

`TgglClient` is an `ObservableObject`. Views re-render when flags change:

```swift
@main
struct MyApp: App {
    @StateObject private var tggl = TgglClient(apiKey: "YOUR_CLIENT_API_KEY")

    var body: some Scene {
        WindowGroup { ContentView().environmentObject(tggl) }
    }
}

struct ContentView: View {
    @EnvironmentObject private var tggl: TgglClient

    var body: some View {
        if tggl.get("new-home", default: false) {
            NewHomeView()
        } else {
            HomeView()
        }
    }
}
```

For previews and tests, set flags locally without any network call:

```swift
let tggl = TgglClient(apiKey: "", options: TgglOptions(initialFetch: false, reporting: false, cache: .disabled))
tggl.setFlags(["new-home": true])
```

## Combine

```swift
tggl.publisher(for: "new-checkout", default: false)
    .sink { [weak self] enabled in self?.showNewCheckout = enabled }
    .store(in: &cancellables)
```

The publisher emits the current value, then each change. When a flag is switched off in Tggl,
it disappears from the evaluation and the publisher emits the **default value**.
Updates are delivered on the main thread.

Other publishers: `flagsPublisher`, `isReadyPublisher` and `errorPublisher`.

## Polling

```swift
let tggl = TgglClient(apiKey: "…", options: TgglOptions(pollingInterval: 60))
// or at any time
tggl.startPolling(every: 60)
tggl.stopPolling()
await tggl.refetch() // one-off refresh
```

On iOS, polling pauses in background and refreshes as soon as the app returns to the foreground.

## Errors

Reading flags never throws. Failed requests keep the last known flags, and you can observe them:

```swift
if let error = tggl.lastError { … }          // cleared by the next successful request

tggl.errorPublisher
    .sink { error in logger.error("\(error.localizedDescription)") }
    .store(in: &cancellables)
```

| Error | Retried |
|---|---|
| `.invalidApiKey` (401) | no, and other URLs are not tried |
| `.badRequest` (400) | no, and other URLs are not tried |
| `.httpStatus` 408, 429, 5xx | yes |
| `.httpStatus` (other) | no, next URL is tried |
| `.network` (offline, timeout…) | yes |
| `.invalidResponse` | no, next URL is tried |

## Options

```swift
let tggl = TgglClient(
    apiKey: "…",
    context: ["userId": "abc"],
    options: TgglOptions(
        baseUrls: [URL(string: "https://tggl-proxy.example.com")!], // Tggl Proxy, tried first
        fallbackToTgglApi: true,     // append https://api.tggl.io as last resort (default)
        maxRetries: 3,               // per URL, backoff 100 → 500 ms
        timeout: 8,                  // per request, in seconds
        initialFetch: true,          // fetch at init
        pollingInterval: nil,        // seconds, nil = disabled
        reporting: true,             // send evaluation stats to Tggl
        reportingInterval: 5,        // seconds
        appName: "MyApp",            // shown in the Tggl dashboard
        cache: .userDefaults,        // .disabled or .custom(MyStorage())
        session: .shared
    )
)
```

### Cache

By default, the last context and flags are stored in `UserDefaults`, separately for each API key.
Cached flags are only reused when the client starts with the same context (or without an explicit
context), so a new user never sees the previous user's flags.
The context may contain personal data (email, ids…). If you need encryption,
provide your own `TgglStorage` (e.g. backed by the Keychain):

```swift
final class KeychainStorage: TgglStorage {
    func load() -> Data? { … }
    func save(_ data: Data) { … }
}

TgglOptions(cache: .custom(KeychainStorage()))
```

### Tggl Proxy

URLs in `baseUrls` are tried in order, each with its own retries. `https://api.tggl.io` is appended
as the last fallback, so the app keeps working if your proxy is down. Set `fallbackToTgglApi: false`
if contexts must never leave your infrastructure.

## Reporting

Each call to `get` is counted and sent to Tggl every 5 seconds. This feeds the flag usage
statistics in the dashboard. Counts are kept and retried if the network fails, and flushed
when the app goes to background. Disable it with `reporting: false`, or send now with
`await tggl.flushReporting()`.

## Shutdown

```swift
await tggl.close() // stops polling and network calls, sends the last reporting batch
```

## Migrating from 1.x

| 1.x | 2.0 |
|---|---|
| `TgglClient` is an `actor`, every call needs `await` | `get`, `flags`, `context`, `isReady` and `lastError` are synchronous; only `setContext`, `refetch`, `waitReady` and `close` are `async` |
| `await client.get(slug: "f", defaultValue: .boolean(false))` → `TgglValue` | `client.get("f", default: false)` → `Bool` |
| `getFlags()` → `[Tggl]` | `flags` → `[String: TgglValue]` |
| `setContext(context: [String: Any])` | `setContext(_:)` with typed values, plus `updateContext(_:)` |
| `publisher(for:)` → `Tggl`, silent when the flag is switched off | `publisher(for:default:)` → typed value, emits the default when the flag is switched off |
| `getIsReady()`, `getError()`, `isReadyPublisher()`, `errorPublisher()` | `isReady`, `lastError`, `isReadyPublisher`, `errorPublisher` |
| `TgglClient(apiKey:baseUrls:session:maxRetries:timeoutMs:appName:reporting:initialFetch:)` | `TgglClient(apiKey:context:options:)` |
| `Tggl` struct | removed: use `TgglValue` |

The 1.x cache (`UserDefaults` suite `tggl`) is not read by 2.0. The first launch after the update
starts from defaults until the first response arrives.

## Support

Report issues on [GitHub](https://github.com/Tggl/swift-tggl-client/issues).
