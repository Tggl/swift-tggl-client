import Foundation

public struct Tggl {

    public enum TgglValueError: Error {
        case invalidType
    }

    public let key: String
    public let value: TgglValue

    enum CodingKeys: String, CodingKey {
        case key
        case type
        case stringValue
        case numberValue
        case booleanValue
        case jsonValue
    }
}

extension Tggl {
    var stringValue: String? {
        if case .string(let s) = value { return s }
        return nil
    }

    var numberValue: Double? {
        if case .number(let n) = value { return n }
        return nil
    }

    var intValue: Int? {
        guard case .number(let n) = value,
              n == n.rounded(),
              n >= Double(Int.min),
              n <= Double(Int.max) else { return nil }
        return Int(n)
    }

    var booleanValue: Bool? {
        if case .boolean(let b) = value { return b }
        return nil
    }

    var arrayValue: [TgglValue]? {
        if case .array(let a) = value { return a }
        return nil
    }

    var objectValue: [String: TgglValue]? {
        if case .object(let o) = value { return o }
        return nil
    }

    var isNull: Bool {
        if case .null = value { return true }
        return false
    }
}

extension Tggl: Codable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)

        switch value {
        case .string(let s):
            try container.encode("string", forKey: .type)
            try container.encode(s, forKey: .stringValue)
        case .number(let n):
            try container.encode("number", forKey: .type)
            try container.encode(n, forKey: .numberValue)
        case .boolean(let b):
            try container.encode("boolean", forKey: .type)
            try container.encode(b, forKey: .booleanValue)
        case .array, .object:
            try container.encode("json", forKey: .type)
            try container.encode(value, forKey: .jsonValue)
        case .null:
            try container.encode("null", forKey: .type)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "string":
            let s = try container.decode(String.self, forKey: .stringValue)
            value = .string(s)
        case "number":
            let n = try container.decode(Double.self, forKey: .numberValue)
            value = .number(n)
        case "boolean":
            let b = try container.decode(Bool.self, forKey: .booleanValue)
            value = .boolean(b)
        case "json":
            value = try container.decode(TgglValue.self, forKey: .jsonValue)
        case "null":
            value = .null
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unsupported type: \(type)"
                )
            )
        }
    }
}

extension Tggl: Equatable {}
