S
  // ===========================================================================

  private func nowSeconds() : Nat {
    Time.toSeconds(Time.now())
  };

  private func isWithinEditWindow(ts : Time.Time) : Bool {
    nowSeconds() - Time.toSeconds(ts) <= EDIT_WINDOW_SECONDS
  };

  private func formatIso(ts : Time.Time) : Text {
    let s = Time.toSeconds(ts);
    let d = s / 86400;
    let h = (s / 3600) % 24;
    let m = (s / 60) % 60;
    let sec = s % 60;

    Text.concat(
      Text.fromInt(d) # "d " #
      Text.fromInt(h) # "h " #
      Text.fromInt(m) # "m " #
      Text.fromInt(sec) # "s"
    )
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
      case null { false };
    }
  };

  private func isModOrAdmin(p : Principal) : Bool {
    switch (findUser(p)) {
      case (?u) {
        u.role == #Admin or u.role == #Moderator
      };
      case null { false };
    }
  };

  // ===========================================================================
  // USER MANAGEMENT
  // ===========================================================================

  /// Register a user (first user becomes Admin)
  public shared ({ caller }) func registerUser(name : Text) : async Bool {
    if (findUser(caller) != null) return false;

    let role : UserRole =
      if (users.size() == 0) #Admin else #User;

    users := Array.append(users, [{
      principal = caller;
      displayName = name;
      role = role;
    }]);

    true
  };

  public query func getUsers() : async [User] { users };

  public shared ({ caller }) func updateDisplayName(name : Text) : async Bool {
    var updated = false;

    users := Array.map(users, func(u) {
      if (Principal.equal(u.principal, caller)) {
        updated := true;
        { u with displayName = name }
      } else u
    });

    updated
  };

  public shared ({ caller }) func deleteAccount() : async Bool {
    let before = users.size();
    users := Array.filter(users, func(u) {
      not Principal.equal(u.principal, caller)
    });
    users.size() < before
  };

  public query func getUserRole(p : Principal) : async ?UserRole {
    switch (findUser(p)) {
      case (?u) ?u.role;
      case null null;
    }
  };

  // ---------------- ADMIN CONTROLS ----------------

  public shared ({ caller }) func addModerator(p : Principal) : async Bool {
    if (!isAdmin(caller)) return false;

    var changed = false;
    users := Array.map(users, func(u) {
      if (Principal.equal(u.principal, p)) {
        changed := true;
        { u with role = #Moderator }
      } else u
    });

    changed
  };

  public shared ({ caller }) func removeModerator(p : Principal) : async Bool {
    if (!isAdmin(caller)) return false;

    var changed = false;
    users := Array.map(users, func(u) {
      if (Principal.equal(u.principal, p)) {
        changed := true;
        { u with role = #User }
      } else u
    });

    changed
  };

  public shared ({ caller }) func transferAdmin(p : Principal) : async Bool {
    if (!isAdmin(caller)) return false;

    var found = false;
    users := Array.map(users, func(u) {
      if (Principal.equal(u.principal, p)) {
        found := true;
        { u with role = #Admin }
      } else if (Principal.equal(u.principal, caller)) {
        { u with role = #User }
      } else u
    });

    found
  };

  // ===========================================================================
  // MESSAGES
  // ===========================================================================

  public shared ({ caller }) func sendMessage(
    content : Text,
    replyTo : ?Nat
  ) : async Nat {

    let id = nextMessageId;
    nextMessageId += 1;

    messages := Array.append(messages, [{
      id = id;
      sender = caller;
      content = content;
      timestamp = Time.now();
      edited = false;
      reactions = [];
      replyTo = replyTo;
    }]);

    id
  };

  public query func getMessages() : async [Message] { messages };

  /// Paginated, newest first
  public query func getMessagesPage(
    page : Nat,
    pageSize : Nat
  ) : async [Message] {

    if (pageSize == 0) return [];

    let total = messages.size();
    let start = total - Nat.min(total, (page + 1) * pageSize);
    let end   = total - Nat.min(total, page * pageSize);

    var out : [Message] = [];
    var i = end;
    while (i > start) {
      i -= 1;
      out := Array.append(out, [messages[i]]);
    };

    out
  };

  public query func getMessageById(id : Nat) : async ?Message {
    for (m in messages.vals()) {
      if (m.id == id) return ?m;
    };
    null
  };

  public query func getThread(rootId : Nat) : async [Message] {
    Array.filter(messages, func(m) {
      m.id == rootId or m.replyTo == ?rootId
    })
  };

  public shared ({ caller }) func editMessage(
    id : Nat,
    content : Text
  ) : async Bool {

    var edited = false;

    messages := Array.map(messages, func(m) {
      if (m.id == id) {
        if (
          (Principal.equal(m.sender, caller) and isWithinEditWindow(m.timestamp))
          or isModOrAdmin(caller)
        ) {
          edited := true;
          { m with content = content; edited = true }
        } else m
      } else m
    });

    edited
  };

  public shared ({ caller }) func deleteMessage(id : Nat) : async Bool {
    let before = messages.size();

    messages := Array.filter(messages, func(m) {
      if (m.id == id) {
        not (
          Principal.equal(m.sender, caller)
          or isModOrAdmin(caller)
        )
      } else true
    });

    messages.size() < before
  };

  // ===========================================================================
  // REACTIONS
  // ===========================================================================

  public shared ({ caller }) func toggleReaction(
    messageId : Nat,
    emoji : Text
  ) : async Bool {

    var updated = false;

    messages := Array.map(messages, func(m) {
      if (m.id == messageId) {
        var exists = false;

        let filtered = Array.filter(m.reactions, func(r) {
          let same = Principal.equal(r.reactor, caller)
            and Text.equal(r.emoji, emoji);
          if (same) exists := true;
          not same
        });

        updated := true;

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

    updated
  };

  // ===========================================================================
  // SEARCH & STATS
  // ===========================================================================

  public query func searchMessages(keyword : Text) : async [Message] {
    let k = Text.toLower(keyword);
    Array.filter(messages, func(m) {
      Text.contains(Text.toLower(m.content), k)
    })
  };

  public query func messageCount() : async Nat {
    messages.size()
  };

  public query func userMessageCount(p : Principal) : async Nat {
    Array.size(Array.filter(messages, func(m) {
      Principal.equal(m.sender, p)
    }))
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

  public shared ({ caller }) func clearUsers() : async Bool {
    if (!isAdmin(caller)) return false;
    users := [];
    true
  };

  // ===========================================================================
  // PUBLIC HELPERS
  // ===========================================================================

  public query func formatTimestamp(ts : Time.Time) : async Text {
    formatIso(ts)
  };

  public query ({ caller }) func whoAmI() : async ?User {
    findUser(caller)
  };
};































































