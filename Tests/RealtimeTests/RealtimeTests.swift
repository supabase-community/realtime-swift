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

    var socket = RealtimeClient("https://galflylhyokjtdotwnde.supabase.co/realtime/v1", params: ["apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlhdCI6MTYwODI3ODIyNCwiZXhwIjoxOTIzODU0MjI0fQ.SaWTr6MKjcSCXSnylOrTjHBOt6oU-e82oRPhddMEu4U"])
//    var socket = RealtimeClient("\(supabaseUrl())/realtime/v1", params: ["apikey": supabaseKey()])

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

        waitForExpectations(timeout: 3000) { error in
            if let error = error {
                XCTFail("testConnection failed: \(error.localizedDescription)")
            }
        }
    }

    static var allTests = [
        ("testConnection", testConnection),
    ]
}
