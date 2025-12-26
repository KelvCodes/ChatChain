// ============================================================================
// ChatChain v3 — Large-Scale, Enterprise-Ready Chat Canister
// Author: Kelvin Agyare Yeboah
// Description:
// Fully-featured decentralized chat system with moderation, threading,
// reactions, audit logs, rate limiting, read receipts, and upgrade safety.
// ============================================================================
  "mo:ort Bo// ============================================================================
// ACTOR
// ============================================================================

actor ChatChain {

  // ===========================================================================
  // CONSTANTS
  // ===========================================================================

  let EDIT_WINDOW_SECONDS : Nat = 15 * 60;
  let RATE_LIMIT_WINDOW   : Nat = 10;   // seconds
  let RATE_LIMIT_MAX      : Nat = 5;    // messages per window

  // ===========================================================================
  // TYPES
  // ===========================================================================

  public type UserRole = { #User; #Moderator; #Admin };

  public type User = {
    principal   : Principal;
    displayName : Text;
    role        : UserRole;
    joinedAt    : Time.Time;
  };

  public type Reaction = {
    reactor : Principal;
    emoji   : Text;
  };

  public type EditRecord = {
    oldContent : Text;
    editedAt   : Time.Time;
  };

  public type Message = {
    id          : Nat;
    sender      : Principal;
    content     : Text;
    timestamp   : Time.Time;
    edited      : Bool;
    editHistory : [EditRecord];
    reactions   : [Reaction];
    replyTo     : ?Nat;
    deleted     : Bool;
    readBy      : [Principal];
    pinned      : Bool;
  };

  public type AuditEvent = {
    actor     : Principal;
    action    : Text;
    targetId  : ?Nat;
    timestamp : Time.Time;
  };

  // ===========================================================================
  // STABLE STORAGE (UPGRADE SAFE)
  // ===========================================================================

  stable var usersStable    : [(Principal, User)]  = [];
  stable var messagesStable : [(Nat, Message)]     = [];
  stable var auditStable    : [AuditEvent]         = [];
  stable var nextMessageId : Nat                   = 0;

  // ===========================================================================
  // RUNTIME STATE
  // ===========================================================================

  let users       = HashMap.HashMap<Principal, User>(32, Principal.equal, Principal.hash);
  let messages    = HashMap.HashMap<Nat, Message>(256, Nat.equal, Nat.hash);
  let auditLog    = Array.Buffer<AuditEvent>(0);
  let rateLimiter = HashMap.HashMap<Principal, [Time.Time]>(32, Principal.equal, Principal.hash);
  let typingUsers = HashMap.HashMap<Principal, Time.Time>(32, Principal.equal, Principal.hash);

  // ===========================================================================
  // SYSTEM HOOKS
  // ===========================================================================

  system func preupgrade() {
    usersStable := Iter.toArray(users.entries());
    messagesStable := Iter.toArray(messages.entries());
    auditStable := auditLog.toArray();
  };

  system func postupgrade() {
    for ((k, v) in usersStable.vals()) { users.put(k, v) };
    for ((k, v) in messagesStable.vals()) { messages.put(k, v) };
    for (e in auditStable.vals()) { auditLog.add(e) };

    usersStable := [];
    messagesStable := [];
    auditStable := [];
  };

  // ===========================================================================
  // PRIVATE HELPERS
  // ===========================================================================

  private func now() : Time.Time { Time.now() };

  private func nowSeconds() : Nat {
    Time.toSeconds(Time.now())
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

  private func log(actor : Principal, action : Text, target : ?Nat) {
    auditLog.add({
      actor = actor;
      action = action;
      targetId = target;
      timestamp = now();
    });
  };

  private func checkRateLimit(p : Principal) : Bool {
    let t = now();
    let prev = switch (rateLimiter.get(p)) {
      case (?arr) arr;
      case null [];
    };

    let recent = Array.filter(prev, func(ts) {
      Time.toSeconds(t) - Time.toSeconds(ts) <= RATE_LIMIT_WINDOW
    });

    if (recent.size() >= RATE_LIMIT_MAX) return false;

    rateLimiter.put(p, Array.append(recent, [t]));
    true
  };

  private func allMessages() : [Message] {
    Iter.toArray(messages.vals())
  };

  // ===========================================================================
  // USER MANAGEMENT
  // ===========================================================================

  public shared ({ caller }) func registerUser(name : Text) : async Bool {
    if (users.get(caller) != null) return false;

    let role : UserRole = if (users.size() == 0) #Admin else #User;

    users.put(caller, {
      principal = caller;
      displayName = name;
      role = role;
      joinedAt = now();
    });

    log(caller, "REGISTER_USER", null);
    true
  };

  public query func getUsers() : async [User] {
    Iter.toArray(users.vals())
  };

  public query ({ caller }) func whoAmI() : async ?User {
    users.get(caller)
  };

  // ===========================================================================
  // MESSAGING
  // ===========================================================================

  public shared ({ caller }) func sendMessage(
    content : Text,
    replyTo : ?Nat
  ) : async ?Nat {

    if (!checkRateLimit(caller)) return null;

    let id = nextMessageId;
    nextMessageId += 1;

    messages.put(id, {
      id = id;
      sender = caller;
      content = content;
      timestamp = now();
      edited = false;
      editHistory = [];
      reactions = [];
      replyTo = replyTo;
      deleted = false;
      readBy = [caller];
      pinned = false;
    });

    log(caller, "SEND_MESSAGE", ?id);
    ?id
  };

  public shared ({ caller }) func editMessage(id : Nat, text : Text) : async Bool {
    switch (messages.get(id)) {
      case (?m) {
        if (
          (Principal.equal(m.sender, caller)
            and nowSeconds() - Time.toSeconds(m.timestamp) <= EDIT_WINDOW_SECONDS)
          or isModOrAdmin(caller)
        ) {
          messages.put(id, {
            m with
            content = text;
            edited = true;
            editHistory = Array.append(m.editHistory, [{
              oldContent = m.content;
              editedAt = now();
            }])
          });
          log(caller, "EDIT_MESSAGE", ?id);
          true
        } else false
      };
      case null false;
    }
  };

  public shared ({ caller }) func softDeleteMessage(id : Nat) : async Bool {
    switch (messages.get(id)) {
      case (?m) {
        if (Principal.equal(m.sender, caller) or isModOrAdmin(caller)) {
          messages.put(id, { m with deleted = true });
          log(caller, "DELETE_MESSAGE", ?id);
          true
        } else false
      };
      case null false;
    }
  };

  // ===========================================================================
  // READ RECEIPTS
  // ===========================================================================

  public shared ({ caller }) func markAsRead(id : Nat) : async Bool {
    switch (messages.get(id)) {
      case (?m) {
        if (Array.find(m.readBy, func(p) { Principal.equal(p, caller) }) != null) {
          true
        } else {
          messages.put(id, { m with readBy = Array.append(m.readBy, [caller]) });
          true
        }
      };
      case null false;
    }
  };

  // ===========================================================================
  // TYPING INDICATOR
  // ===========================================================================

  public shared ({ caller }) func setTyping() : async () {
    typingUsers.put(caller, now());
  };

  public query func getTypingUsers() : async [Principal] {
    let t = nowSeconds();
    Iter.toArray(
      Iter.filter(typingUsers.entries(), func((p, ts)) {
        t - Time.toSeconds(ts) <= 5
      })
    ).map(func((p, _)) { p })
  };

  // ===========================================================================
  // PINNING
  // ===========================================================================

  public shared ({ caller }) func pinMessage(id : Nat) : async Bool {
    if (!isModOrAdmin(caller)) return false;

    switch (messages.get(id)) {
      case (?m) {
        messages.put(id, { m with pinned = true });
        log(caller, "PIN_MESSAGE", ?id);
        true
      };
      case null false;
    }
  };

  // ===========================================================================
  // SEARCH & ADMIN
  // ===========================================================================

  public query func searchMessages(keyword : Text) : async [Message] {
    let k = Text.toLower(keyword);
    Array.filter(allMessages(), func(m) {
      Text.contains(Text.toLower(m.content), k) and not m.deleted
    })
  };

  public query func getAuditLog() : async [AuditEvent] {
    auditLog.toArray(












