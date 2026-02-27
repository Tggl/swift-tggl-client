//
//  TgglValue.swift
//
//
//  Created by Pierre on 10/09/2024.
//

import Foundation

public enum TgglValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case array([TgglValue])
    case object([String: TgglValue])
    case null

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s):
            try container.encode(s)
        case .number(let n):
            try container.encode(n)
        case .boolean(let b):
            try container.encode(b)
        case .array(let a):
            try container.encode(a)
        case .object(let o):
            try container.encode(o)
        case .null:
            try container.encodeNil()
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }

        if let b = try? container.decode(Bool.self) {
            self = .boolean(b)
            return
        }

        if let n = try? container.decode(Double.self) {
            self = .number(n)
            return
        }

        if let s = try? container.decode(String.self) {
            self = .string(s)
            return
        }

        if let a = try? container.decode([TgglValue].self) {
            self = .array(a)
            return
        }

        if let o = try? container.decode([String: TgglValue].self) {
            self = .object(o)
            return
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Unable to decode TgglValue"
            )
        )
    }
}
