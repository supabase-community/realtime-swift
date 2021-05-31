import XCTest
@testable import Realtime

final class RealtimeTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(Realtime().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
