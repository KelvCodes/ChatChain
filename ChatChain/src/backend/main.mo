
  system func preupgrade() {
    usersStable := Iter.toArray(users.entries());
    messagesStable := Iter.toArray(messages.entries());
  };

  system func postupgrade() {
    for ((k, v) in usersStable.vals()) { users.put(k, v) };
    for ((k, v) in messagesStable.vals()) { messages.put(k, v) };
    usersStable := [];
    messagesStable := [];
  };

  // ===========================================================================
  // PRIVATE HELPERS
  // ===========================================================================

  private func nowSeconds() : Nat {
    Time.toSeconds(Time.now())
  };

  private func canEdit(ts : Time.Time) : Bool {
    nowSeconds() - Time.toSeconds(ts) <= EDIT_WINDOW_SECONDS
  };

  private func isAdmin(p : Principal) : Bool {
    switch (users.get(p)) {
      case (?u) { u.role == #Admin };
      case null false;
    }
  };

  private func isModOrAdmin(p : Principal) : Bool {
    switch (users.get(p)) {
      case (?u) { u.role == #Admin or u.role == #Moderator };
      case null false;
    }
  };

  private func messageArray() : [Message] {
    Iter.toArray(messages.vals())
  };

  // ===========================================================================
  // USER MANAGEMENT
  // ===========================================================================

  public shared ({ caller }) func registerUser(name : Text) : async Bool {
    if (users.get(caller) != null) return false;

    let role : UserRole =
      if (users.size() == 0) #Admin else #User;

    users.put(caller, {
      principal = caller;
      displayName = name;
      role = role;
    });

    true
  };

  public query func getUsers() : async [User] {
    Iter.toArray(users.vals())
  };

  public shared ({ caller }) func updateDisplayName(name : Text) : async Bool {
    switch (users.get(caller)) {
      case (?u) {
        users.put(caller, { u with displayName = name });
        true
      };
      case null false;
    }
  };

  public shared ({ caller }) func deleteAccount() : async Bool {
    users.remove(caller) != null
  };

  public query func whoAmI() : async ?User {
    users.get(Principal.fromActor(this)) // frontend override later
  };

  // ---------------- ADMIN ----------------

  public shared ({ caller }) func addModerator(p : Principal) : async Bool {
    if (!isAdmin(caller)) return false;
    switch (users.get(p)) {
      case (?u) { users.put(p, { u with role = #Moderator }); true };
      case null false;
    }
  };

  public shared ({ caller }) func removeModerator(p : Principal) : async Bool {
    if (!isAdmin(caller)) return false;
    switch (users.get(p)) {
      case (?u) { users.put(p, { u with role = #User }); true };
      case null false;
    }
  };

  public shared ({ caller }) func transferAdmin(p : Principal) : async Bool {
    if (!isAdmin(caller)) return false;

    switch (users.get(p)) {
      case (?newAdmin) {
        users.put(p, { newAdmin with role = #Admin });
        switch (users.get(caller)) {
          case (?old) { users.put(caller, { old with role = #User }) };
          case null ();
        };
        true
      };
      case null false;
    }
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

    messages.put(id, {
      id = id;
      sender = caller;
      content = content;
      timestamp = Time.now();
      edited = false;
      reactions = [];
      replyTo = replyTo;
    });

    id
  };

  public query func getMessageById(id : Nat) : async ?Message {
    messages.get(id)
  };

  /// Newest-first pagination
  public query func getMessagesPage(page : Nat, size : Nat) : async [Message] {
    if (size == 0) return [];

    let all = messageArray();
    let sorted = Array.sort(all, func(a, b) { b.id < a.id });

    let start = page * size;
    let end = Nat.min(start + size, sorted.size());

    if (start >= sorted.size()) return [];
    Array.slice(sorted, start, end - start)
  };

  public query func getThread(rootId : Nat) : async [Message] {
    Array.filter(messageArray(), func(m) {
      m.id == rootId or m.replyTo == ?rootId
    })
  };

  public shared ({ caller }) func editMessage(id : Nat, text : Text) : async Bool {
    switch (messages.get(id)) {
      case (?m) {
        if (
          (Principal.equal(m.sender, caller) and canEdit(m.timestamp))
          or isModOrAdmin(caller)
        ) {
          messages.put(id, { m with content = text; edited = true });
          true
        } else false
      };
      case null false;
    }
  };

  public shared ({ caller }) func deleteMessage(id : Nat) : async Bool {
    switch (messages.get(id)) {
      case (?m) {
        if (Principal.equal(m.sender, caller) or isModOrAdmin(caller)) {
          messages.remove(id);
          true
        } else false
      };
      case null false;
    }
  };

  // ===========================================================================
  // REACTIONS (1 emoji per user per message)
  // ===========================================================================

  public shared ({ caller }) func toggleReaction(
    messageId : Nat,
    emoji : Text
  ) : async Bool {

    switch (messages.get(messageId)) {
      case (?m) {
        let filtered = Array.filter(m.reactions, func(r) {
          not Principal.equal(r.reactor, caller)
        });

        let exists = Array.size(filtered) < Array.size(m.reactions);

        let newReactions =
          if (exists) filtered
          else Array.append(filtered, [{
            reactor = caller;
            emoji = emoji;
          }]);

        messages.put(messageId, { m with reactions = newReactions });
        true
      };
      case null false;
    }
  };

  // ===========================================================================
  // SEARCH & STATS
  // ===========================================================================

  public query func searchMessages(keyword : Text) : async [Message] {
    let k = Text.toLower(keyword);
    Array.filter(messageArray(), func(m) {
      Text.contains(Text.toLower(m.content), k)
    })
  };

  public query func messageCount() : async Nat {
    messages.size()
  };

  public query func userMessageCount(p : Principal) : async Nat {
    Array.size(Array.filter(messageArray(), func(m) {
      Principal.equal(m.sender, p)
    }))
  };

  // ===========================================================================
  // ADMIN UTILITIES
  // ===========================================================================

  public shared ({ caller }) func clearMessages() : async Bool {
    if (!isAdmin(caller)) return false;
    messages.clear();
    nextMessageId := 0;
    true
  };

  public shared ({ caller }) func clearUsers() : async Bool {
    if (!isAdmin(caller)) return false;
    users.clear();
    true
  };
};


























































