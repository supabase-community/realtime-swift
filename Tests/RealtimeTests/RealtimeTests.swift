import XCTest

@testable import Realtime

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

  var socket = RealtimeClient(
    endPoint: "\(supabaseUrl())/realtime/v1", params: ["apikey": supabaseKey()])

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

  func testChannelCreation() {
    let client = RealtimeClient(
      endPoint: "\(Self.supabaseUrl())/realtime/v1", params: ["apikey": Self.supabaseKey()])
    let allChanges = client.channel(.all)
    allChanges.on(.all) { message in
      print(message)
    }
    allChanges.subscribe()
    allChanges.unsubscribe()
    allChanges.off(.all)

    let allPublicInsertChanges = client.channel(.schema("public"))
    allPublicInsertChanges.on(.insert) { message in
      print(message)
    }
    allPublicInsertChanges.subscribe()
    allPublicInsertChanges.unsubscribe()
    allPublicInsertChanges.off(.insert)

    let allUsersUpdateChanges = client.channel(.table("users", schema: "public"))
    allUsersUpdateChanges.on(.update) { message in
      print(message)
    }
    allUsersUpdateChanges.subscribe()
    allUsersUpdateChanges.unsubscribe()
    allUsersUpdateChanges.off(.update)

    let allUserId99Changes = client.channel(
      .column("id", value: "99", table: "users", schema: "public"))
    allUserId99Changes.on(.all) { message in
      print(message)
    }
    allUserId99Changes.subscribe()
    allUserId99Changes.unsubscribe()
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
}
