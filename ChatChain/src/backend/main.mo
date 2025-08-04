
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



















































