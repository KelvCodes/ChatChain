
    content   : Text;
    timestamp : Nat;
    edited    : Bool;
    deleted   : Bool;
    pinned    : Bool;
    reactions : [Reaction];
    replyTo   : ?Nat;
  };

  // ===========================================================================
  // STABLE STATE
  // ===========================================================================

  stable var users         : [User]    = [];
  stable var messages      : [Message] = [];
  stable var nextMessageId : Nat        = 0;
  stable var lastSendMap   : [(Principal, Nat)] = [];

  // ===========================================================================
  // PRIVATE HELPERS
  // ===========================================================================

  private func now() : Nat {
    Time.toSeconds(Time.now())
  };

  private func findUser(p : Principal) : ?User {
    for (u in users.vals()) {
      if (Principal.equal(u.principal, p)) return ?u;
    };
    null
  };

  private func isAdmin(p : Principal) : Bool {
    switch (findUser(p)) {
      case (?u) { u.role == #Admin };
      case null false;
    }
  };

  private func isModOrAdmin(p : Principal) : Bool {
    switch (findUser(p)) {
      case (?u) { u.role == #Admin or u.role == #Moderator };
      case null false;
    }
  };

  private func isBanned(p : Principal) : Bool {
    switch (findUser(p)) {
      case (?u) u.banned;
      case null true;
    }
  };

  private func updateLastSeen(p : Principal) {
    users := Array.map(users, func(u) {
      if (Principal.equal(u.principal, p)) {
        { u with lastSeen = now() }
      } else u
    });
  };

  private func rateLimited(p : Principal) : Bool {
    let t = now();
    var blocked = false;

    lastSendMap := Array.map(lastSendMap, func(e) {
      if (Principal.equal(e.0, p)) {
        if (t - e.1 < RATE_LIMIT_SECONDS) blocked := true;
        (p, t)
      } else e
    });

    if (not blocked) {
      lastSendMap := Array.append(lastSendMap, [(p, t)]);
    };

    blocked
  };

  // ===========================================================================
  // USER MANAGEMENT
  // ===========================================================================

  public shared ({ caller }) func registerUser(name : Text) : async Bool {
    if (findUser(caller) != null) return false;

    let role = if (users.size() == 0) #Admin else #User;

    users := Array.append(users, [{
      principal = caller;
      displayName = name;
      role = role;
      banned = false;
      lastSeen = now();
    }]);

    true
  };

  public query func getUsers() : async [User] { users };

  public shared ({ caller }) func banUser(p : Principal) : async Bool {
    if (!isModOrAdmin(caller)) return false;

    users := Array.map(users, func(u) {
      if (Principal.equal(u.principal, p)) {
        { u with banned = true }
      } else u
    });

    true
  };

  public shared ({ caller }) func unbanUser(p : Principal) : async Bool {
    if (!isModOrAdmin(caller)) return false;

    users := Array.map(users, func(u) {
      if (Principal.equal(u.principal, p)) {
        { u with banned = false }
      } else u
    });

    true
  };

  // ===========================================================================
  // MESSAGES
  // ===========================================================================

  public shared ({ caller }) func sendMessage(
    content : Text,
    replyTo : ?Nat
  ) : async ?Nat {

    if (isBanned(caller)) return null;
    if (Text.size(content) == 0 or Text.size(content) > MAX_MESSAGE_LENGTH)
      return null;
    if (rateLimited(caller)) return null;

    let id = nextMessageId;
    nextMessageId += 1;

    messages := Array.append(messages, [{
      id = id;
      sender = caller;
      content = content;
      timestamp = now();
      edited = false;
      deleted = false;
      pinned = false;
      reactions = [];
      replyTo = replyTo;
    }]);

    updateLastSeen(caller);
    ?id
  };

  public shared ({ caller }) func editMessage(
    id : Nat,
    newContent : Text
  ) : async Bool {

    messages := Array.map(messages, func(m) {
      if (m.id == id and not m.deleted) {
        if (
          Principal.equal(m.sender, caller)
          or isModOrAdmin(caller)
        ) {
          { m with content = newContent; edited = true }
        } else m
      } else m
    });

    true
  };

  public shared ({ caller }) func softDeleteMessage(id : Nat) : async Bool {
    if (!isModOrAdmin(caller)) return false;

    messages := Array.map(messages, func(m) {
      if (m.id == id) {
        { m with deleted = true }
      } else m
    });

    true
  };

  public shared ({ caller }) func pinMessage(id : Nat) : async Bool {
    if (!isModOrAdmin(caller)) return false;

    messages := Array.map(messages, func(m) {
      if (m.id == id) { { m with pinned = true } } else m
    });

    true
  };

  public query func getPinnedMessages() : async [Message] {
    Array.filter(messages, func(m) { m.pinned and not m.deleted })
  };

  public query func getMessagesPage(
    page : Nat,
    size : Nat
  ) : async [Message] {

    let total = messages.size();
    let start = Nat.max(0, total - (page + 1) * size);
    let end = Nat.max(0, total - page * size);

    var out : [Message] = [];
    var i = end;

    while (i > start) {
      i -= 1;
      if (not messages[i].deleted)
        out := Array.append(out, [messages[i]]);
    };

    out
  };

  public query func getThread(root : Nat) : async [Message] {
    Array.filter(messages, func(m) {
      m.id == root or m.replyTo == ?root
    })
  };

  // ===========================================================================
  // REACTIONS
  // ===========================================================================

  public shared ({ caller }) func toggleReaction(
    messageId : Nat,
    emoji : Text
  ) : async Bool {

    messages := Array.map(messages, func(m) {
      if (m.id == messageId) {
        var exists = false;

        let filtered = Array.filter(m.reactions, func(r) {
          let same =
            Principal.equal(r.reactor, caller)
            and Text.equal(r.emoji, emoji);
          if (same) exists := true;
          not same
        });

        if (exists) {
          { m with reactions = filtered }
        } else {
          { m with reactions = Array.append(filtered, [{
            reactor = caller;
            emoji = emoji;
          }]) }
        }
      } else m
    });

    true
  };

  // ===========================================================================
  // ADMIN UTILITIES
  // ===========================================================================

  public shared ({ caller }) func clearMessages() : async Bool {
    if (!isAdmin(caller)) return false;
    messages := [];
    nextMessageId := 0;
    true
  };

  public query ({ caller }) func whoAmI() : async ?User {
    findUser(caller)
  };
}





























