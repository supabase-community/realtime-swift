// Copyright (c) 2021 Supabase
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

/// ## RealtimeClient
///
/// ```swift
/// let socket = new RealtimeClient("/socket", params: { ["apikey": "123" ] })
/// socket.connect()
/// ```
///
public class RealtimeClient: TransportDelegate {
    // ----------------------------------------------------------------------

    // MARK: - Public Attributes

    // ----------------------------------------------------------------------
    /// The string WebSocket endpoint (ie `"ws://supabase.io/realtime/v1"`,
    /// `"wss://supabase.io/realtime/v1"`, etc.) That was passed to the Socket during
    /// initialization. The URL endpoint will be modified by the Socket to
    /// include `"/websocket"` if missing.
    public let endPoint: String

    /// The fully qualified socket URL
    public private(set) var endPointUrl: URL

    /// Resolves to return the `params` result at the time of calling.
    /// If the `Socket` was created with static params, then those will be
    /// returned every time.
    public var params: [String: Any]?

    /// The WebSocket transport. Default behavior is to provide a Starscream
    /// WebSocket instance. Potentially allows changing WebSockets in future
    private let transport: Transport

    /// Override to provide custom encoding of data before writing to the socket
    public var encode: ([String: Any]) -> Data = Defaults.encode

    /// Override to provide customd decoding of data read from the socket
    public var decode: (Data) -> [String: Any]? = Defaults.decode

    /// Timeout to use when opening connections
    public var timeout: TimeInterval = Defaults.timeoutInterval

    /// Interval between sending a heartbeat
    public var heartbeatInterval: TimeInterval = Defaults.heartbeatInterval

    /// Interval between socket reconnect attempts, in seconds
    public var reconnectAfter: (Int) -> TimeInterval = Defaults.reconnectSteppedBackOff

    /// Interval between channel rejoin attempts, in seconds
    public var rejoinAfter: (Int) -> TimeInterval = Defaults.rejoinSteppedBackOff

    /// The optional function to receive logs
    public var logger: ((String) -> Void)?

    /// Disables heartbeats from being sent. Default is false.
    public var skipHeartbeat: Bool = false

    /// Enable/Disable SSL certificate validation. Default is false. This
    /// must be set before calling `socket.connect()` in order to be applied
    public var disableSSLCertValidation: Bool = false

    #if os(Linux)
    #else
        /// Configure custom SSL validation logic, eg. SSL pinning. This
        /// must be set before calling `socket.connect()` in order to apply.
        //  public var security: SSLTrustValidator?

        /// Configure the encryption used by your client by setting the
        /// allowed cipher suites supported by your server. This must be
        /// set before calling `socket.connect()` in order to apply.
        public var enabledSSLCipherSuites: [SSLCipherSuite]?
    #endif

    // ----------------------------------------------------------------------

    // MARK: - Private Attributes

    // ----------------------------------------------------------------------
    /// Callbacks for socket state changes
    var stateChangeCallbacks = StateChangeCallbacks()

    /// Collection on channels created for the Socket
    var channels: [Channel] = []

    /// Buffers messages that need to be sent once the socket has connected. It is an array
    /// of tuples, with the ref of the message to send and the callback that will send the message.
    var sendBuffer: [(ref: String?, callback: () throws -> Void)] = []

    /// Ref counter for messages
    var ref = UInt64.min // 0 (max: 18,446,744,073,709,551,615)

    /// Queue to run heartbeat timer on
    var heartbeatQueue = DispatchQueue(label: "com.supabase.realtime.socket.heartbeat")

    /// Timer that triggers sending new Heartbeat messages
    var heartbeatTimer: HeartbeatTimer?

    /// Ref counter for the last heartbeat that was sent
    var pendingHeartbeatRef: String?

    /// Timer to use when attempting to reconnect
    var reconnectTimer: TimeoutTimer

    /// True if the Socket closed cleaned. False if not (connection timeout, heartbeat, etc)
    var closeWasClean: Bool = false

    /// The connection to the server
    var connection: Transport?

    // ----------------------------------------------------------------------

    // MARK: - Initialization

    // ----------------------------------------------------------------------
    public init(endPoint: String,
                params: [String: Any]? = nil)
    {
        endPointUrl = RealtimeClient.buildEndpointUrl(endpoint: endPoint,
                                                      params: params)
        if #available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *) {
            transport = URLSessionTransport(url: endPointUrl)
        } else {
            transport = StarscreamTransport(url: endPointUrl)
        }
        self.params = params
        self.endPoint = endPoint

        reconnectTimer = TimeoutTimer()
        reconnectTimer.callback.delegate(to: self) { (self) in
            self.logItems("Socket attempting to reconnect")
            self.teardown { self.connect() }
        }
        reconnectTimer.timerCalculation
            .delegate(to: self) { (self, tries) -> TimeInterval in
                let interval = self.reconnectAfter(tries)
                self.logItems("Socket reconnecting in \(interval)s")
                return interval
            }
    }

    deinit {
        reconnectTimer.reset()
    }

    // ----------------------------------------------------------------------

    // MARK: - Public

    // ----------------------------------------------------------------------
    /// - return: The socket protocol, wss or ws
    public var websocketProtocol: String {
        switch endPointUrl.scheme {
        case "https": return "wss"
        case "http": return "ws"
        default: return endPointUrl.scheme ?? ""
        }
    }

    /// - return: True if the socket is connected
    public var isConnected: Bool {
        return connection?.readyState == .open
    }

    /// Connects the Socket. The params passed to the Socket on initialization
    /// will be sent through the connection. If the Socket is already connected,
    /// then this call will be ignored.
    public func connect() {
        // Do not attempt to reconnect if the socket is currently connected
        guard !isConnected else { return }

        // Reset the clean close flag when attempting to connect
        closeWasClean = false

        // We need to build this right before attempting to connect as the
        // parameters could be built upon demand and change over time
        endPointUrl = RealtimeClient.buildEndpointUrl(endpoint: endPoint,
                                                      params: params)

        connection = transport
        connection?.delegate = self

        connection?.connect()
    }

    /// Disconnects the socket
    ///
    /// - parameter code: Optional. Closing status code
    /// - paramter callback: Optional. Called when disconnected
    public func disconnect(code: CloseCode = CloseCode.normal,
                           callback: (() -> Void)? = nil)
    {
        // The socket was closed cleanly by the User
        closeWasClean = true

        // Reset any reconnects and teardown the socket connection
        reconnectTimer.reset()
        teardown(code: code, callback: callback)
    }

    internal func teardown(code: CloseCode = CloseCode.normal, callback: (() -> Void)? = nil) {
        connection?.delegate = nil
        connection?.disconnect(code: code.rawValue, reason: nil)
        connection = nil

        // The socket connection has been torndown, heartbeats are not needed
        heartbeatTimer?.stopTimer()
        heartbeatTimer = nil

        // Since the connection's delegate was nil'd out, inform all state
        // callbacks that the connection has closed
        stateChangeCallbacks.close.forEach { $0.callback.call() }
        callback?()
    }

    // ----------------------------------------------------------------------

    // MARK: - Register Socket State Callbacks

    // ----------------------------------------------------------------------

    /// Registers callbacks for connection open events. Does not handle retain
    /// cycles. Use `delegateOnOpen(to:)` for automatic handling of retain cycles.
    ///
    /// Example:
    ///
    ///     socket.onOpen() { [weak self] in
    ///         self?.print("Socket Connection Open")
    ///     }
    ///
    /// - parameter callback: Called when the Socket is opened
    @discardableResult
    public func onOpen(callback: @escaping () -> Void) -> String {
        var delegated = Delegated<Void, Void>()
        delegated.manuallyDelegate(with: callback)

        return append(callback: delegated, to: &stateChangeCallbacks.open)
    }

    /// Registers callbacks for connection open events. Automatically handles
    /// retain cycles. Use `onOpen()` to handle yourself.
    ///
    /// Example:
    ///
    ///     socket.delegateOnOpen(to: self) { self in
    ///         self.print("Socket Connection Open")
    ///     }
    ///
    /// - parameter owner: Class registering the callback. Usually `self`
    /// - parameter callback: Called when the Socket is opened
    @discardableResult
    public func delegateOnOpen<T: AnyObject>(to owner: T,
                                             callback: @escaping ((T) -> Void)) -> String
    {
        var delegated = Delegated<Void, Void>()
        delegated.delegate(to: owner, with: callback)

        return append(callback: delegated, to: &stateChangeCallbacks.open)
    }

    /// Registers callbacks for connection close events. Does not handle retain
    /// cycles. Use `delegateOnClose(_:)` for automatic handling of retain cycles.
    ///
    /// Example:
    ///
    ///     socket.onClose() { [weak self] in
    ///         self?.print("Socket Connection Close")
    ///     }
    ///
    /// - parameter callback: Called when the Socket is closed
    @discardableResult
    public func onClose(callback: @escaping () -> Void) -> String {
        var delegated = Delegated<Void, Void>()
        delegated.manuallyDelegate(with: callback)

        return append(callback: delegated, to: &stateChangeCallbacks.close)
    }

    /// Registers callbacks for connection close events. Automatically handles
    /// retain cycles. Use `onClose()` to handle yourself.
    ///
    /// Example:
    ///
    ///     socket.delegateOnClose(self) { self in
    ///         self.print("Socket Connection Close")
    ///     }
    ///
    /// - parameter owner: Class registering the callback. Usually `self`
    /// - parameter callback: Called when the Socket is closed
    @discardableResult
    public func delegateOnClose<T: AnyObject>(to owner: T,
                                              callback: @escaping ((T) -> Void)) -> String
    {
        var delegated = Delegated<Void, Void>()
        delegated.delegate(to: owner, with: callback)

        return append(callback: delegated, to: &stateChangeCallbacks.close)
    }

    /// Registers callbacks for connection error events. Does not handle retain
    /// cycles. Use `delegateOnError(to:)` for automatic handling of retain cycles.
    ///
    /// Example:
    ///
    ///     socket.onError() { [weak self] (error) in
    ///         self?.print("Socket Connection Error", error)
    ///     }
    ///
    /// - parameter callback: Called when the Socket errors
    @discardableResult
    public func onError(callback: @escaping (Error) -> Void) -> String {
        var delegated = Delegated<Error, Void>()
        delegated.manuallyDelegate(with: callback)

        return append(callback: delegated, to: &stateChangeCallbacks.error)
    }

    /// Registers callbacks for connection error events. Automatically handles
    /// retain cycles. Use `manualOnError()` to handle yourself.
    ///
    /// Example:
    ///
    ///     socket.delegateOnError(to: self) { (self, error) in
    ///         self.print("Socket Connection Error", error)
    ///     }
    ///
    /// - parameter owner: Class registering the callback. Usually `self`
    /// - parameter callback: Called when the Socket errors
    @discardableResult
    public func delegateOnError<T: AnyObject>(to owner: T,
                                              callback: @escaping ((T, Error) -> Void)) -> String
    {
        var delegated = Delegated<Error, Void>()
        delegated.delegate(to: owner, with: callback)

        return append(callback: delegated, to: &stateChangeCallbacks.error)
    }

    /// Registers callbacks for connection message events. Does not handle
    /// retain cycles. Use `delegateOnMessage(_to:)` for automatic handling of
    /// retain cycles.
    ///
    /// Example:
    ///
    ///     socket.onMessage() { [weak self] (message) in
    ///         self?.print("Socket Connection Message", message)
    ///     }
    ///
    /// - parameter callback: Called when the Socket receives a message event
    @discardableResult
    public func onMessage(callback: @escaping (Message) -> Void) -> String {
        var delegated = Delegated<Message, Void>()
        delegated.manuallyDelegate(with: callback)

        return append(callback: delegated, to: &stateChangeCallbacks.message)
    }

    /// Registers callbacks for connection message events. Automatically handles
    /// retain cycles. Use `onMessage()` to handle yourself.
    ///
    /// Example:
    ///
    ///     socket.delegateOnMessage(self) { (self, message) in
    ///         self.print("Socket Connection Message", message)
    ///     }
    ///
    /// - parameter owner: Class registering the callback. Usually `self`
    /// - parameter callback: Called when the Socket receives a message event
    @discardableResult
    public func delegateOnMessage<T: AnyObject>(to owner: T,
                                                callback: @escaping ((T, Message) -> Void)) -> String
    {
        var delegated = Delegated<Message, Void>()
        delegated.delegate(to: owner, with: callback)

        return append(callback: delegated, to: &stateChangeCallbacks.message)
    }

    private func append<T>(callback: T, to array: inout [(ref: String, callback: T)]) -> String {
        let ref = makeRef()
        array.append((ref, callback))
        return ref
    }

    /// Releases all stored callback hooks (onError, onOpen, onClose, etc.) You should
    /// call this method when you are finished when the Socket in order to release
    /// any references held by the socket.
    public func releaseCallbacks() {
        stateChangeCallbacks.open.removeAll()
        stateChangeCallbacks.close.removeAll()
        stateChangeCallbacks.error.removeAll()
        stateChangeCallbacks.message.removeAll()
    }

    // ----------------------------------------------------------------------

    // MARK: - Channel Initialization

    // ----------------------------------------------------------------------
    /// Initialize a new Channel
    ///
    /// Example:
    ///
    ///     let channel = socket.channel("rooms", params: ["user_id": "abc123"])
    ///
    /// - parameter topic: Topic of the channel
    /// - parameter params: Optional. Parameters for the channel
    /// - return: A new channel
    public func channel(_ topic: ChannelTopic,
                        params: [String: Any] = [:]) -> Channel
    {
        let channel = Channel(topic: topic, params: params, socket: self)
        channels.append(channel)

        return channel
    }

    /// Removes the Channel from the socket. This does not cause the channel to
    /// inform the server that it is leaving. You should call channel.leave()
    /// prior to removing the Channel.
    ///
    /// Example:
    ///
    ///     channel.leave()
    ///     socket.remove(channel)
    ///
    /// - parameter channel: Channel to remove
    public func remove(_ channel: Channel) {
        off(channel.stateChangeRefs)
        channels.removeAll(where: { $0.joinRef == channel.joinRef })
    }

    /// Removes `onOpen`, `onClose`, `onError,` and `onMessage` registrations.
    ///
    ///
    /// - Parameter refs: List of refs returned by calls to `onOpen`, `onClose`, etc
    public func off(_ refs: [String]) {
        stateChangeCallbacks.open = stateChangeCallbacks.open.filter { !refs.contains($0.ref) }
        stateChangeCallbacks.close = stateChangeCallbacks.close.filter { !refs.contains($0.ref) }
        stateChangeCallbacks.error = stateChangeCallbacks.error.filter { !refs.contains($0.ref) }
        stateChangeCallbacks.message = stateChangeCallbacks.message.filter { !refs.contains($0.ref) }
    }

    // ----------------------------------------------------------------------

    // MARK: - Sending Data

    // ----------------------------------------------------------------------
    /// Sends data through the Socket. This method is internal. Instead, you
    /// should call `push(_:, payload:, timeout:)` on the Channel you are
    /// sending an event to.
    ///
    /// - parameter topic:
    /// - parameter event:
    /// - parameter payload:
    /// - parameter ref: Optional. Defaults to nil
    /// - parameter joinRef: Optional. Defaults to nil
    internal func push(topic: ChannelTopic,
                       event: ChannelEvent,
                       payload: [String: Any],
                       ref: String? = nil,
                       joinRef: String? = nil)
    {
        let callback: (() throws -> Void) = {
            var body: [String: Any] = [
                "topic": topic.raw,
                "event": event,
                "payload": payload,
            ]

            if let safeRef = ref { body["ref"] = safeRef }
            if let safeJoinRef = joinRef { body["join_ref"] = safeJoinRef }

            let data = self.encode(body)

            self.logItems("push", "Sending \(String(data: data, encoding: String.Encoding.utf8) ?? "")")
            self.connection?.send(data: data)
        }

        /// If the socket is connected, then execute the callback immediately.
        if isConnected {
            try? callback()
        } else {
            /// If the socket is not connected, add the push to a buffer which will
            /// be sent immediately upon connection.
            sendBuffer.append((ref: ref, callback: callback))
        }
    }

    /// - return: the next message ref, accounting for overflows
    public func makeRef() -> String {
        ref = (ref == UInt64.max) ? 0 : ref + 1
        return String(ref)
    }

    /// Logs the message. Override Socket.logger for specialized logging. noops by default
    ///
    /// - paramter items: List of items to be logged. Behaves just like debugPrint()
    func logItems(_ items: Any...) {
        let msg = items.map { String(describing: $0) }.joined(separator: ", ")
        logger?("SwiftPhoenixClient: \(msg)")
    }

    // ----------------------------------------------------------------------

    // MARK: - Connection Events

    // ----------------------------------------------------------------------
    /// Called when the underlying Websocket connects to it's host
    internal func onConnectionOpen() {
        logItems("transport", "Connected to \(endPoint)")

        // Reset the closeWasClean flag now that the socket has been connected
        closeWasClean = false

        // Send any messages that were waiting for a connection
        flushSendBuffer()

        // Reset how the socket tried to reconnect
        reconnectTimer.reset()

        // Restart the heartbeat timer
        resetHeartbeat()

        // Inform all onOpen callbacks that the Socket has opened
        stateChangeCallbacks.open.forEach { $0.callback.call() }
    }

    internal func onConnectionClosed(code _: Int?) {
        logItems("transport", "close")
        triggerChannelError()

        // Prevent the heartbeat from triggering if the
        heartbeatTimer?.stopTimer()
        heartbeatTimer = nil

        // Only attempt to reconnect if the socket did not close normally
        if !closeWasClean {
            reconnectTimer.scheduleTimeout()
        }

        stateChangeCallbacks.close.forEach { $0.callback.call() }
    }

    internal func onConnectionError(_ error: Error) {
        logItems("transport", error)

        // Send an error to all channels
        triggerChannelError()

        // Inform any state callabcks of the error
        stateChangeCallbacks.error.forEach { $0.callback.call(error) }
    }

    internal func onConnectionMessage(_ rawMessage: String) {
        logItems("receive ", rawMessage)

        guard
            let data = rawMessage.data(using: String.Encoding.utf8),
            let json = decode(data),
            let message = Message(json: json)
        else {
            logItems("receive: Unable to parse JSON: \(rawMessage)")
            return
        }

        // Clear heartbeat ref, preventing a heartbeat timeout disconnect
        if message.ref == pendingHeartbeatRef { pendingHeartbeatRef = nil }

        if message.event == .close {
            print("Close Event Received")
        }

        // Dispatch the message to all channels that belong to the topic
        channels
            .filter { $0.isMember(message) }
            .forEach { $0.trigger(message) }

        // Inform all onMessage callbacks of the message
        stateChangeCallbacks.message.forEach { $0.callback.call(message) }
    }

    /// Triggers an error event to all of the connected Channels
    internal func triggerChannelError() {
        channels.forEach { channel in
            // Only trigger a channel error if it is in an "opened" state
            if !(channel.isErrored || channel.isLeaving || channel.isClosed) {
                channel.trigger(event: ChannelEvent.error)
            }
        }
    }

    /// Send all messages that were buffered before the socket opened
    internal func flushSendBuffer() {
        guard isConnected, sendBuffer.count > 0 else { return }
        sendBuffer.forEach { try? $0.callback() }
        sendBuffer = []
    }

    /// Removes an item from the sendBuffer with the matching ref
    internal func removeFromSendBuffer(ref: String) {
        sendBuffer = sendBuffer.filter { $0.ref != ref }
    }

    /// Builds a fully qualified socket `URL` from `endPoint` and `params`.
    internal static func buildEndpointUrl(endpoint: String, params: [String: Any]?) -> URL {
        guard
            let url = URL(string: endpoint),
            var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { fatalError("Malformed URL: \(endpoint)") }

        // Ensure that the URL ends with "/websocket
        if !urlComponents.path.contains("/websocket") {
            // Do not duplicate '/' in the path
            if urlComponents.path.last != "/" {
                urlComponents.path.append("/")
            }

            // append 'websocket' to the path
            urlComponents.path.append("websocket")
        }

        // If there are parameters, append them to the URL
        if let params = params {
            urlComponents.queryItems = params.map {
                URLQueryItem(name: $0.key, value: String(describing: $0.value))
            }
        }

        guard let qualifiedUrl = urlComponents.url
        else { fatalError("Malformed URL while adding parameters") }
        return qualifiedUrl
    }

    // Leaves any channel that is open that has a duplicate topic
    internal func leaveOpenTopic(topic: ChannelTopic) {
        guard
            let dupe = channels.first(where: { $0.topic == topic && ($0.isJoined || $0.isJoining) })
        else { return }

        logItems("transport", "leaving duplicate topic: [\(topic)]")
        dupe.unsubscribe()
    }

    // ----------------------------------------------------------------------

    // MARK: - Heartbeat

    // ----------------------------------------------------------------------
    internal func resetHeartbeat() {
        // Clear anything related to the heartbeat
        pendingHeartbeatRef = nil
        heartbeatTimer?.stopTimer()
        heartbeatTimer = nil

        // Do not start up the heartbeat timer if skipHeartbeat is true
        guard !skipHeartbeat else { return }

        heartbeatTimer = HeartbeatTimer(timeInterval: heartbeatInterval, dispatchQueue: heartbeatQueue)
        heartbeatTimer?.startTimerWithEvent(eventHandler: { [weak self] in
            self?.sendHeartbeat()
        })
    }

    /// Sends a hearbeat payload to the phoenix serverss
    @objc func sendHeartbeat() {
        // Do not send if the connection is closed
        guard isConnected else { return }

        // If there is a pending heartbeat ref, then the last heartbeat was
        // never acknowledged by the server. Close the connection and attempt
        // to reconnect.
        if let _ = pendingHeartbeatRef {
            pendingHeartbeatRef = nil
            logItems("transport",
                     "heartbeat timeout. Attempting to re-establish connection")

            // Close the socket manually, flagging the closure as abnormal. Do not use
            // `teardown` or `disconnect` as they will nil out the websocket delegate.
            abnormalClose("heartbeat timeout")

            return
        }

        // The last heartbeat was acknowledged by the server. Send another one
        pendingHeartbeatRef = makeRef()
        push(topic: .heartbeat,
             event: ChannelEvent.heartbeat,
             payload: [:],
             ref: pendingHeartbeatRef)
    }

    internal func abnormalClose(_ reason: String) {
        closeWasClean = false

        /*
         We use NORMAL here since the client is the one determining to close the
         connection. However, we keep a flag `closeWasClean` set to false so that
         the client knows that it should attempt to reconnect.
         */
        connection?.disconnect(code: CloseCode.normal.rawValue, reason: reason)
    }

    // ----------------------------------------------------------------------

    // MARK: - TransportDelegate

    // ----------------------------------------------------------------------
    public func onOpen() {
        onConnectionOpen()
    }

    public func onError(error: Error) {
        onConnectionError(error)
    }

    public func onMessage(message: String) {
        onConnectionMessage(message)
    }

    public func onClose(code: Int) {
        closeWasClean = code != CloseCode.abnormal.rawValue
        onConnectionClosed(code: code)
    }
}

// ----------------------------------------------------------------------

// MARK: - Close Codes

// ----------------------------------------------------------------------
public extension RealtimeClient {
    enum CloseCode: Int {
        case abnormal = 999

        case normal = 1000

        case goingAway = 1001
    }
}
