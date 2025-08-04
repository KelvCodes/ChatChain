k if user already exists
    for ((principal, _) in userBuffer.toArray().vals()) {
      if (Principal.equal(principal, caller)) {
        return false; // User already registered
      }
    };
    userBuffer.add((caller, name));
    users := userBuffer.toArray();
    true
  };

  // Get all registered users
  public query func getUsers() : async [(Principal, Text)] {
    userBuffer.toArray()
  };

  // Send a message
  public shared(msg) func sendMessage(content: Text) : async () {
    let message: Message = {
      sender = msg.caller;
      content = content;
      timestamp = Time.now();
    };
    messageBuffer.add(message);
    messages := messageBuffer.toArray();
  };

  // Get all messages
  public query func getMessages() : async [Message] {
    messages
  };

  // Get messages since a given timestamp
  public query func getMessagesSince(timestamp: Time.Time) : async [Message] {
    Array.filter(messages, func (msg: Message) : Bool { msg.timestamp >= timestamp })
  };

  // Clear messages (for testing, optional)
  public func clearMessages() : async () {
    messageBuffer.clear();
    messages := [];
  };

};

































