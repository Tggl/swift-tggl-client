import XCTest
@testable import TgglClient

final class TgglClientTests: XCTestCase {
    func testExample() throws {
        
        print("Test started")
        let client = TgglClient(apiKey: "")
        
        XCTAssertEqual(client.flags.count, 0)
        
        client.startPolling(every: 3)
        
        print("Test ended")
        
        let expectation = XCTestExpectation(description: "Success")
        
        XCTWaiter.wait(for: [expectation], timeout: 20.0)
    }
}
