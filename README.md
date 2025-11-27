
# Tggl Swift client

## Getting Started

Add the package in Xcode
```
https://github.com/Tggl/swift-tggl-client
```

or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Tggl/swift-tggl-client", from: "1.0.0")
]
```

## Quick Start

Instantiate the client
```
    let tgglClient: TgglClient
    tgglClient = TgglClient(apiKey: "abc123")
```

Get the publisher
```
    let publisher = await tgglClient.publisher(for: "myFlag")
```

Use the value
```
    publisher
        .sink { tggl in
            if let string = tggl.stringValue {
                self?.variationValue = string
            }
        }
        .store(in: &cancellables)
```

## Core Concepts

### TgglClient

The main actor-based client that manages feature flags.

### Tggl

A struct representing a single feature flag with:
- `key`: The flag identifier/slug
- `value`: A `TgglValue` that can be a string, number, or boolean

### TgglValue

An enum representing the typed value of a flag:
- `.string(string: String)` - String value
- `.number(int: Int)` - Integer value
- `.boolean(bool: Bool)` - Boolean value

### Context

User/application context data used to evaluate feature flags. Context is a dictionary of `[String: Any]` that gets sent to the Tggl API to determine which flags should be active and their values.

## Initialization

### Basic Initialization

```swift
let client = TgglClient(apiKey: "YOUR_API_KEY")
```

### Custom API URL

```swift
let client = TgglClient(
    apiKey: "YOUR_API_KEY",
    url: "https://custom.tggl.endpoint/typed-flags"
)
```

The client automatically:
- Loads previously stored flags from local storage
- Loads the last known context from local storage
- Prepares for flag evaluation

## Setting Context

Context is crucial for feature flag evaluation. It typically includes user information, environment details, or any other data used in your flag rules.

```swift
await client.setContext(context: [
    "userId": "user_123",
    "email": "user@example.com",
    "plan": "premium",
    "country": "US"
])
```

**What happens when you set context:**
1. The context is saved to local storage (UserDefaults)
2. Any in-flight network requests are cancelled
3. A new request is made to fetch flags based on the new context
4. Publishers are updated with new flag values

### Getting Current Context

```swift
let currentContext = await client.getContext()
print("Current context: \(currentContext)")
```

## Reading Flags

### Check if a Flag is Active

```swift
let isFeatureEnabled = await client.isActive(slug: "newFeature")
if isFeatureEnabled {
    // Feature is enabled for this user
}
```

### Get Flag Value

```swift
if let flag = await client.get(slug: "welcomeMessage") {
    // Access typed values
    if let message = flag.stringValue {
        print("Welcome message: \(message)")
    }
}
```

### Get Flag with Default Value

```swift
let flag = await client.get(slug: "maxItems", defaultValue: nil)
if let count = flag?.intValue {
    print("Max items: \(count)")
}
```

### Get All Flags

```swift
// Returns [Tggl] - array of flag arrays
if let flags = await client.getFlags() {
    for flag in flags {
        print("\(flag.key): \(flag.value)")
    }
}
```

The client provides Combine publishers for reactive flag value changes.

### Basic Publisher Usage

```swift
import Combine

var cancellables = Set<AnyCancellable>()

let publisher = await client.publisher(for: "myFlag")

publisher
    .sink { flag in
        if let stringValue = flag.stringValue {
            print("Flag updated: \(stringValue)")
        }
    }
    .store(in: &cancellables)
```

## Polling

Enable automatic polling to keep flags up-to-date in real-time.

### Start Polling

```swift
await client.startPolling(every: 60.0) // Poll every 60 seconds
```

### Stop Polling

```swift
await client.stopPolling()
```

### How Polling Works

1. When enabled, the client fetches flags at the specified interval
2. If context changes during polling, the current request is cancelled and a new one starts immediately
3. Polling continues in the background until explicitly stopped
4. Failed requests don't stop polling; it will retry on the next interval

### Best Practices

- Use reasonable intervals (30-300 seconds) to avoid excessive API calls

## Support

For issues and questions, please visit [GitHub Issues](https://github.com/Tggl/swift-tggl-client/issues).
