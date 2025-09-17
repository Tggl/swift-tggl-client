import XCTest
@testable import TgglClient

final class TgglClientTests: XCTestCase {
    func testFlagsAreUpdatedWhenContextChanges() throws {
        
        print("Test started")
        let client = TgglClient(apiKey: "kREFUsLPom692h8if8TPxdi18Zk-nSHjvaB1uBtYyAQ")
        
        // start from scratch to avoid storage interference
        client.flags = [[]]
        
        if let fl = client.flags.first {
            XCTAssertEqual(fl.count, 0)
        }
        
        // Start
        client.startPolling(every: 3)
        
        print("Test initial state")
        sleep(5)
        XCTAssertEqual(client.flags.first?.count, 0)

        
        print("Test first context change")
        client.setContext(context: ["email": "pierre.kopaczewski@scenies.com"])
        print("setContext pierre.kopaczewski@scenies.com")
        sleep(5)
        XCTAssertEqual(client.flags.first?.count, 1)
        
        print("Test second context change")
        
        client.setContext(context: ["email": "zlobodan.debernardi@sadoma.so"])
        print("setContext zlobodan.debernardi@sadoma.so")
        sleep(5)
        XCTAssertEqual(client.flags.first?.count, 0)

        print("Test ended")
    }
}
