
  // -{
    #User;
    #Moderator;
    #Admin;
  };

  type User = {
    principal: Principal;
    displayName: Text;
    role: UserRole;
  };

  type Reaction = {
    reactor: Principal;
    emoji: Text;
  };

  type Message = {
    id: Nat;
    sender: Principal;
    content: Text;
    timestamp: Time.Time;
    edited: Bool;
    reactions: [Reaction];
    replyTo: ?Nat; // Optional reply message ID (threading)
  };

  // -------------------------
  // Stable storage
  // -------------------------
  stable var users : [User] = [];
  stable var messages : [Message] = [];
  stable var nextMessageId : Nat = 0;

  // Configurable behaviour
  let EDIT_WINDOW_SECONDS : Nat = 15 * 60; // allow edits within 15 minutes

  // -------------------------
  // Helper utilities (private)
  // -------------------------

  private func nowSeconds(): Nat {
    // Convert Time.Time to seconds
    Time.toSeconds(Time.now())
  };

  private func formatIso(ts: Time.Time): Text {
    // Simple human-friendly ISO-like formatter
    let secs = Time.toSeconds(ts);
    let days = secs / 86400;
    let hours = (secs / 3600) % 24;
    let minutes = (secs / 60) % 60;
    let s = secs % 60;
    Text.concat(Text.fromInt(days) # "d " # Text.fromInt(hours) # "h " # Text.fromInt(minutes) # "m " # Text.fromInt(s) # "s")
  };

  private query func getUserIndex(p: Principal): async ?Nat {
    var i: Nat = 0;
    for (u in users.vals()) {
      if (Principal.equal(u.principal, p)) { return ?i };
      i += 1;
    };
    null
  };

  private query func getMessageIndex(id: Nat): async ?Nat {
    var i: Nat = 0;
    for (m in messages.vals()) {
      if (m.id == id) { return ?i };
      i += 1;
    };
    null
  };

  private query func isAdmin(p: Principal): async Bool {
    switch (getUserRole(p)) {
      case (?role) { switch (role) { case (#Admin) { true }; case (_) { false } } };
      case null { false };
    }
  };

  private query func isModeratorOrAdmin(p: Principal): async Bool {
    switch (getUserRole(p)) {
      case (?role) { switch (role) { case (#Admin) { true }; case (#Moderator) { true }; case (_) { false } } };
      case null { false };
    }
  };

  // -------------------------
  // User management
  // -------------------------

  /// Register caller with a display name.
  /// The first registered user becomes Admin.
  public shared(msg) func registerUser(displayName: Text): async Bool {
    let caller = msg.caller;

    // Prevent duplicate registration
    for (u in users.vals()) {
      if (Principal.equal(u.principal, caller)) { return false };
    };

    let role: UserRole = if (Array.size(users) == 0) { #Admin } else { #User };
    users := Array.append(users, [{ principal = caller; displayName = displayName; role = role }]);
    true
  };

  public query func getUsers(): async [User] { users };

  /// Update the display name of the caller
  public shared(msg) func updateUserName(newDisplayName: Text): async Bool {
    let caller = msg.caller;
    var updated = false;
    var tmp: [User] = [];

    for (u in users.vals()) {
      if (Principal.equal(u.principal, caller)) {
        tmp := Array.append(tmp, [{ u with displayName = newDisplayName }]);
        updated := true;
      } else {
        tmp := Array.append(tmp, [u]);
      };
    };

    if (updated) { users := tmp };
    updated
  };

  /// Delete caller's account (removes user but keeps messages for audit)
  public shared(msg) func deleteUser(): async Bool {
    let caller = msg.caller;
    var tmp: [User] = [];
    var deleted = false;

    for (u in users.vals()) {
      if (Principal.equal(u.principal, caller)) {
        deleted := true;
      } else {
        tmp := Array.append(tmp, [u]);
      };
    };

    if (deleted) { users := tmp };
    deleted
  };

  /// Get user's role (nullable)
  public query func getUserRole(user: Principal): async ?UserRole {
    for (u in users.vals()) {
      if (Principal.equal(u.principal, user)) { return ?u.role };
    };
    null
  };

  /// Promote a user to Moderator (admin-only)
  public shared(msg) func addModerator(user: Principal): async Bool {
    if (!await isAdmin(msg.caller)) { return false };
    var tmp: [User] = [];
    var changed = false;

    for (u in users.vals()) {
      if (Principal.equal(u.principal, user)) {
        tmp := Array.append(tmp, [{ u with role = #Moderator }]);
        changed := true;
      } else {
        tmp := Array.append(tmp, [u]);
      };
    };

    if (changed) { users := tmp };
    changed
  };

  /// Revoke moderator or transfer admin (admin-only)
  public shared(msg) func removeModerator(user: Principal): async Bool {
    if (!await isAdmin(msg.caller)) { return false };
    var tmp: [User] = [];
    var changed = false;

    for (u in users.vals()) {
      if (Principal.equal(u.principal, user)) {
        tmp := Array.append(tmp, [{ u with role = #User }]);
        changed := true;
      } else {
        tmp := Array.append(tmp, [u]);
      };
    };

    if (changed) { users := tmp };
    changed
  };

  /// Transfer admin to another user (admin-only)
  public shared(msg) func transferAdmin(newAdmin: Principal): async Bool {
    if (!await isAdmin(msg.caller)) { return false };
    var tmp: [User] = [];
    var found = false;

    for (u in users.vals()) {
      if (Principal.equal(u.principal, newAdmin)) {
        tmp := Array.append(tmp, [{ u with role = #Admin }]);
        found := true;
      } else if (Principal.equal(u.principal, msg.caller)) {
        tmp := Array.append(tmp, [{ u with role = #User }]);
      } else {
        tmp := Array.append(tmp, [u]);
      };
    };

    if (found) { users := tmp };
    found
  };

  // -------------------------
  // Messaging
  // -------------------------

  /// Send a message; returns assigned message id
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

  public query func getMessages(): async [Message] { messages };

  /// Pagination: page starts at 0. Returns most recent messages first.
  public query func getMessagesPage(page: Nat, pageSize: Nat): async [Message] {
    if (pageSize == 0) { return [] };
    let total = Array.size(messages);
    if (total == 0) { return [] };

    // calculate slice indices for reversed ordering
    let startIndex = if ((page * pageSize) >= total) { total } else { total - (page * pageSize) };
    let endIndex = if (startIndex <= pageSize) { 0 } else { startIndex - pageSize };

    var out: [Message] = [];
    var i = startIndex;
    while (i > endIndex) {
      i -= 1; // walk backwards
      out := Array.append(out, [messages[i]]);
    };
    out
  };

  /// Retrieve a message by id
  public query func getMessageById(id: Nat): async ?Message {
    for (m in messages.vals()) {
      if (m.id == id) { return ?m };
    };
    null
  };

  /// Get a thread (message and all replies recursively)
  public query func getThread(rootId: Nat): async [Message] {
    var out: [Message] = [];
    // find root
    for (m in messages.vals()) {
      if (m.id == rootId) { out := Array.append(out, [m]) };
    };

    // collect direct replies (non-recursive for simplicity)
    for (m in messages.vals()) {
      switch (m.replyTo) {
        case (?rid) { if (rid == rootId) { out := Array.append(out, [m]) } };
        case null { () };
      }
    };

    out
  };

  /// Edit message (sender only) — allowed within EDIT_WINDOW_SECONDS, admins can override
  public shared(msg) func editMessage(messageId: Nat, newContent: Text): async Bool {
    let caller = msg.caller;
    var updated = false;
    var tmp: [Message] = [];

    for (m in messages.vals()) {
      if (m.id == messageId) {
        let canEdit = Principal.equal(m.sender, caller) and (nowSeconds() - Time.toSeconds(m.timestamp) <= EDIT_WINDOW_SECONDS);
        // Admins and Moderators can edit any message
        let moderatorOrAdmin = await isModeratorOrAdmin(caller);
        if (canEdit or moderatorOrAdmin) {
          tmp := Array.append(tmp, [{ m with content = newContent; edited = true }]);
          updated := true;
        } else {
          tmp := Array.append(tmp, [m]);
        };
      } else {
        tmp := Array.append(tmp, [m]);
      }
    };

    if (updated) { messages := tmp };
    updated
  };

  /// Delete message (sender can delete their own; moderators/admins can delete any)
  public shared(msg) func deleteMessage(messageId: Nat): async Bool {
    let caller = msg.caller;
    var tmp: [Message] = [];
    var deleted = false;

    for (m in messages.vals()) {
      if (m.id == messageId) {
        if (Principal.equal(m.sender, caller) or (await isModeratorOrAdmin(caller))) {
          deleted := true;
        } else {
          tmp := Array.append(tmp, [m]);
        };
      } else {
        tmp := Array.append(tmp, [m]);
      }
    };

    if (deleted) { messages := tmp };
    deleted
  };

  // -------------------------
  // Reactions
  // -------------------------

  /// Toggle reaction: if the same reactor already used the same emoji on the message, remove it; otherwise add it.
  public shared(msg) func toggleReaction(messageId: Nat, emoji: Text): async Bool {
    let caller = msg.caller;
    var updated = false;
    var tmp: [Message] = [];

    for (m in messages.vals()) {
      if (m.id == messageId) {
        // remove same reaction from same reactor (toggle)
        var found = false;
        var newReacts: [Reaction] = [];
        for (r in m.reactions.vals()) {
          if (Principal.equal(r.reactor, caller) and Text.equal(r.emoji, emoji)) {
            // skip it (effectively removing)
            found := true;
          } else {
            newReacts := Array.append(newReacts, [r]);
          };
        };

        if (found) {
          tmp := Array.append(tmp, [{ m with reactions = newReacts }]);
        } else {
          let r: Reaction = { reactor = caller; emoji = emoji };
          tmp := Array.append(tmp, [{ m with reactions = Array.append(m.reactions, [r]) }]);
        };
        updated := true;
      } else {
        tmp := Array.append(tmp, [m]);
      }
    };

    if (updated) { messages := tmp };
    updated
  };

  // -------------------------
  // Search & counts
  // -------------------------

  public query func searchMessages(keyword: Text): async [Message] {
    if (Text.size(keyword) == 0) { return [] };
    let lowerKeyword = Text.toLower(keyword);
    Array.filter(messages, func(m: Message): Bool { Text.contains(Text.toLower(m.content), lowerKeyword) })
  };

  public query func messageCount(): async Nat { Array.size(messages) };

  public query func userMessageCount(user: Principal): async Nat {
    Array.size(Array.filter(messages, func(m: Message): Bool { Principal.equal(m.sender, user) }))
  };

  // -------------------------
  // Admin utilities
  // -------------------------

  public shared(msg) func clearMessages(): async Bool {
    if (!(await isAdmin(msg.caller))) { return false };
    messages := [];
    nextMessageId := 0;
    true
  };

  public shared(msg) func clearUsers(): async Bool {
    if (!(await isAdmin(msg.caller))) { return false };
    users := [];
    true
  };

  // -------------------------
  // Formatting helpers exposed as queries
  // -------------------------

  public query func formatTimestamp(ts: Time.Time): async Text { formatIso(ts) };

  public query func whoAmI(): async ?User {
    // returns user record for caller (if registered)
    let caller = Principal.fromActor(this);
    for (u in users.vals()) {
      if (Principal.equal(u.principal, caller)) { return ?u };
    };
    null
  };

};






























