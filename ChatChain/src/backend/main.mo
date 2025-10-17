g, buffers for runtime efficiency.
// =====================================================

// -----------------------------------------------------------
// Importing Core Motoko Base Libraries
// -----------------------------------------------------------
// These provide essential functionality for the actor

import Principal "mo:base/Principal"; // Principal type: unique identity of users and actors
import Time "mo:base/Time";           // Time utilities for timestamps
import Buffer "mo:base/Buffer";       // Dynamic buffer structures
import Text "mo:base/Text";           // Text manipulation utilities
import Array "mo:base/Array";         // Array manipulation utilities (append, filter, size, etc.)

// -----------------------------------------------------------
// Actor Declaration
// -----------------------------------------------------------
// ChatChain acts as our main smart contract
// It handles all chat logic, user management, and message storage

actor ChatChain {

  // ===========================================================
  // TYPE DEFINITIONS
  // ===========================================================

  // -----------------------------------------------------------------
  // Each chat message is represented as a record
  // Contains unique ID, sender, text content, and timestamp
  // -----------------------------------------------------------------
  type Message = {
    id: Nat;               // Unique identifier for the message
    sender: Principal;     // Principal identity of the sender
    content: Text;         // Actual textual content of the message
    timestamp: Time.Time;  // Time when the message was sent
  };

  // ===========================================================
  // STABLE STORAGE VARIABLES (persistent across upgrades)
  // ===========================================================

  // Stores all chat messages permanently
  stable var messages: [Message] = [];

  // Stores all registered users as tuples of (Principal, DisplayName)
  stable var users: [(Principal, Text)] = [];

  // Counter to assign unique IDs to each message
  stable var nextMessageId: Nat = 0;

  // ===========================================================
  // IN-MEMORY BUFFERS (temporary, runtime only)
  // ===========================================================

  // Buffer to hold up to 100 messages before syncing to stable storage
  let messageBuffer = Buffer.Buffer<Message>(100);

  // Buffer to hold up to 100 users before syncing to stable storage
  let userBuffer = Buffer.Buffer<(Principal, Text)>(100);

  // ===========================================================
  // USER REGISTRATION AND MANAGEMENT FUNCTIONS
  // ===========================================================

  // -----------------------------------------------------------------
  // Register a new user with a display name
  // Checks if the user already exists, returns true if successful
  // -----------------------------------------------------------------
  public shared(msg) func registerUser(displayName: Text): async Bool {
    let caller = msg.caller;

    // Loop through buffer to check if user already exists
    for ((existingPrincipal, _) in userBuffer.toArray().vals()) {
      if (Principal.equal(existingPrincipal, caller)) {
        return false; // User is already registered
      }
    };

    // Add the new user to the buffer
    userBuffer.add((caller, displayName));

    // Sync buffer to stable storage
    users := userBuffer.toArray();

    return true;
  };

  // -----------------------------------------------------------------
  // Retrieve the list of all registered users
  // Returns an array of tuples (Principal, DisplayName)
  // -----------------------------------------------------------------
  public query func getUsers(): async [(Principal, Text)] {
    userBuffer.toArray()
  };

  // -----------------------------------------------------------------
  // Update the caller’s display name
  // Only the user themselves can update their name
  // Returns true if update was successful
  // -----------------------------------------------------------------
  public shared(msg) func updateUserName(newDisplayName: Text): async Bool {
    let caller = msg.caller;
    var updatedSuccessfully: Bool = false;
    var temporaryUserList: [(Principal, Text)] = [];

    // Rebuild user list with updated name for caller
    for ((p, n) in userBuffer.toArray().vals()) {
      if (Principal.equal(p, caller)) {
        temporaryUserList := Array.append(temporaryUserList, [(p, newDisplayName)]);
        updatedSuccessfully := true;
      } else {
        temporaryUserList := Array.append(temporaryUserList, [(p, n)]);
      }
    };

    // If user was found, update buffer and stable storage
    if (updatedSuccessfully) {
      userBuffer.clear();
      for (u in temporaryUserList.vals()) {
        userBuffer.add(u);
      };
      users := userBuffer.toArray();
    };

    return updatedSuccessfully;
  };

  // -----------------------------------------------------------------
  // Delete the caller from the user list
  // Only the user themselves can delete their account
  // Returns true if deletion occurred
  // -----------------------------------------------------------------
  public shared(msg) func deleteUser(): async Bool {
    let caller = msg.caller;
    var temporaryUserList: [(Principal, Text)] = [];
    var userDeleted: Bool = false;

    // Loop through users, keep all except the caller
    for ((p, n) in userBuffer.toArray().vals()) {
      if (Principal.equal(p, caller)) {
        userDeleted := true;
      } else {
        temporaryUserList := Array.append(temporaryUserList, [(p, n)]);
      }
    };

    // Update buffer and storage if deletion occurred
    if (userDeleted) {
      userBuffer.clear();
      for (u in temporaryUserList.vals()) {
        userBuffer.add(u);
      };
      users := userBuffer.toArray();
    };

    return userDeleted;
  };

  // ===========================================================
  // MESSAGE SENDING AND RETRIEVAL FUNCTIONS
  // ===========================================================

  // -----------------------------------------------------------------
  // Send a new message
  // Returns the assigned unique message ID
  // -----------------------------------------------------------------
  public shared(msg) func sendMessage(content: Text): async Nat {
    let newMessage: Message = {
      id = nextMessageId;
      sender = msg.caller;
      content = content;
      timestamp = Time.now();
    };

    // Increment message ID for the next message
    nextMessageId += 1;

    // Add message to buffer
    messageBuffer.add(newMessage);

    // Sync buffer to stable storage
    messages := messageBuffer.toArray();

    return newMessage.id;
  };

  // -----------------------------------------------------------------
  // Retrieve all messages
  // Returns an array of Message records
  // -----------------------------------------------------------------
  public query func getMessages(): async [Message] {
    messages
  };

  // -----------------------------------------------------------------
  // Retrieve all messages sent since a specific timestamp
  // Useful for fetching only new messages
  // -----------------------------------------------------------------
  public query func getMessagesSince(timestamp: Time.Time): async [Message] {
    Array.filter(messages, func(m: Message): Bool { m.timestamp >= timestamp })
  };

  // -----------------------------------------------------------------
  // Edit a message (only the sender can edit)
  // Returns true if message was successfully updated
  // -----------------------------------------------------------------
  public shared(msg) func editMessage(messageId: Nat, newContent: Text): async Bool {
    let caller = msg.caller;
    var messageUpdated: Bool = false;
    var tempMessageList: [Message] = [];

    // Rebuild message list with updated content
    for (m in messages.vals()) {
      if (m.id == messageId and Principal.equal(m.sender, caller)) {
        tempMessageList := Array.append(tempMessageList, [{ m with content = newContent }]);
        messageUpdated := true;
      } else {
        tempMessageList := Array.append(tempMessageList, [m]);
      }
    };

    // Update buffer and stable storage if updated
    if (messageUpdated) {
      messageBuffer.clear();
      for (m in tempMessageList.vals()) {
        messageBuffer.add(m);
      };
      messages := messageBuffer.toArray();
    };

    return messageUpdated;
  };

  // -----------------------------------------------------------------
  // Delete a message (only the sender can delete)
  // Returns true if deletion was successful
  // -----------------------------------------------------------------
  public shared(msg) func deleteMessage(messageId: Nat): async Bool {
    let caller = msg.caller;
    var temporaryMessages: [Message] = [];
    var messageDeleted: Bool = false;

    for (m in messages.vals()) {
      if (m.id == messageId and Principal.equal(m.sender, caller)) {
        messageDeleted := true;
      } else {
        temporaryMessages := Array.append(temporaryMessages, [m]);
      }
    };

    // Update buffer and storage if deletion occurred
    if (messageDeleted) {
      messageBuffer.clear();
      for (m in temporaryMessages.vals()) {
        messageBuffer.add(m);
      };
      messages := messageBuffer.toArray();
    };

    return messageDeleted;
  };

  // -----------------------------------------------------------------
  // Search messages containing a specific keyword
  // Returns an array of matching messages
  // -----------------------------------------------------------------
  public query func searchMessages(keyword: Text): async [Message] {
    Array.filter(messages, func(m: Message): Bool { Text.contains(m.content, keyword) })
  };

  // -----------------------------------------------------------------
  // Get the total number of messages
  // -----------------------------------------------------------------
  public query func messageCount(): async Nat {
    Array.size(messages)
  };

  // -----------------------------------------------------------------
  // Get the number of messages sent by a specific user
  // -----------------------------------------------------------------
  public query func userMessageCount(user: Principal): async Nat {
    Array.size(Array.filter(messages, func(m: Message): Bool { Principal.equal(m.sender, user) }))
  };

  // ===========================================================
  // ADMIN / UTILITY FUNCTIONS
  // ===========================================================

  // -----------------------------------------------------------------
  // Clear all messages (admin utility)
  // -----------------------------------------------------------------
  public shared(msg) func clearMessages(): async () {
    messageBuffer.clear();
    messages := [];
  };

  // -----------------------------------------------------------------
  // Clear all users (admin utility)
  // -----------------------------------------------------------------
  public shared(msg) func clearUsers(): async () {
    userBuffer.clear();
    users := [];
  };
};









