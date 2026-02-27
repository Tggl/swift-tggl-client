import XCTest
@testable import TgglClient

final class TgglDataTests: XCTestCase {

    override func setUp() async throws {
        let storage = TgglStorage()
        storage.clear()
    }

    let payload = """
[[{"key":"eric","type":"string","stringValue":"flag"}]]
"""

    func testDecodeTgglFromJSONFile() throws {
        guard let data = payload.data(using: .utf8) else {
            return XCTFail("No payload")
        }

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
        let originalFlags = [[Tggl(key: "jaajint", value: .number(7)),
                      Tggl(key: "jaajstr", value: .string("spet")),
                      Tggl(key: "jaajbool", value: .boolean(true))]]

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
        case .number(let n): XCTAssertEqual(n, 7)
        default: XCTFail("wrong number")
        }
        switch flags[1].value {
        case .string(let s): XCTAssertEqual(s, "spet")
        default: XCTFail("wrong string")
        }
        switch flags[2].value {
        case .boolean(let b): XCTAssertEqual(b, true)
        default: XCTFail("wrong bool")
        }
    }

    func testContext() async throws {
        let storage = TgglStorage()
        storage.save(context: [:])

        let client = TgglClient(apiKey: "", reporting: false, initialFetch: false)
        await client.setContext(context: ["keyTest": "valueTest"])

        let newStoredContext = storage.getContext()
        XCTAssertEqual(newStoredContext.keys.count, 1)
        XCTAssertEqual(newStoredContext.keys.first, "keyTest")
        XCTAssertEqual(newStoredContext["keyTest"] as! String, "valueTest")
    }

    // MARK: - TgglValue plain JSON decoding

    func testDecodeNumberValue() throws {
        let json = "3.14"
        let data = Data(json.utf8)
        let value = try JSONDecoder().decode(TgglValue.self, from: data)
        if case .number(let n) = value {
            XCTAssertEqual(n, 3.14, accuracy: 0.001)
        } else {
            XCTFail("Expected .number, got \(value)")
        }
    }

    func testDecodeIntegerAsNumber() throws {
        let json = "42"
        let data = Data(json.utf8)
        let value = try JSONDecoder().decode(TgglValue.self, from: data)
        if case .number(let n) = value {
            XCTAssertEqual(n, 42)
        } else {
            XCTFail("Expected .number, got \(value)")
        }
    }

    func testEncodeDecodeNumber() throws {
        let original = TgglValue.number(2.718)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TgglValue.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - TgglValue array (plain JSON)

    func testDecodeArrayValue() throws {
        let json = """
        ["a", 1, true]
        """
        let data = Data(json.utf8)
        let value = try JSONDecoder().decode(TgglValue.self, from: data)
        if case .array(let arr) = value {
            XCTAssertEqual(arr.count, 3)
            XCTAssertEqual(arr[0], .string("a"))
            XCTAssertEqual(arr[1], .number(1))
            XCTAssertEqual(arr[2], .boolean(true))
        } else {
            XCTFail("Expected .array, got \(value)")
        }
    }

    func testEncodeDecodeArray() throws {
        let original = TgglValue.array([
            .string("hello"),
            .number(42),
            .boolean(false)
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TgglValue.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - TgglValue object (plain JSON)

    func testDecodeObjectValue() throws {
        let json = """
        {"name":"test","count":5}
        """
        let data = Data(json.utf8)
        let value = try JSONDecoder().decode(TgglValue.self, from: data)
        if case .object(let obj) = value {
            XCTAssertEqual(obj.count, 2)
            XCTAssertEqual(obj["name"], .string("test"))
            XCTAssertEqual(obj["count"], .number(5))
        } else {
            XCTFail("Expected .object, got \(value)")
        }
    }

    func testEncodeDecodeObject() throws {
        let original = TgglValue.object([
            "key1": .string("val"),
            "key2": .boolean(true)
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TgglValue.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - TgglValue null

    func testDecodeNullValue() throws {
        let json = "null"
        let data = Data(json.utf8)
        let value = try JSONDecoder().decode(TgglValue.self, from: data)
        XCTAssertEqual(value, .null)
    }

    func testEncodeDecodeNull() throws {
        let original = TgglValue.null
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TgglValue.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - TgglValue equality

    func testValueEquality() {
        XCTAssertEqual(TgglValue.string("a"), TgglValue.string("a"))
        XCTAssertNotEqual(TgglValue.string("a"), TgglValue.string("b"))
        XCTAssertEqual(TgglValue.number(1), TgglValue.number(1.0))
        XCTAssertEqual(TgglValue.null, TgglValue.null)
    }

    // MARK: - Tggl typed format round-trip through storage

    func testStoreAndRetrieveNewValueTypes() throws {
        let originalFlags = [[
            Tggl(key: "pi", value: .number(3.14159)),
            Tggl(key: "tags", value: .array([.string("a"), .string("b")])),
            Tggl(key: "meta", value: .object(["x": .number(1)])),
            Tggl(key: "empty", value: .null)
        ]]

        let storage = TgglStorage()
        storage.save(flags: originalFlags)

        let storedFlags = storage.getFlags()
        guard let flags = storedFlags.first else {
            return XCTFail("No flags found")
        }

        XCTAssertEqual(flags.count, 4)
        XCTAssertEqual(flags[0].value, .number(3.14159))
        XCTAssertEqual(flags[1].value, .array([.string("a"), .string("b")]))
        XCTAssertEqual(flags[2].value, .object(["x": .number(1)]))
        XCTAssertEqual(flags[3].value, .null)
    }

    // MARK: - Tggl decode from API-style JSON

    func testDecodeFullTgglWithNumberFromJSON() throws {
        let json = """
        [[{"key":"ratio","type":"number","numberValue":0.75}]]
        """
        let data = Data(json.utf8)
        let flags = try JSONDecoder().decode([[Tggl]].self, from: data)
        XCTAssertEqual(flags.first?.first?.key, "ratio")
        XCTAssertEqual(flags.first?.first?.value, .number(0.75))
    }

    func testDecodeFullTgglWithJsonArrayFromJSON() throws {
        let json = """
        [[{"key":"tags","type":"json","jsonValue":["a","b"]}]]
        """
        let data = Data(json.utf8)
        let flags = try JSONDecoder().decode([[Tggl]].self, from: data)
        XCTAssertEqual(flags.first?.first?.key, "tags")
        XCTAssertEqual(flags.first?.first?.value, .array([.string("a"), .string("b")]))
    }

    func testDecodeFullTgglWithJsonObjectFromJSON() throws {
        let json = """
        [[{"key":"meta","type":"json","jsonValue":{"x":1}}]]
        """
        let data = Data(json.utf8)
        let flags = try JSONDecoder().decode([[Tggl]].self, from: data)
        XCTAssertEqual(flags.first?.first?.key, "meta")
        XCTAssertEqual(flags.first?.first?.value, .object(["x": .number(1)]))
    }

    func testDecodeFullTgglWithNullFromJSON() throws {
        let json = """
        [[{"key":"nothing","type":"null"}]]
        """
        let data = Data(json.utf8)
        let flags = try JSONDecoder().decode([[Tggl]].self, from: data)
        XCTAssertEqual(flags.first?.first?.key, "nothing")
        XCTAssertEqual(flags.first?.first?.value, .null)
    }

    // MARK: - Unsupported type error

    func testDecodeUnsupportedTypeThrows() {
        let json = """
        {"key":"bad","type":"unknown","someValue":123}
        """
        let data = Data(json.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Tggl.self, from: data))
    }
}

// MARK: - TgglReporting tests

final class TgglReportingTests: XCTestCase {

    func testReportFlagAggregatesCounts() async throws {
        let reporting = TgglReporting(apiKey: nil, baseUrls: [], flushIntervalMs: 0)

        await reporting.reportFlag(slug: "flag1", value: .string("a"), defaultValue: .string("b"), clientId: "test")
        await reporting.reportFlag(slug: "flag1", value: .string("a"), defaultValue: .string("b"), clientId: "test")
        await reporting.reportFlag(slug: "flag1", value: .string("a"), defaultValue: .string("b"), count: 3, clientId: "test")

        await reporting.flush()
    }

    func testReportFlagDifferentValuesAreSeparate() async throws {
        let reporting = TgglReporting(apiKey: nil, baseUrls: [], flushIntervalMs: 0)

        await reporting.reportFlag(slug: "flag1", value: .string("a"), defaultValue: .string("b"), clientId: "test")
        await reporting.reportFlag(slug: "flag1", value: .string("c"), defaultValue: .string("b"), clientId: "test")

        await reporting.flush()
    }

    func testStartStop() async throws {
        let reporting = TgglReporting(apiKey: nil, baseUrls: [], flushIntervalMs: 5_000)

        let active = await reporting.isActive()
        XCTAssertTrue(active)

        await reporting.stop()
        let stopped = await reporting.isActive()
        XCTAssertFalse(stopped)

        await reporting.start(flushIntervalMs: 1_000)
        let restarted = await reporting.isActive()
        XCTAssertTrue(restarted)
    }
}
