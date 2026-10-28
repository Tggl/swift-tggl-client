import Foundation

/// A JSON-like value, used both for flag values and for context properties.
///
/// `TgglValue` can be written with literals:
/// ```swift
/// let value: TgglValue = ["plan": "premium", "seats": 3, "beta": true, "tags": ["a", "b"], "coupon": nil]
/// ```
public enum TgglValue: Hashable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case array([TgglValue])
    case object([String: TgglValue])
    case null
}

// MARK: - Accessors

extension TgglValue {
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    /// The number as an `Int`, only if it is an exact integer.
    public var intValue: Int? {
        if case .number(let value) = self { return Int(exactly: value) }
        return nil
    }

    public var boolValue: Bool? {
        if case .boolean(let value) = self { return value }
        return nil
    }

    public var arrayValue: [TgglValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: TgglValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

// MARK: - Codable (plain JSON representation)

extension TgglValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([TgglValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: TgglValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode TgglValue")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Literals

extension TgglValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension TgglValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension TgglValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}

extension TgglValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .boolean(value) }
}

extension TgglValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension TgglValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: TgglValue...) { self = .array(elements) }
}

extension TgglValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, TgglValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

extension TgglValue: CustomStringConvertible {
    public var description: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let string = String(data: data, encoding: .utf8) else {
            return "TgglValue"
        }
        return string
    }
}
