


  // Stable storage (persistent across upgrades)
  // -------------------------
  stable var users : [User] = [];
  stable var messages : [Message] = [];
  stable var nextMessageId : Nat = 0;

  // -------------------------
  // USER MANAGEMENT
  // -------------------------

  // Register caller with a display name. Admin by default is only the first user.
  public shared(msg) func registerUser(displayName: Text): async Bool {
    let caller = msg.caller;

    for (u in users.vals()) {
      if (Principal.equal(u.principal, caller)) {
        return false;
      };
    };

    let role: UserRole = if (Array.size(users) == 0) { #Admin } else { #User };
    users := Array.append(users, [{ principal = caller; displayName = displayName; role = role }]);
    return true;
  };

  public query func getUsers(): async [User] {
    users
  };

  public shared(msg) func updateUserName(newDisplayName: Text): async Bool {
    let caller = msg.caller;
    var updated: Bool = false;
    var tmp: [User] = [];

    for (u in users.vals()) {
      if (Principal.equal(u.principal, caller)) {
        tmp := Array.append(tmp, [{ u with displayName = newDisplayName }]);
        updated := true;
      } else {
        tmp := Array.append(tmp, [u]);
      }
    };

    if (updated) { users := tmp };
    updated
  };

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

    if (deleted) { users := tmp };
    deleted
  };

  public query func getUserRole(user: Principal): async ?UserRole {
    for (u in users.vals()) {
      if (Principal.equal(u.principal, user)) {
        return ?u.role;
      }
    };
    return null;
  };

  // -------------------------
  // MESSAGING
  // -------------------------

  public shared(msg) func sendMessage(content: Text, replyTo: ?Nat): async Nat {
    let sender = msg.caller;
    let id = nextMessageId;

    let m: Message = {
      id = id;
      sender = sender;
      content = content;
      timestamp = Time.now();
      edited = false;
      reactions = [];
      replyTo = replyTo;
    };

    nextMessageId += 1;
    messages := Array.append(messages, [m]);
    id
  };

  public query func getMessages(): async [Message] {
    messages
  };

  public query func getMessagesSince(since: Time.Time): async [Message] {
    Array.filter(messages, func(m: Message): Bool { m.timestamp >= since })
  };

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

    if (updated) { messages := tmp };
    updated
  };

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

    if (deleted) { messages := tmp };
    deleted
  };

  // Reactions (like emoji)
  public shared(msg) func addReaction(messageId: Nat, emoji: Text): async Bool {
    let caller = msg.caller;
    var updated: Bool = false;
    var tmp: [Message] = [];

    for (m in messages.vals()) {
      if (m.id == messageId) {
        let r: Reaction = { reactor = caller; emoji = emoji };
        tmp := Array.append(tmp, [{ m with reactions = Array.append(m.reactions, [r]) }]);
        updated := true;
      } else {
        tmp := Array.append(tmp, [m]);
      }
    };

    if (updated) { messages := tmp };
    updated
  };

  // Search messages (case-insensitive)
  public query func searchMessages(keyword: Text): async [Message] {
    if (Text.size(keyword) == 0) { return [] };
    let lowerKeyword = Text.toLower(keyword);
    Array.filter(messages, func(m: Message): Bool { Text.contains(Text.toLower(m.content), lowerKeyword) })
  };

  public query func messageCount(): async Nat {
    Array.size(messages)
  };

  public query func userMessageCount(user: Principal): async Nat {
    Array.size(Array.filter(messages, func(m: Message): Bool { Principal.equal(m.sender, user) }))
  };

  // -------------------------
  // ADMIN / UTILITIES
  // -------------------------

  private func isAdmin(p: Principal): Bool {
    switch (getUserRole(p)) {
      case (?role) { switch (role) { case (#Admin) { true }; case (#User) { false } } };
      case null { false };
    }
  };

  public shared(msg) func clearMessages(): async Bool {
    if (!isAdmin(msg.caller)) { return false };
    messages := [];
    nextMessageId := 0;
    true
  };

  public shared(msg) func clearUsers(): async Bool {
    if (!isAdmin(msg.caller)) { return false };
    users := [];
    true
  };

  // Format timestamp as readable string
  public query func formatTimestamp(ts: Time.Time): async Text {
    let seconds = Time.toSeconds(ts);
    let days = seconds / 86400;
    let hours = (seconds / 3600) % 24;
    let minutes = (seconds / 60) % 60;
    let secs = seconds % 60;
    Text.concat(Text.fromInt(days) # "d " # Text.fromInt(hours) # "h " # Text.fromInt(minutes) # "m " # Text.fromInt(secs) # "s")
  };
};







































