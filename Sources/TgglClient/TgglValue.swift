//
//  TgglValue.swift
//
//
//  Created by Pierre on 10/09/2024.
//

import Foundation

public struct Tggl {
    
    public enum TgglValueError: Error {
        case invalidType
    }

    let `key`: String
    let value: TgglValue
    
    enum TgglValue {
        case string(string: String)
        case number(int: Int)
        case boolean(bool: Bool)
    }
    
    enum CodingKeys: String, CodingKey {
        case `key`
        case `type`
    }
    
    enum StringCodingKeys: String, CodingKey {
        case stringValue
    }
    
    enum IntCodingKeys: String, CodingKey {
        case intValue
    }
    
    enum BoolCodingKeys: String, CodingKey {
        case boolValue
    }
}

extension Tggl: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try container.decode(String.self, forKey: .key)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "string":
            let container = try decoder.container(keyedBy: StringCodingKeys.self)
            let stringValue = try container.decode(String.self, forKey: .stringValue)
            self.value = .string(string: stringValue)
            return
        case "int":
            let container = try decoder.container(keyedBy: IntCodingKeys.self)
            let intValue = try container.decode(Int.self, forKey: .intValue)
            self.value = .number(int: intValue)
            return
        case "bool":
            let container = try decoder.container(keyedBy: BoolCodingKeys.self)
            let boolValue = try container.decode(Bool.self, forKey: .boolValue)
            self.value = .boolean(bool: boolValue)
            return
        default:
            print("unknown type: \(type)")
            throw TgglValueError.invalidType
        }

        //{\"key\":\"eric\",\"type\":\"string\",\"stringValue\":\"flag\"}
    }
}

