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
socket.onOpen { 
    print("Socket opened.")
}

socket.onError { error in
    print("Socket error: ", error.localizedDescription)
}

socket.onClose {
    print("Socket closed")
}
```

**Disconnect the socket**

Call `disconnect()` on the socket:

```swift
client.disconnect()
```

## Credits

- https://github.com/supabase/realtime-js 
- https://github.com/davidstump/SwiftPhoenixClient 

## License

This repo is licensed under MIT.
