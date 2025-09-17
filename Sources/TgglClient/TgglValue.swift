//
//  TgglValue.swift
//
//
//  Created by Pierre on 10/09/2024.
//

import Foundation

enum TgglValue: Codable {
    case string(string: String)
    case number(int: Int)
    case boolean(bool: Bool)

    private enum CodingKeys: String, CodingKey {
        case type
        case stringValue
        case intValue
        case boolValue
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let s):
            try container.encode("string", forKey: .type)
            try container.encode(s, forKey: CodingKeys.stringValue)
        case .number(let i):
            try container.encode("number", forKey: .type)
            try container.encode(i, forKey: CodingKeys.intValue)
        case .boolean(let b):
            try container.encode("boolean", forKey: .type)
            try container.encode(b, forKey: CodingKeys.boolValue)
        }
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "string":
            let s = try container.decode(String.self, forKey: .stringValue)
            self = .string(string: s)
        case "number":
            let i = try container.decode(Int.self, forKey: .intValue)
            self = .number(int: i)
        case "boolean":
            let b = try container.decode(Bool.self, forKey: .boolValue)
            self = .boolean(bool: b)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: container.codingPath,
                                      debugDescription: "Type \(type) non supporté")
            )
        }
    }
}
