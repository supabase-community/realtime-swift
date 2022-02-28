/// Struct that gathers callbacks assigned to the Socket
struct StateChangeCallbacks {
  var open: [(ref: String, callback: Delegated<Void, Void>)] = []
  var close: [(ref: String, callback: Delegated<Void, Void>)] = []
  var error: [(ref: String, callback: Delegated<Error, Void>)] = []
  var message: [(ref: String, callback: Delegated<Message, Void>)] = []
}
