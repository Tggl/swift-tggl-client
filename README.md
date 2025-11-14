
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
    let publisher = await tgglClient.getSlugPublisher(slug: "bgColor")
```

Use the value
```
    publisher
        .receive(on: RunLoop.main)
        .sink { [weak self] tggl in
            switch tggl.value {
            case .string(let string):
                self?.backgroundColor = Color(hex: string)
            default:
                break
            }
        }
        .store(in: &cancellables)
```
