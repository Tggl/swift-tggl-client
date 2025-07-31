import XCTest
@testable import TgglClient

final class TgglClientTests: XCTestCase {
    func testExample() throws {
        
        print("Test started")
        let client = TgglClient(apiKey: "kREFUsLPom692h8if8TPxdi18Zk-nSHjvaB1uBtYyAQ")
        
        XCTAssertEqual(client.flags.count, 0)
        
        client.startPolling(every: 3)

        //sleep(5)

        client.setContext(context: ["email": " "])
        print("setContext pierre.kopaczewski@scenies.com")

        sleep(5)
        
        client.setContext(context: ["email": "zlobodan.debernardi@sadoma.so"])
        print("setContext zlobodan.debernardi@sadoma.so")
               
        sleep(5)

        XCTAssertEqual(client.flags.count, 1)

        print("Test ended")
    }
}
