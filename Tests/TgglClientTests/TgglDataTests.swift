//
//  TgglDataTests.swift
//  TgglClient
//
//  Created by Pierre on 17/09/2025.
//

import XCTest
@testable import TgglClient

final class TgglDataTests: XCTestCase {
    
    let payload = """
[[{"key":"eric","type":"string","stringValue":"flag"}]]
"""
    
    func testDecodeTgglFromJSONFile() throws {

        // Load the file data
        guard let data = payload.data(using: .utf8) else {
            return XCTFail("No payload")
        }
        
        // Decode using JSONDecoder
        let decoder = JSONDecoder()
        let tggl = try decoder.decode([[Tggl]].self, from: data)
        
        XCTAssertTrue(tggl.first!.count > 0)
        
        guard let realFlags = tggl.first else {
            return XCTFail("No flags found")
        }
        
        guard let firstAndOnlyFlag = realFlags.first else {
            return XCTFail("No flag found")
        }
        
        XCTAssertEqual(firstAndOnlyFlag.key, "eric")
        switch firstAndOnlyFlag.value {
        case .string(let string):
            XCTAssertEqual(string, "flag")
        default:
            XCTFail("Expected string value")
        }
    }
    
    func testWhatYouStoreIsWhatYouGet() throws {
        
        let originalFlags = [[Tggl(key: "jaajint", value: .number(int: 7)),
                      Tggl(key: "jaajstr", value: .string(string: "spet")),
                      Tggl(key: "jaajbool", value: .boolean(bool: true))]]
        
        let storage = TgglStorage()

        storage.save(flags: originalFlags)
        
        let storedFlags = storage.getFlags()
                        
        guard let flags = storedFlags.first else {
            return XCTFail("No flags found")
        }
        
        XCTAssertEqual(flags.count, 3)
        
        XCTAssertEqual(flags[0].key, "jaajint")
        XCTAssertEqual(flags[1].key, "jaajstr")
        XCTAssertEqual(flags[2].key, "jaajbool")
        
        switch flags[0].value {
        case .number(int: let intValue): XCTAssertEqual(intValue, 7)
        default: XCTFail("wrong int")
        }

        switch flags[1].value {
        case .string(string: let stringValue): XCTAssertEqual(stringValue, "spet")
        default: XCTFail("wrong string")
        }
        
        switch flags[2].value {
        case .boolean(bool: let boolValue): XCTAssertEqual(boolValue, true)
        default: XCTFail("wrong bool")
        }
    }
}
