//
//  Tggl.swift
//  TgglClient
//
//  Created by Pierre on 16/09/2025.
//

import Foundation

public struct Tggl {
    
    public enum TgglValueError: Error {
        case invalidType
    }

    public let `key`: String
    public let value: TgglValue
    
    enum CodingKeys: String, CodingKey {
        case `key`
        case `type`
        case stringValue
        case intValue
        case boolValue
    }
}

extension Tggl {
    var stringValue: String? {
        switch value {
            case .string(string: let string):
            return string
        default:
            return nil
        }
    }
    
    var intValue: Int? {
        switch value {
        case .number(int: let int):
            return int
        default:
            return nil
        }
    }
    
    var boolValue: Bool? {
        switch value {
        case .boolean(bool: let bool):
            return bool
        default:
            return nil
        }
    }
}

extension Tggl: Codable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try value.encode(to: encoder)
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        value = try TgglValue.init(from: decoder)
    }
}

extension Tggl: Equatable {
    
}
