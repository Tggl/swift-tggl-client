import XCTest
@testable import TgglClient

final class TgglClientTests: XCTestCase {
    func testFlagsAreUpdatedWhenContextChanges() async throws {
        print("Test started")
        
        // Start from scratch to avoid storage interference
        let storage = TgglStorage()
        storage.save(flags: [])
        storage.save(context: [:])
        
        let client = TgglClient(apiKey: "kREFUsLPom692h8if8TPxdi18Zk-nSHjvaB1uBtYyAQ")
        
        print("client.context : \(await client.getContext())")
        
        let initialFlags = await client.getFlags()
        XCTAssertEqual(initialFlags.count, 0)
        
        // Start
        await client.startPolling(every: 3)
        
        print("Test initial state")
        try await Task.sleep(nanoseconds: 5_000_000_000)
        let flagsAfterStart = await client.getFlags()
        XCTAssertEqual(flagsAfterStart.count, 1)

        print("Test first context change")
        await client.setContext(context: ["email": "pierre.kopaczewski@scenies.com"])
        print("setContext pierre.kopaczewski@scenies.com")
        try await Task.sleep(nanoseconds: 5_000_000_000)
        let flagsAfterFirstContext = await client.getFlags()
        XCTAssertEqual(flagsAfterFirstContext.count, 2)
        
        print("Test second context change")
        await client.setContext(context: ["email": "zlobodan.debernardi@sadoma.so"])
        print("setContext zlobodan.debernardi@sadoma.so")
        try await Task.sleep(nanoseconds: 5_000_000_000)
        let flagsAfterSecondContext = await client.getFlags()
        XCTAssertEqual(flagsAfterSecondContext.count, 1)

        print("Test ended")
    }
}
