# `realtime-swift`

> [!WARNING]  
> This repository is deprecated and it was moved to the [monorepo](https://github.com/supabase-community/supabase-swift).
> Repository will remain live to support old versions of the library, but any new updates **MUST** be done on the monorepo.

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


## Credits

- https://github.com/supabase/realtime-js
- https://github.com/davidstump/SwiftPhoenixClient

## License

This repo is licensed under MIT.
