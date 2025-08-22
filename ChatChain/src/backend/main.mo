
ase/Buffer";       // Provides dynamic buffer structure for temporary storage
import Text "mo:base/Text";           // Provides Text utilities (strings, searching, etc.)
import Array "mo:base/Array";         // Provides Array utilities (filter, append, size, etc.)

// -----------------------------------------------------------
// Actor Declaration
// -----------------------------------------------------------
// ChatChain is our main actor (like a smart contract)
// It will handle users, messages, and provide query + update methods
actor ChatChain {

  // ===========================================================
  // TYPE DEFINITIONS
  // ===========================================================

  // Each message in the chat is represented by this record type
  type Message = {
    id: Nat;               // Unique numeric ID for message
    sender: Principal;     // The principal (unique identity) of the sender
    content: Text;         // The actual text content of the message
    timestamp: Time.Time;  // The system time at which the message was sent
  };

  // ===========================================================
  // STABLE STORAGE VARIABLES (persist across upgrades)
  // ===========================================================
  stable var messages: [Message] = [];               // Stores all chat messages
  stable var users: [(Principal, Text)] = [];        // Stores registered users as (Principal, DisplayName)
  stable var nextMessageId: Nat = 0;                 // Counter for assigning unique IDs to messages

  // ===========================================================
  // IN-MEMORY BUFFERS (temporary during runtime, not upgrade-safe)
  // ===========================================================
  let messageBuffer = Buffer.Buffer<Message>(100);   // Holds up to 100 messages before syncing to stable array
  let userBuffer = Buffer.Buffer<(Principal, Text)>(100); // Holds up to 100 users before syncing to stable array

  // ===========================================================
  // USER REGISTRATION AND MANAGEMENT FUNCTIONS
  // ===========================================================

  // Function to register a new user
  // Each user is uniquely identified by their Principal (msg.caller)
  // Returns `true` if registration is successful, `false` if user already exists
  public shared(msg) func registerUser(name: Text): async Bool {
    let caller = msg.caller;

    // Check if user already exists in buffer
    for ((principal, _) in userBuffer.toArray().vals()) {
      if (Principal.equal(principal, caller)) {
        return false; // user already registered
      }
    };

    // Add new user to buffer
    userBuffer.add((caller, name));

    // Sync buffer to stable storage
    users := userBuffer.toArray();

    return true;
  };

  // Function to get all users
  public query func getUsers(): async [(Principal, Text)] {
    userBuffer.toArray()
  };

  // Function to update a user’s display name
  // Only the caller can update their own name
  public shared(msg) func updateUserName(newName: Text): async Bool {
    let caller = msg.caller;
    var found: Bool = false;
    var tempUsers: [(Principal, Text)] = [];

    // Rebuild the user list with updated name
    for ((p, n) in userBuffer.toArray().vals()) {
      if (Principal.equal(p, caller)) {
        tempUsers := Array.append(tempUsers, [(p, newName)]);
        found := true;
      } else {
        tempUsers := Array.append(tempUsers, [(p, n)]);
      }
    };

    // Update buffers if user was found
    if (found) {
      userBuffer.clear();
      for (u in tempUsers.vals()) {
        userBuffer.add(u);
      };
      users := userBuffer.toArray();
    };

    return found;
  };

  // Function to delete a user
  // Only the caller can delete themselves
  public shared(msg) func deleteUser(): async Bool {
    let caller = msg.caller;
    var tempUsers: [(Principal, Text)] = [];
    var found: Bool = false;

    for ((p, n) in userBuffer.toArray().vals()) {
      if (Principal.equal(p, caller)) {
        found := true;
      } else {
        tempUsers := Array.append(tempUsers, [(p, n)]);
      }
    };

    // Update storage if deletion occurred
    if (found) {
      userBuffer.clear();
      for (u in tempUsers.vals()) {
        userBuffer.add(u);
      };
      users := userBuffer.toArray();
    };

    return found;
  };

  // ===========================================================
  // MESSAGE SENDING AND RETRIEVAL FUNCTIONS
  // ===========================================================

  // Function to send a message
  // Returns the message ID assigned to this message
  public shared(msg) func sendMessage(content: Text): async Nat {
    let newMessage: Message = {
      id = nextMessageId;
      sender = msg.caller;
      content = content;
      timestamp = Time.now();
    };

    // Increment ID counter for next message
    nextMessageId += 1;

    // Add message to buffer and sync to stable storage
    messageBuffer.add(newMessage);
    messages := messageBuffer.toArray();

    return newMessage.id;
  };

  // Function to retrieve all messages
  public query func getMessages(): async [Message] {
    messages
  };

  // Function to retrieve all messages since a given timestamp
  public query func getMessagesSince(timestamp: Time.Time): async [Message] {
    Array.filter(
      messages,
      func(msg: Message): Bool { msg.timestamp >= timestamp }
    )
  };

  // Function to edit a message (only sender can edit their message)
  public shared(msg) func editMessage(messageId: Nat, newContent: Text): async Bool {
    let caller = msg.caller;
    var updated: Bool = false;
    var tempMessages: [Message] = [];

    // Rebuild message array with updated content
    for (m in messages.vals()) {
      if (m.id == messageId and Principal.equal(m.sender, caller)) {
        tempMessages := Array.append(tempMessages, [{ m with content = newContent }]);
        updated := true;
      } else {
        tempMessages := Array.append(tempMessages, [m]);
      }
    };

    // If message was updated, sync back to buffers
    if (updated) {
      messageBuffer.clear();
      for (m in tempMessages.vals()) {
        messageBuffer.add(m);
      };
      messages := messageBuffer.toArray();
    };

    return updated;
  };

  // Function to delete a message (only sender can delete)
  public shared(msg) func deleteMessage(messageId: Nat): async Bool {
    let caller = msg.caller;
    var tempMessages: [Message] = [];
    var deleted: Bool = false;

    // Filter out the message to delete
    for (m in messages.vals()) {
      if (m.id == messageId and Principal.equal(m.sender, caller)) {
        deleted := true;
      } else {
        tempMessages := Array.append(tempMessages, [m]);
      }
    };

    // Update buffers if deletion occurred
    if (deleted) {
      messageBuffer.clear();
      for (m in tempMessages.vals()) {
        messageBuffer.add(m);
      };
      messages := messageBuffer.toArray();
    };

    return deleted;
  };

  // Function to search for messages containing a keyword
  public query func searchMessages(keyword: Text): async [Message] {
    Array.filter(messages, func(m: Message): Bool {
      Text.contains(m.content, keyword)
    })
  };

  // Function to get total number of messages
  public query func messageCount(): async Nat {
    Array.size(messages)
  };

  // Function to get the number of messages sent by a particular user
  public query func userMessageCount(user: Principal): async Nat {
    Array.size(
      Array.filter(messages, func(m: Message): Bool {
        Principal.equal(m.sender, user)
      })
    )
  };

  // ===========================================================
  // ADMIN / UTILITY FUNCTIONS
  // ===========================================================

  // Function to clear all messages (Admin utility)
  public shared(msg) func clearMessages(): async () {
    messageBuffer.clear();
    messages := [];
  };

  // Function to clear all users (Admin utility)
  public shared(msg) func clearUsers(): async () {
    userBuffer.clear();
    users := [];
  };
};
















