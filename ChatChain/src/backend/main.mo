

import Text "mo:base/Text";
import Array "mo:base/Array";

actor ChatChain {
  // Define a message type
  type Message = {
    sender: Principal;
    content: Text;
    timestamp: Time.Time;
  };

  // Stable storage for messages
  stable var messages: [Message] = [];
  let messageBuffer = Buffer.Buffer<Message>(100);

  // Stable storage for users
  stable var users: [(Principal, Text)] = [];
  let userBuffer = Buffer.Buffer<(Principal, Text)>(100);

  // Register a user with a name
  public shared(msg) func registerUser(name: Text) : async Bool {
    let caller = msg.caller;
    // Check if user already exists
    for ((principal, _) in userBuffer.toArray().vals()) {
      if (Principal.equal(principal, caller)) {
        return false; // User already registered
      }
    };
    userBuffer.add((caller, name));
    users := userBuffer.toArray();
    true
  };

  // Get all registered users
  public query func getUsers() : async [(Principal, Text)] {
    userBuffer.toArray()
  };

  // Send a message
  public shared(msg) func sendMessage(content: Text) : async () {
    let message: Message = {
      sender = msg.caller;
      content = content;
      timestamp = Time.now();
    };
    messageBuffer.add(message);
    messages := messageBuffer.toArray();
  };

  // Get all messages
  public query func getMessages() : async [Message] {
    messages
  };

  // Get messages since a given timestamp
  public query func getMessagesSince(timestamp: Time.Time) : async [Message] {
    Array.filter(messages, func (msg: Message) : Bool { msg.timestamp >= timestamp })
  };

  // Clear messages (for testing, optional)
  public func clearMessages() : async () {
    messageBuffer.clear();
    messages := [];
  };

};




