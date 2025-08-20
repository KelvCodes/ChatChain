

     // The user's principal who sent the message
    content: Text;         // The actual text message content
    timestamp: Time.Time;  // The time the message was sent
  };

  // -------------------------------
  // STABLE STORAGE VARIABLES
  // -------------------------------

  // Persisted list of all chat messages (used during upgrades)
  stable var messages: [Message] = [];

  // Persisted list of registered users (Principal, name)
  stable var users: [(Principal, Text)] = [];

  // -------------------------------
  // IN-MEMORY BUFFERS (MUTABLE)
  // -------------------------------

  // In-memory buffer to efficiently add/retrieve messages
  let messageBuffer = Buffer.Buffer<Message>(100);

  // In-memory buffer to manage registered users
  let userBuffer = Buffer.Buffer<(Principal, Text)>(100);

  // -------------------------------
  // USER REGISTRATION
  // -------------------------------

  /// Registers a new user with a display name.
  /// Fails if the user is already registered.
  ///
  /// @param name The name the user wants to register with
  /// @return `true` if successful, `false` if already registered
  public shared(msg) func registerUser(name: Text): async Bool {
    let caller = msg.caller;

    // Prevent duplicate registration
    for ((principal, _) in userBuffer.toArray().vals()) {
      if (Principal.equal(principal, caller)) {
        return false;
      }
    };

    // Add new user and sync with stable storage
    userBuffer.add((caller, name));
    users := userBuffer.toArray();
    return true;
  };

  /// Retrieves all registered users (Principal and name).
  public query func getUsers(): async [(Principal, Text)] {
    userBuffer.toArray();
  };

  // -------------------------------
  // MESSAGE SENDING AND RETRIEVAL
  // -------------------------------

  /// Allows a user to send a message.
  ///
  /// @param content The message text content
  public shared(msg) func sendMessage(content: Text): async () {
    let newMessage: Message = {
      sender = msg.caller;
      content = content;
      timestamp = Time.now();
    };

    // Add to buffer and persist to stable variable
    messageBuffer.add(newMessage);
    messages := messageBuffer.toArray();
  };

  /// Retrieves all messages.
  public query func getMessages(): async [Message] {
    messages;
  };

  /// Retrieves messages sent since a specific timestamp.
  ///
  /// @param timestamp The earliest time to retrieve messages from
  /// @return An array of messages sent on or after the given timestamp
  public query func getMessagesSince(timestamp: Time.Time): async [Message] {
    Array.filter(
      messages,
      func(msg: Message): Bool {
        msg.timestamp >= timestamp
      }
    )
  };

  // -------------------------------
  // UTILITY FUNCTIONS
  // -------------------------------

  /// Clears all messages (for testing or admin use).
  public func clearMessages(): async () {
    messageBuffer.clear();
    messages := [];
  };
};





































































