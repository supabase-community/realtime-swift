@testable import Realtime
import XCTest

final class RealtimeTests: XCTestCase {
    static func supabaseUrl() -> String {
        if let token = ProcessInfo.processInfo.environment["supabaseUrl"] {
            return token
        } else {
            fatalError()
        }
    }

    static func supabaseKey() -> String {
        if let url = ProcessInfo.processInfo.environment["supabaseKey"] {
            return url
        } else {
            fatalError()
        }
    }

    var socket = RealtimeClient("\(supabaseUrl())/realtime/v1", params: ["apikey": supabaseKey()])

    func testConnection() {
        let e = expectation(description: "testConnection")
        socket.onOpen { [self] in
            XCTAssertEqual(socket.isConnected, true)
            socket.disconnect()
        }

        socket.onError { error in
            XCTFail(error.localizedDescription)
        }

        socket.onClose { [self] in
            XCTAssertEqual(socket.isConnected, false)
            e.fulfill()
        }

        socket.connect()

        waitForExpectations(timeout: 30) { error in
            if let error = error {
                XCTFail("testConnection failed: \(error.localizedDescription)")
            }
        }
    }

    static var allTests = [
        ("testConnection", testConnection),
    ]
}
