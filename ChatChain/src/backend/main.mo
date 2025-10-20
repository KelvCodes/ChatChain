

  // -------------------------
  // USER------------------

  // Register caller with a display name. Returns true if successful, false if already registered.
  public shared(msg) func registerUser(displayName: Text): async Bool {
    let caller = msg.caller;

    // If caller already in users, fail
    for (u in users.vals()) {
      if (Principal.equal(u.principal, caller)) {
        return false;
      };
    };

    // Append user and persist
    users := Array.append(users, [{ principal = caller; displayName = displayName }]);
    return true;
  };

  // Get all users
  public query func getUsers(): async [User] {
    users
  };

  // Update the caller's display name. Returns true if updated, false if not found.
  public shared(msg) func updateUserName(newDisplayName: Text): async Bool {
    let caller = msg.caller;
    var found: Bool = false;
    var tmp: [User] = [];

    for (u in users.vals()) {
      if (Principal.equal(u.principal, caller)) {
        tmp := Array.append(tmp, [{ principal = u.principal; displayName = newDisplayName }]);
        found := true;
      } else {
        tmp := Array.append(tmp, [u]);
      }
    };

    if (found) {
      users := tmp;
    };

    found
  };

  // Delete the caller from user list. Returns true if deleted.
  public shared(msg) func deleteUser(): async Bool {
    let caller = msg.caller;
    var tmp: [User] = [];
    var deleted: Bool = false;

    for (u in users.vals()) {
      if (Principal.equal(u.principal, caller)) {
        deleted := true;
      } else {
        tmp := Array.append(tmp, [u]);
      }
    };

    if (deleted) {
      users := tmp;
    };

    deleted
  };

  // -------------------------
  // MESSAGING
  // -------------------------

  // Send a new message. Returns the assigned message id.
  public shared(msg) func sendMessage(content: Text): async Nat {
    let sender = msg.caller;
    let id = nextMessageId;

    let m: Message = {
      id = id;
      sender = sender;
      content = content;
      timestamp = Time.now();
      edited = false;
    };

    nextMessageId += 1;

    messages := Array.append(messages, [m]);
    id
  };

  // Retrieve all messages
  public query func getMessages(): async [Message] {
    messages
  };

  // Retrieve messages since a timestamp (inclusive)
  public query func getMessagesSince(since: Time.Time): async [Message] {
    Array.filter(messages, func(m: Message): Bool { m.timestamp >= since })
  };

  // Edit a message. Only the original sender can edit. Returns true if successful.
  public shared(msg) func editMessage(messageId: Nat, newContent: Text): async Bool {
    let caller = msg.caller;
    var updated: Bool = false;
    var tmp: [Message] = [];

    for (m in messages.vals()) {
      if (m.id == messageId and Principal.equal(m.sender, caller)) {
        tmp := Array.append(tmp, [{ m with content = newContent; edited = true }]);
        updated := true;
      } else {
        tmp := Array.append(tmp, [m]);
      }
    };

    if (updated) {
      messages := tmp;
    };

    updated
  };

  // Delete a message. Only the original sender can delete. Returns true if deleted.
  public shared(msg) func deleteMessage(messageId: Nat): async Bool {
    let caller = msg.caller;
    var tmp: [Message] = [];
    var deleted: Bool = false;

    for (m in messages.vals()) {
      if (m.id == messageId and Principal.equal(m.sender, caller)) {
        deleted := true;
      } else {
        tmp := Array.append(tmp, [m]);
      }
    };

    if (deleted) {
      messages := tmp;
    };

    deleted
  };

  // Search messages for a keyword (case-sensitive). Returns all messages whose content contains the keyword.
  public query func searchMessages(keyword: Text): async [Message] {
    if (Text.size(keyword) == 0) {
      // If empty search, return nothing to avoid returning full message history accidentally
      return [];
    };
    Array.filter(messages, func(m: Message): Bool { Text.contains(m.content, keyword) })
  };

  // Get total number of messages
  public query func messageCount(): async Nat {
    Array.size(messages)
  };

  // Get number of messages by a specific user
  public query func userMessageCount(user: Principal): async Nat {
    Array.size(Array.filter(messages, func(m: Message): Bool { Principal.equal(m.sender, user) }))
  };

  // -------------------------
  // ADMIN / UTILITIES
  // -------------------------

  // Clear all messages. (You may want to restrict this to an admin principal in production.)
  public shared(msg) func clearMessages(): async () {
    messages := [];
    nextMessageId := 0;
  };

  // Clear all users. (You may want to restrict this to an admin principal in production.)
  public shared(msg) func clearUsers(): async () {
    users := [];
  };
};









































