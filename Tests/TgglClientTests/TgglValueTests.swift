import XCTest
@testable import TgglClient

final class TgglValueTests: XCTestCase {
    // MARK: - /typed-flags parsing

    func testParsesEveryTypedFlagType() throws {
        let json = """
        [[
          {"key": "s", "type": "string", "stringValue": "foo"},
          {"key": "n", "type": "number", "numberValue": 3.5},
          {"key": "b", "type": "boolean", "booleanValue": false},
          {"key": "j", "type": "json", "jsonValue": {"a": [1, true, null]}},
          {"key": "z", "type": "null"}
        ]]
        """
        let flags = try TgglTypedFlags.parse(Data(json.utf8))

        XCTAssertEqual(flags, [
            "s": .string("foo"),
            "n": .number(3.5),
            "b": .boolean(false),
            "j": ["a": [1, true, nil]],
            "z": .null,
        ])
    }

    func testUnknownFlagTypeIsIgnoredInsteadOfFailingTheResponse() throws {
        let json = """
        [[
          {"key": "known", "type": "boolean", "booleanValue": true},
          {"key": "future", "type": "date", "dateValue": "2030-01-01"}
        ]]
        """
        let flags = try TgglTypedFlags.parse(Data(json.utf8))
        XCTAssertEqual(flags, ["known": true])
    }

    func testInvalidPayloadThrows() {
        XCTAssertThrowsError(try TgglTypedFlags.parse(Data("{}".utf8)))
        XCTAssertThrowsError(try TgglTypedFlags.parse(Data("[]".utf8)))
    }

    func testRequestBodyIsAnArrayOfOneContext() throws {
        let data = try TgglTypedFlags.requestBody(context: ["userId": "u1"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(json.count, 1)
        XCTAssertEqual(json[0]["userId"] as? String, "u1")
    }

    // MARK: - TgglValue

    func testCodableRoundTrip() throws {
        let value: TgglValue = ["s": "x", "n": 1.5, "b": true, "a": [1, "2"], "o": ["k": nil]]
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(TgglValue.self, from: data), value)
    }

    func testBooleansAndNumbersStayDistinct() throws {
        XCTAssertEqual(try JSONDecoder().decode(TgglValue.self, from: Data("true".utf8)), .boolean(true))
        XCTAssertEqual(try JSONDecoder().decode(TgglValue.self, from: Data("1".utf8)), .number(1))
    }

    func testAccessors() {
        XCTAssertEqual(TgglValue.number(3).intValue, 3)
        XCTAssertNil(TgglValue.number(3.2).intValue)
        XCTAssertEqual(TgglValue.string("a").stringValue, "a")
        XCTAssertNil(TgglValue.string("a").boolValue)
        XCTAssertTrue(TgglValue.null.isNull)
    }

    // MARK: - TgglValueRepresentable

    func testRepresentableConversions() {
        XCTAssertEqual(Bool(tgglValue: true), true)
        XCTAssertNil(Bool(tgglValue: "true"))
        XCTAssertEqual(Int(tgglValue: 4), 4)
        XCTAssertNil(Int(tgglValue: 4.5))
        XCTAssertEqual([String](tgglValue: ["a", "b"]), ["a", "b"])
        XCTAssertNil([String](tgglValue: ["a", 1]))
        XCTAssertEqual([String: Int](tgglValue: ["a": 1]), ["a": 1])
        XCTAssertEqual(Optional<String>(tgglValue: .null), .some(nil))
        XCTAssertEqual(Optional<String>(tgglValue: "x"), .some("x"))
        XCTAssertNil(Optional<String>(tgglValue: 1))
    }

    func testContextInputConversion() {
        let email: String? = nil
        let userId = "u1"
        let input: TgglContextInput = [
            "userId": userId,
            "email": email,
            "age": 42,
            "score": 0.5,
            "beta": true,
            "tags": ["a", "b"],
            "explicitNull": nil,
            "raw": TgglValue.object(["k": "v"]),
        ]

        XCTAssertEqual(input.tgglContext, [
            "userId": "u1",
            "email": nil,
            "age": 42,
            "score": 0.5,
            "beta": true,
            "tags": ["a", "b"],
            "explicitNull": nil,
            "raw": ["k": "v"],
        ])
    }
}
