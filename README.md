
# Tggl Swift client

## Getting Started

Add the package in Xcode
```
https://github.com/Tggl/swift-tggl-client
```

## Usage

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
