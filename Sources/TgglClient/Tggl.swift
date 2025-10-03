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

    let `key`: String
    let value: TgglValue
    
    enum CodingKeys: String, CodingKey {
        case `key`
        case `type`
        case stringValue
        case intValue
        case boolValue
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
