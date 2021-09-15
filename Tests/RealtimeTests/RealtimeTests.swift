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

   var socket = RealtimeClient(endPoint: "\(supabaseUrl())/realtime/v1", params: ["apikey": supabaseKey()])

    func testConnection() {
        let e = expectation(description: "testConnection")
        socket.onOpen { [self] in
            XCTAssertEqual(socket.isConnected, true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                socket.disconnect()
            }
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
                XCTFail("\(self.name)) failed: \(error.localizedDescription)")
            }
        }
    }

    func testTopicSerialization() {
        XCTAssertEqual(ChannelTopic.all.raw, "realtime:*")
        XCTAssertEqual(ChannelTopic.schema("public").raw,
                       "realtime:public")
        XCTAssertEqual(ChannelTopic.table("users", schema: "public").raw,
                       "realtime:public:users")
        XCTAssertEqual(ChannelTopic.column("id", value: "99", table: "users", schema: "public").raw,
                       "realtime:public:users:id=eq.99")
    }

    func testChannelCreation() {
        let client = RealtimeClient(endPoint: "\(Self.supabaseUrl())/realtime/v1", params: ["apikey": Self.supabaseKey()])
        let allChanges = client.channel(.all)
        allChanges.on(.all) { message in
            print(message)
        }
        allChanges.off(.all)

        let allPublicInsertChanges = client.channel(.schema("public"))
        allPublicInsertChanges.on(.insert) { message in
            print(message)
        }
        allPublicInsertChanges.off(.insert)

        let allUsersUpdateChanges = client.channel(.table("users", schema: "public"))
        allUsersUpdateChanges.on(.update) { message in
            print(message)
        }
        allUsersUpdateChanges.off(.update)

        let allUserId99Changes = client.channel(.column("id", value: "99", table: "users", schema: "public"))
        allUserId99Changes.on(.all){ message in
            print(message)
        }
        allUserId99Changes.off(.all)

        XCTAssertEqual(client.isConnected, false)

        let e = expectation(description: self.name)
        client.onOpen { [self] in
            XCTAssertEqual(client.isConnected, true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                client.disconnect()
            }
        }

        client.onError { error in
            XCTFail(error.localizedDescription)
        }

        client.onClose { [self] in
            XCTAssertEqual(client.isConnected, false)
            e.fulfill()
        }

        client.connect()

        waitForExpectations(timeout: 3000) { error in
            if let error = error {
                XCTFail("\(self.name)) failed: \(error.localizedDescription)")
            }
        }
    }

    static var allTests = [
        ("testConnection", testConnection),
        ("testTopicSerialization", testTopicSerialization),
        ("testChannelCreation", testChannelCreation),
    ]
}
