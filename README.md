# `realtime-swift`

Listens to changes in a PostgreSQL Database and via websockets.

A Swift client for Supabase [Realtime](https://github.com/supabase/realtime-swift) server.

## Usage

### Creating a Socket connection

You can set up one connection to be used across the whole app.

```swift
import Realtime

var client = RealtimeClient(endPoint: "https://yourcompany.supabase.co/realtime/v1", params: ["apikey": "public-anon-key"])
client.connect()
```

**Socket Hooks**

```swift
client.onOpen {
    print("Socket opened.")
}

client.onError { error in
    print("Socket error: ", error.localizedDescription)
}

client.onClose {
    print("Socket closed")
}
```

**Disconnect the socket**

Call `disconnect()` on the socket:

```swift
client.disconnect()
```

### Subscribe to topics

You can subscribe to all topic, or to specific schema parts.

* Listen to all database changes:

```swift
let allChanges = client.channel(.all)
allChanges.on(.all) { message in
    print(message)
}
allChanges.subscribe()
// ...
allChanges.unsubscribe()
allChanges.off(.all)
```

* Listen to a specific schema's changes:

```swift
let allPublicInsertChanges = client.channel(.schema("public"))
allPublicInsertChanges.on(.insert) { message in
    print(message)
}
allPublicInsertChanges.subscribe()
// ...
allPublicInsertChanges.unsubscribe()
allPublicInsertChanges.off(.insert)
```

* Listen to a specific table's changes:

```swift
let allUsersUpdateChanges = client.channel(.table("users", schema: "public"))
allUsersUpdateChanges.on(.update) { message in
    print(message)
}
allUsersUpdateChanges.subscribe()
// ...
allUsersUpdateChanges.unsubscribe()
allUsersUpdateChanges.off(.update)
```

* Listen to a specific column's value changes:

```swift
let allUserId99Changes = client.channel(.column("id", value: "99", table: "users", schema: "public"))
allUserId99Changes.on(.all){ message in
    print(message)
}
allUserId99Changes.subscribe()
// ...
allUserId99Changes.unsubscribe()
allUserId99Changes.off(.all)
```
### Broadcast

* Listen for `broadcast` messages:

```swift
let channel = client.channel(.table("channel_id", schema: "someChannel"), options: .init(presenceKey: "user_uuid"))
channel.on(.broadcast) { message in
    let payload = message.payload["payload"]
    let event = message.payload["event"]
    let type = message.payload["type"]
    print(type, event, payload)
}

channel.join()
```

* Send `broadcast` messages:
    
```swift
let channel = client.channel(.table("channel_id", schema: "someChannel"), options: .init(presenceKey: "user_uuid"))
channel.join()

channel.broadcast(event: "my_event", payload: ["hello": "world"])
```
### Presence

Presence can be used to share state between clients.

* Listen to presence `sync` events to track state changes:

```swift
let channel = client.channel(.table("channel_id", schema: "someChannel"), options: .init(presenceKey: "user_uuid"))
let presence = Presence(channel: channel)

presence.onSync {
    print("presence sync", presence?.state, presence?.list())
}

channel.join()
// ...
```

* Track presence state changes:

```swift
let channel = client.channel(.table("channel_id", schema: "someChannel"), options: .init(presenceKey: "user_uuid"))
channel.join()

channel.track(payload: [
    ["hello": "world]
])
```

* Remove tracked presence state changes:

```swift
let channel = client.channel(.table("channel_id", schema: "someChannel"), options: .init(presenceKey: "user_uuid"))
channel.join()

channel.untrack()
```
## Credits

- https://github.com/supabase/realtime-js
- https://github.com/davidstump/SwiftPhoenixClient

## License

This repo is licensed under MIT.
