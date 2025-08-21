
import Array "mo:base/Array";

actor ChatChain {

  // -------------------------------
  // TYPE DEFINITIONS
  // -------------------------------
  type Message = {
    id: Nat;               // Unique ID for message
    sender: Principal;     
    content: Text;         
    timestamp: Time.Time;  
  };

  // -------------------------------
  // STABLE STORAGE VARIABLES
  // -------------------------------
  stable var messages: [Message] = [];
  stable var users: [(Principal, Text)] = [];
  stable var nextMessageId: Nat = 0; // for unique message IDs

  // -------------------------------
  // IN-MEMORY BUFFERS
  // -------------------------------
  let messageBuffer = Buffer.Buffer<Message>(100);
  let userBuffer = Buffer.Buffer<(Principal, Text)>(100);

  // -------------------------------
  // USER REGISTRATION / MANAGEMENT
  // -------------------------------
  public shared(msg) func registerUser(name: Text): async Bool {
    let caller = msg.caller;

    for ((principal, _) in userBuffer.toArray().vals()) {
      if (Principal.equal(principal, caller)) {
        return false;
      }
    };

    userBuffer.add((caller, name));
    users := userBuffer.toArray();
    return true;
  };

  public query func getUsers(): async [(Principal, Text)] {
    userBuffer.toArray();
  };

  // Update user display name
  public shared(msg) func updateUserName(newName: Text): async Bool {
    let caller = msg.caller;
    var found = false;
    var tempUsers: [(Principal, Text)] = [];

    for ((p, n) in userBuffer.toArray().vals()) {
      if (Principal.equal(p, caller)) {
        tempUsers := Array.append(tempUsers, [(p, newName)]);
        found := true;
      } else {
        tempUsers := Array.append(tempUsers, [(p, n)]);
      }
    };

    if (found) {
      userBuffer.clear();
      for (u in tempUsers.vals()) { userBuffer.add(u); }
      users := userBuffer.toArray();
    };
    return found;
  };

  public shared(msg) func deleteUser(): async Bool {
    let caller = msg.caller;
    var tempUsers: [(Principal, Text)] = [];
    var found = false;

    for ((p, n) in userBuffer.toArray().vals()) {
      if (Principal.equal(p, caller)) {
        found := true;
      } else {
        tempUsers := Array.append(tempUsers, [(p, n)]);
      }
    };

    if (found) {
      userBuffer.clear();
      for (u in tempUsers.vals()) { userBuffer.add(u); }
      users := userBuffer.toArray();
    };
    return found;
  };

  // -------------------------------
  // MESSAGE SENDING / RETRIEVAL
  // -------------------------------
  public shared(msg) func sendMessage(content: Text): async Nat {
    let newMessage: Message = {
      id = nextMessageId;
      sender = msg.caller;
      content = content;
      timestamp = Time.now();
    };
    nextMessageId += 1;

    messageBuffer.add(newMessage);
    messages := messageBuffer.toArray();
    return newMessage.id;
  };

  public query func getMessages(): async [Message] {
    messages;
  };

  public query func getMessagesSince(timestamp: Time.Time): async [Message] {
    Array.filter(messages, func(msg: Message): Bool { msg.timestamp >= timestamp })
  };

  // Edit a message (only sender can edit)
  public shared(msg) func editMessage(messageId: Nat, newContent: Text): async Bool {
    let caller = msg.caller;
    var updated = false;

    var tempMessages: [Message] = [];
    for (m in messages.vals()) {
      if (m.id == messageId && Principal.equal(m.sender, caller)) {
        tempMessages := Array.append(tempMessages, [{ m with content = newContent }]);
        updated := true;
      } else {
        tempMessages := Array.append(tempMessages, [m]);
      }
    };

    if (updated) {
      messageBuffer.clear();
      for (m in tempMessages.vals()) { messageBuffer.add(m); }
      messages := messageBuffer.toArray();
    };
    return updated;
  };

  // Delete a message (only sender can delete)
  public shared(msg) func deleteMessage(messageId: Nat): async Bool {
    let caller = msg.caller;
    var tempMessages: [Message] = [];
    var deleted = false;

    for (m in messages.vals()) {
      if (m.id == messageId && Principal.equal(m.sender, caller)) {
        deleted := true;
      } else {
        tempMessages := Array.append(tempMessages, [m]);
      }
    };

    if (deleted) {
      messageBuffer.clear();
      for (m in tempMessages.vals()) { messageBuffer.add(m); }
      messages := messageBuffer.toArray();
    };
    return deleted;
  };

  // Search messages by keyword
  public query func searchMessages(keyword: Text): async [Message] {
    Array.filter(messages, func(m: Message): Bool {
      Text.contains(m.content, keyword)
    })
  };

  // Get message count
  public query func messageCount(): async Nat {
    Array.size(messages)
  };

  public query func userMessageCount(user: Principal): async Nat {
    Array.size(Array.filter(messages, func(m: Message): Bool {
      Principal.equal(m.sender, user)
    }))
  };

  // -------------------------------
  // ADMIN / UTILITY FUNCTIONS
  // -------------------------------
  public shared(msg) func clearMessages(): async () {
    messageBuffer.clear();
    messages := [];
  };

  public shared(msg) func clearUsers(): async () {
    userBuffer.clear();
    users := [];
  };
};








