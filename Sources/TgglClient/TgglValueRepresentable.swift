import Foundation

/// A Swift type that can be converted to and from a ``TgglValue``.
///
/// Used to read flags with a typed default (`client.get("my-flag", default: false)`)
/// and to build contexts from plain Swift values (`["userId": user.id, "age": 42]`).
///
/// Built-in conformances: `Bool`, `String`, `Int`, `Double`, `TgglValue`,
/// and `Array`, `Dictionary` (with `String` keys) and `Optional` of conforming types.
public protocol TgglValueRepresentable {
    /// Returns `nil` when the value does not have the expected type.
    init?(tgglValue: TgglValue)
    var tgglValue: TgglValue { get }
}

extension TgglValue: TgglValueRepresentable {
    public init?(tgglValue: TgglValue) { self = tgglValue }
    public var tgglValue: TgglValue { self }
}

extension Bool: TgglValueRepresentable {
    public init?(tgglValue: TgglValue) {
        guard let value = tgglValue.boolValue else { return nil }
        self = value
    }
    public var tgglValue: TgglValue { .boolean(self) }
}

extension String: TgglValueRepresentable {
    public init?(tgglValue: TgglValue) {
        guard let value = tgglValue.stringValue else { return nil }
        self = value
    }
    public var tgglValue: TgglValue { .string(self) }
}

extension Double: TgglValueRepresentable {
    public init?(tgglValue: TgglValue) {
        guard let value = tgglValue.doubleValue else { return nil }
        self = value
    }
    public var tgglValue: TgglValue { .number(self) }
}

extension Int: TgglValueRepresentable {
    /// Only succeeds for numbers that are exact integers (`3` but not `3.5`).
    public init?(tgglValue: TgglValue) {
        guard let value = tgglValue.intValue else { return nil }
        self = value
    }
    public var tgglValue: TgglValue { .number(Double(self)) }
}

extension Array: TgglValueRepresentable where Element: TgglValueRepresentable {
    public init?(tgglValue: TgglValue) {
        guard let values = tgglValue.arrayValue else { return nil }
        var result: [Element] = []
        result.reserveCapacity(values.count)
        for value in values {
            guard let element = Element(tgglValue: value) else { return nil }
            result.append(element)
        }
        self = result
    }
    public var tgglValue: TgglValue { .array(map(\.tgglValue)) }
}

extension Dictionary: TgglValueRepresentable where Key == String, Value: TgglValueRepresentable {
    public init?(tgglValue: TgglValue) {
        guard let object = tgglValue.objectValue else { return nil }
        var result: [String: Value] = [:]
        for (key, value) in object {
            guard let converted = Value(tgglValue: value) else { return nil }
            result[key] = converted
        }
        self = result
    }
    public var tgglValue: TgglValue { .object(mapValues(\.tgglValue)) }
}

extension Optional: TgglValueRepresentable where Wrapped: TgglValueRepresentable {
    /// `.null` converts to `nil`; any other value must convert to `Wrapped`.
    public init?(tgglValue: TgglValue) {
        if case .null = tgglValue {
            self = .none
        } else if let wrapped = Wrapped(tgglValue: tgglValue) {
            self = .some(wrapped)
        } else {
            return nil
        }
    }
    public var tgglValue: TgglValue {
        switch self {
        case .none: return .null
        case .some(let wrapped): return wrapped.tgglValue
        }
    }
}

/// Context passed to ``TgglClient/setContext(_:)``: any property can be a plain Swift value.
///
/// ```swift
/// await client.setContext(["userId": user.id, "email": user.email, "plan": "premium", "seats": 3])
/// ```
/// `nil` values are sent as JSON `null`.
public typealias TgglContextInput = [String: (any TgglValueRepresentable)?]

extension Dictionary where Key == String, Value == (any TgglValueRepresentable)? {
    var tgglContext: [String: TgglValue] {
        mapValues { $0?.tgglValue ?? .null }
    }
}
