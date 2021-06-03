// Copyright (c) 2021 David Stump <david@davidstump.net>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation
import Starscream

// ----------------------------------------------------------------------

// MARK: - Transport Protocol

// ----------------------------------------------------------------------
/**
 Defines a `Socket`'s Transport layer.
 */
// sourcery: AutoMockable
public protocol Transport {
    /// The current `ReadyState` of the `Transport` layer
    var readyState: TransportReadyState { get }

    /// Delegate for the `Transport` layer
    var delegate: TransportDelegate? { get set }

    /**
     Connect to the server
     */
    func connect()

    /**
     Disconnect from the server.

     - Parameters:
     - code: Status code as defined by <ahref="http://tools.ietf.org/html/rfc6455#section-7.4">Section 7.4 of RFC 6455</a>.
     - reason: Reason why the connection is closing. Optional.
     */
    func disconnect(code: Int, reason: String?)

    /**
     Sends a message to the server.

     - Parameter data: Data to send.
     */
    func send(data: Data)
}

// ----------------------------------------------------------------------

// MARK: - Transport Delegate Protocol

// ----------------------------------------------------------------------
/**
 Delegate to receive notifications of events that occur in the `Transport` layer
 */
public protocol TransportDelegate {
    /**
     Notified when the `Transport` opens.
     */
    func onOpen()

    /**
     Notified when the `Transport` receives an error.

     - Parameter error: Error from the underlying `Transport` implementation
     */
    func onError(error: Error)

    /**
     Notified when the `Transport` receives a message from the server.

     - Parameter message: Message received from the server
     */
    func onMessage(message: String)

    /**
     Notified when the `Transport` closes.

     - Parameter code: Code that was sent when the `Transport` closed
     */
    func onClose(code: Int)
}

// ----------------------------------------------------------------------

// MARK: - Transport Ready State Enum

// ----------------------------------------------------------------------
/**
 Available `ReadyState`s of a `Transport` layer.
 */
public enum TransportReadyState {
    /// The `Transport` is opening a connection to the server.
    case connecting

    /// The `Transport` is connected to the server.
    case open

    /// The `Transport` is closing the connection to the server.
    case closing

    /// The `Transport` has disconnected from the server.
    case closed
}

// ----------------------------------------------------------------------

// MARK: - Default Websocket Transport Implementation

// ----------------------------------------------------------------------
/**
 A `Transport` implementation that relies on URLSession's native WebSocket
 implementation.

 This implementation ships default with SwiftClient however
 SwiftClient supports earlier OS versions using one of the submodule
 `Transport` implementations. Or you can create your own implementation using
 your own WebSocket library or implementation.
 */
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
public class URLSessionTransport: NSObject, Transport, URLSessionWebSocketDelegate {
    /// The URL to connect to
    internal let url: URL

    /// The underling URLsession. Assigned during `connect()`
    private var session: URLSession?

    /// The ongoing task. Assigned during `connect()`
    private var task: URLSessionWebSocketTask?

    /**
     Initializes a `Transport` layer built using URLSession's WebSocket

     Example:

     ```swift
     let url = URL("wss://example.com/socket")
     let transport: Transport = URLSessionTransport(url: url)
     ```

     - parameter url: URL to connect to
     */
    init(url: URL) {
        // URLSession requires that the endpoint be "wss" instead of "https".
        let endpoint = url.absoluteString
        let wsEndpoint = endpoint
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")

        // Force unwrapping should be safe here since a valid URL came in and we just
        // replaced the protocol.
        self.url = URL(string: wsEndpoint)!

        super.init()
    }

    // MARK: - Transport

    public var readyState: TransportReadyState = .closed
    public var delegate: TransportDelegate?

    public func connect() {
        // Set the trasport state as connecting
        readyState = .connecting

        // Create the session and websocket task
        session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        task = session?.webSocketTask(with: url)

        // Start the task
        task?.resume()
    }

    public func disconnect(code: Int, reason: String?) {
        /*
         TODO:
         1. Provide a "strict" mode that fails if an invalid close code is given
         2. If strict mode is disabled, default to CloseCode.invalid
         3. Provide default .normalClosure function
         */
        guard let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) else {
            fatalError("Could not create a CloseCode with invalid code: [\(code)].")
        }

        readyState = .closing
        task?.cancel(with: closeCode, reason: reason?.data(using: .utf8))
    }

    public func send(data: Data) {
        task?.send(.data(data)) { _ in
            // TODO: What is the behavior when an error occurs?
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    public func urlSession(_: URLSession,
                           webSocketTask _: URLSessionWebSocketTask,
                           didOpenWithProtocol _: String?)
    {
        // The Websocket is connected. Set Transport state to open and inform delegate
        readyState = .open
        delegate?.onOpen()

        // Start receiving messages
        receive()
    }

    public func urlSession(_: URLSession,
                           webSocketTask _: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                           reason _: Data?)
    {
        // A close frame was received from the server.
        readyState = .closed
        delegate?.onClose(code: closeCode.rawValue)
    }

    public func urlSession(_: URLSession,
                           task _: URLSessionTask,
                           didCompleteWithError error: Error?)
    {
        // The task has terminated. Inform the delegate that the transport has closed abnormally
        // if this was caused by an error.
        guard let err = error else { return }
        abnormalErrorReceived(err)
    }

    // MARK: - Private

    private func receive() {
        task?.receive { result in
            switch result {
            case let .success(message):
                switch message {
                case .data:
                    print("Data received. This method is unsupported by the Client")
                case let .string(text):
                    self.delegate?.onMessage(message: text)
                default:
                    fatalError("Unknown result was received. [\(result)]")
                }

                // Since `.receive()` is only good for a single message, it must
                // be called again after a message is received in order to
                // received the next message.
                self.receive()
            case let .failure(error):
                print("Error when receiving \(error)")
                self.abnormalErrorReceived(error)
            }
        }
    }

    private func abnormalErrorReceived(_ error: Error) {
        // Set the state of the Transport to closed
        readyState = .closed

        // Inform the Transport's delegate that an error occurred.
        delegate?.onError(error: error)

        // An abnormal error is results in an abnormal closure, such as internet getting dropped
        // so inform the delegate that the Transport has closed abnormally. This will kick off
        // the reconnect logic.
        delegate?.onClose(code: RealtimeClient.CloseCode.abnormal.rawValue)
    }
}

public class StarscreamTransport: NSObject, Transport, WebSocketDelegate {
    /// The URL to connect to
    private let url: URL

    /// The underlying Starscream WebSocket that data is transfered over.
    private var socket: WebSocket?

    /**
     Initializes a `Transport` layer built using Starscream's WebSocket, which is available for
     previous iOS targets back to iOS 10.

     If you are targeting iOS 13 or later, then you do not need to use this transport layer unless
     you specifically prefer using Starscream as the underlying Socket connection.

     Example:

     ```swift
     let url = URL("wss://example.com/socket")
     let transport: Transport = StarscreamTransport(url: url)
     ```

     - parameter url: URL to connect to
     */
    public init(url: URL) {
        self.url = url
        super.init()
    }

    // MARK: - Transport

    public var readyState: TransportReadyState = .closed
    public var delegate: TransportDelegate?

    public func connect() {
        // Set the trasport state as connecting
        readyState = .connecting

        let socket = WebSocket(url: url)
        socket.delegate = self
        socket.connect()

        self.socket = socket
    }

    public func disconnect(code: Int, reason _: String?) {
        /*
         TODO:
         1. Provide a "strict" mode that fails if an invalid close code is given
         2. If strict mode is disabled, default to CloseCode.invalid
         3. Provide default .normalClosure function
         */
        guard
            let closeCode = CloseCode(rawValue: UInt16(code))
        else {
            fatalError("Could not create a CloseCode with invalid code: [\(code)].")
        }

        readyState = .closing
        socket?.disconnect(closeCode: closeCode.rawValue)
    }

    public func send(data: Data) {
        socket?.write(data: data)
    }

    // MARK: - WebSocketDelegate

    public func websocketDidConnect(socket _: WebSocketClient) {
        readyState = .open
        delegate?.onOpen()
    }

    public func websocketDidDisconnect(socket _: WebSocketClient, error: Error?) {
        let closeCode = (error as? WSError)?.code ?? RealtimeClient.CloseCode.abnormal.rawValue
        // Set the state of the Transport to closed
        readyState = .closed

        // Inform the Transport's delegate that an error occurred.
        if let safeError = error { delegate?.onError(error: safeError) }

        // An abnormal error is results in an abnormal closure, such as internet getting dropped
        // so inform the delegate that the Transport has closed abnormally. This will kick off
        // the reconnect logic.
        delegate?.onClose(code: closeCode)
    }

    public func websocketDidReceiveMessage(socket _: WebSocketClient, text: String) {
        delegate?.onMessage(message: text)
    }

    public func websocketDidReceiveData(socket _: WebSocketClient, data _: Data) { /* no-op */ }
}
