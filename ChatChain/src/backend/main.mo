

import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Text "mo:base/Text";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Bool "mo:base/Bool";
import Option "mo:base/Option";
import Buffer "mo:base/Buffer";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";

actor ChatChain {

  // ===========================================================================
  // CONSTANTS & CONFIGURATION
  // ===========================================================================

  let EDIT_WINDOW_SECONDS : Nat = 15 * 60;
  let MAX_MESSAGE_LENGTH : Nat = 500;
  let MAX_DISPLAY_NAME_LENGTH : Nat = 50;
  let RATE_LIMIT_SECONDS : Nat = 3;
  let MAX_MESSAGES_PER_USER_PER_DAY : Nat = 1000;
  let MESSAGE_RETENTION_DAYS : Nat = 90;
  let MAX_REACTIONS_PER_MESSAGE : Nat = 20;

  // ===========================================================================
  // TYPES
  // ===========================================================================

  public type UserRole = { #User; #Moderator; #Admin };
  
  public type UserStatus = {
    #Online;
    #Away;
    #Offline;
    #DoNotDisturb;
  };

  public type User = {
    principal   : Principal;
    displayName : Text;
    role        : UserRole;
    banned      : Bool;
    lastSeen    : Nat;
    status      : UserStatus;
    joined      : Nat;
    messageCount : Nat;
  };

  public type Reaction = {
    reactor : Principal;
    emoji   : Text;
    timestamp : Nat;
  };

  public type Message = {
    id        : Nat;
    sender    : Principal;
    content   : Text;
    timestamp : Nat;
    edited    : Bool;
    deleted   : Bool;
    pinned    : Bool;
    reactions : [Reaction];
    replyTo   : ?Nat;
    threadId  : ?Nat; // For grouping messages in threads
    metadata  : ?Text; // For future extensions (file attachments, links, etc.)
  };

  public type ChatRoom = {
    id : Nat;
    name : Text;
    description : ?Text;
    isPrivate : Bool;
    moderators : [Principal];
    createdBy : Principal;
    createdAt : Nat;
    messageCount : Nat;
  };

  public type Error = {
    #Unauthorized;
    #NotFound;
    #InvalidInput;
    #RateLimited;
    #Banned;
    #NoPermission;
    #AlreadyExists;
  };

  // ===========================================================================
  // STABLE STATE WITH UPGRADE SAFETY
  // ===========================================================================

  stable var users         : [User] = [];
  stable var messages      : [Message] = [];
  stable var chatRooms     : [ChatRoom] = [];
  stable var nextMessageId : Nat = 0;
  stable var nextRoomId    : Nat = 0;
  
  // Using stable arrays for maps with manual serialization
  stable var lastSendMapEntries : [(Principal, Nat)] = [];
  stable var dailyMessageCountEntries : [(Principal, Nat)] = [];
  stable var userRoomMembershipEntries : [(Principal, [Nat])] = [];

  // ===========================================================================
  // IN-MEMORY COLLECTIONS (will be re-initialized on upgrade)
  // ===========================================================================

  private var lastSendMap : HashMap.HashMap<Principal, Nat> = HashMap.HashMap(32, Principal.equal, Principal.hash);
  private var dailyMessageCount : HashMap.HashMap<Principal, Nat> = HashMap.HashMap(32, Principal.equal, Principal.hash);
  private var userRoomMembership : HashMap.HashMap<Principal, Buffer.Buffer<Nat>> = HashMap.HashMap(32, Principal.equal, Principal.hash);

  // ===========================================================================
  // INITIALIZATION
  // ===========================================================================

  system func preupgrade() {
    // Convert HashMaps to stable arrays before upgrade
    lastSendMapEntries := Iter.toArray(lastSendMap.entries());
    dailyMessageCountEntries := Iter.toArray(dailyMessageCount.entries());
    
    // Convert Buffer to array for stable storage
    userRoomMembershipEntries := Iter.toArray(
      userRoomMembership.entries()
      .map(func ((p, b) : (Principal, Buffer.Buffer<Nat>)) : (Principal, [Nat]) {
        (p, Buffer.toArray(b))
      })
    );
  };

  system func postupgrade() {
    // Re-initialize HashMaps from stable arrays after upgrade
    lastSendMap := HashMap.fromIter<Principal, Nat>(
      lastSendMapEntries.vals(),
      lastSendMapEntries.size(),
      Principal.equal,
      Principal.hash
    );
    
    dailyMessageCount := HashMap.fromIter<Principal, Nat>(
      dailyMessageCountEntries.vals(),
      dailyMessageCountEntries.size(),
      Principal.equal,
      Principal.hash
    );
    
    userRoomMembership := HashMap.fromIter<Principal, Buffer.Buffer<Nat>>(
      userRoomMembershipEntries.vals()
      .map(func ((p, arr) : (Principal, [Nat])) : (Principal, Buffer.Buffer<Nat>) {
        (p, Buffer.fromArray<Nat>(arr))
      }),
      userRoomMembershipEntries.size(),
      Principal.equal,
      Principal.hash
    );
  };

  // ===========================================================================
  // PRIVATE HELPERS
  // ===========================================================================

  private func now() : Nat {
    Time.toSeconds(Time.now())
  };

  private func isValidDisplayName(name : Text) : Bool {
    let size = Text.size(name);
    size > 0 and size <= MAX_DISPLAY_NAME_LENGTH
    and not Text.contains(name, #char '@') // Prevent email-like names
    and not Text.contains(name, #char '/') // Prevent path-like names
  };

  private func findUser(p : Principal) : ?User {
    Array.find(users, func(u : User) : Bool { Principal.equal(u.principal, p) })
  };

  private func findMessage(id : Nat) : ?Message {
    Array.find(messages, func(m : Message) : Bool { m.id == id })
  };

  private func findRoom(id : Nat) : ?ChatRoom {
    Array.find(chatRooms, func(r : ChatRoom) : Bool { r.id == id })
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
      case null true; // Unregistered users are considered "banned"
    }
  };

  private func updateUser(p : Principal, update : (User) -> User) : () {
    users := Array.map(users, func(u : User) : User {
      if (Principal.equal(u.principal, p)) {
        update(u)
      } else u
    });
  };

  private func updateLastSeen(p : Principal) : () {
    updateUser(p, func(u) { { u with lastSeen = now() } });
  };

  private func incrementMessageCount(p : Principal) : () {
    updateUser(p, func(u) { 
      { u with 
        messageCount = u.messageCount + 1;
        lastSeen = now();
      }
    });
  };

  private func rateLimited(p : Principal) : Bool {
    let currentTime = now();
    switch (lastSendMap.get(p)) {
      case (?lastTime) {
        if (currentTime - lastTime < RATE_LIMIT_SECONDS) {
          return true;
        };
      };
      case null {};
    };
    
    // Update rate limit tracking
    lastSendMap.put(p, currentTime);
    
    // Check daily message limit
    let dayStart = currentTime - (currentTime % (24 * 60 * 60));
    switch (dailyMessageCount.get(p)) {
      case (?count) {
        if (count >= MAX_MESSAGES_PER_USER_PER_DAY) {
          return true;
        };
        dailyMessageCount.put(p, count + 1);
      };
      case null {
        dailyMessageCount.put(p, 1);
      };
    };
    
    false
  };

  private func cleanOldMessages() : () {
    let cutoff = now() - (MESSAGE_RETENTION_DAYS * 24 * 60 * 60);
    messages := Array.filter(messages, func(m : Message) : Bool {
      m.timestamp >= cutoff or m.pinned
    });
  };

  // ===========================================================================
  // USER MANAGEMENT
  // ===========================================================================

  public shared ({ caller }) func registerUser(
    name : Text
  ) : async Result.Result<Bool, Error> {
    
    if (not isValidDisplayName(name)) {
      return #err(#InvalidInput);
    };
    
    if (findUser(caller) != null) {
      return #err(#AlreadyExists);
    };

    let role = if (users.size() == 0) #Admin else #User;
    let nowTime = now();

    users := Array.append(users, [{
      principal = caller;
      displayName = name;
      role = role;
      banned = false;
      lastSeen = nowTime;
      status = #Online;
      joined = nowTime;
      messageCount = 0;
    }]);

    #ok(true)
  };

  public shared ({ caller }) func updateProfile(
    newName : ?Text,
    newStatus : ?UserStatus
  ) : async Result.Result<Bool, Error> {
    
    switch (findUser(caller)) {
      case null { return #err(#NotFound) };
      case (?user) {
        if (user.banned) { return #err(#Banned) };
        
        let updatedUser = {
          user with
          displayName = switch (newName) {
            case (?name) {
              if (not isValidDisplayName(name)) {
                return #err(#InvalidInput);
              };
              name
            };
            case null user.displayName;
          };
          status = Option.get(newStatus, user.status);
        };
        
        updateUser(caller, func(_) { updatedUser });
        #ok(true)
      };
    }
  };

  public query func getUsers(
    filterOnline : ?Bool,
    filterRole : ?UserRole
  ) : async [User] {
    
    Array.filter(users, func(u : User) : Bool {
      var include = true;
      
      switch (filterOnline) {
        case (?onlineOnly) {
          let isOnline = (now() - u.lastSeen) < 300; // 5 minutes
          include := include and (isOnline == onlineOnly);
        };
        case null {};
      };
      
      switch (filterRole) {
        case (?role) include := include and (u.role == role);
        case null {};
      };
      
      include
    })
  };

  public query func getUserStats(p : Principal) : async ?{
    user : User;
    activeDays : Nat;
    avgMessagesPerDay : Float;
  } {
    switch (findUser(p)) {
      case null null;
      case (?user) {
        let daysActive = Float.fromInt(
          Nat.max(1, (now() - user.joined) / (24 * 60 * 60))
        );
        let avgMessages = Float.fromInt(user.messageCount) / daysActive;
        
        ?{
          user = user;
          activeDays = Int.abs(Float.toInt(daysActive));
          avgMessagesPerDay = avgMessages;
        }
      };
    }
  };

  public shared ({ caller }) func banUser(
    p : Principal,
    reason : ?Text
  ) : async Result.Result<Bool, Error> {
    
    if (not isModOrAdmin(caller)) {
      return #err(#Unauthorized);
    };
    
    if (isAdmin(p) and not isAdmin(caller)) {
      return #err(#NoPermission); // Can't ban admins unless you're admin
    };

    updateUser(p, func(u) { { u with banned = true } });
    #ok(true)
  };

  public shared ({ caller }) func unbanUser(p : Principal) : async Result.Result<Bool, Error> {
    if (not isModOrAdmin(caller)) {
      return #err(#Unauthorized);
    };

    updateUser(p, func(u) { { u with banned = false } });
    #ok(true)
  };

  // ===========================================================================
  // CHAT ROOMS
  // ===========================================================================

  public shared ({ caller }) func createRoom(
    name : Text,
    description : ?Text,
    isPrivate : Bool
  ) : async Result.Result<Nat, Error> {
    
    if (isBanned(caller)) {
      return #err(#Banned);
    };
    
    let id = nextRoomId;
    nextRoomId += 1;

    let room : ChatRoom = {
      id = id;
      name = name;
      description = description;
      isPrivate = isPrivate;
      moderators = if (isPrivate) [caller] else [];
      createdBy = caller;
      createdAt = now();
      messageCount = 0;
    };

    chatRooms := Array.append(chatRooms, [room]);
    
    // Add creator to room membership
    switch (userRoomMembership.get(caller)) {
      case (?buffer) { buffer.add(id) };
      case null {
        let buffer = Buffer.Buffer<Nat>(5);
        buffer.add(id);
        userRoomMembership.put(caller, buffer);
      };
    };

    #ok(id)
  };

  public shared ({ caller }) func joinRoom(roomId : Nat) : async Result.Result<Bool, Error> {
    switch (findRoom(roomId)) {
      case null { return #err(#NotFound) };
      case (?room) {
        if (room.isPrivate) {
          return #err(#NoPermission);
        };
        
        // Add to membership
        switch (userRoomMembership.get(caller)) {
          case (?buffer) {
            if (Buffer.contains(buffer, roomId, Nat.equal)) {
              return #ok(true); // Already a member
            };
            buffer.add(roomId);
          };
          case null {
            let buffer = Buffer.Buffer<Nat>(5);
            buffer.add(roomId);
            userRoomMembership.put(caller, buffer);
          };
        };
        
        #ok(true)
      };
    }
  };

  public query func getRooms(
    showPrivate : Bool,
    filterByMember : ?Principal
  ) : async [ChatRoom] {
    
    Array.filter(chatRooms, func(room : ChatRoom) : Bool {
      var include = true;
      
      if (room.isPrivate and not showPrivate) {
        include := false;
      };
      
      switch (filterByMember) {
        case (?member) {
          switch (userRoomMembership.get(member)) {
            case (?buffer) {
              include := include and Buffer.contains(buffer, room.id, Nat.equal);
            };
            case null include := false;
          };
        };
        case null {};
      };
      
      include
    })
  };

  // ===========================================================================
  // MESSAGES
  // ===========================================================================

  public shared ({ caller }) func sendMessage(
    content : Text,
    replyTo : ?Nat,
    roomId : ?Nat,
    metadata : ?Text
  ) : async Result.Result<Nat, Error> {
    
    if (isBanned(caller)) {
      return #err(#Banned);
    };
    
    if (Text.size(content) == 0 or Text.size(content) > MAX_MESSAGE_LENGTH) {
      return #err(#InvalidInput);
    };
    
    if (rateLimited(caller)) {
      return #err(#RateLimited);
    };
    
    // Check room membership if room is specified
    switch (roomId) {
      case (?rId) {
        switch (userRoomMembership.get(caller)) {
          case (?buffer) {
            if (not Buffer.contains(buffer, rId, Nat.equal)) {
              return #err(#NoPermission);
            };
          };
          case null { return #err(#NoPermission) };
        };
      };
      case null {};
    };

    let id = nextMessageId;
    nextMessageId += 1;

    let message : Message = {
      id = id;
      sender = caller;
      content = content;
      timestamp = now();
      edited = false;
      deleted = false;
      pinned = false;
      reactions = [];
      replyTo = replyTo;
      threadId = null; // Could be derived from replyTo if needed
      metadata = metadata;
    };

    messages := Array.append(messages, [message]);
    
    // Update user stats and room stats
    incrementMessageCount(caller);
    
    switch (roomId) {
      case (?rId) {
        chatRooms := Array.map(chatRooms, func(r : ChatRoom) : ChatRoom {
          if (r.id == rId) {
            { r with messageCount = r.messageCount + 1 }
          } else r
        });
      };
      case null {};
    };
    
    // Clean old messages periodically
    if (id % 100 == 0) {
      cleanOldMessages();
    };

    #ok(id)
  };

  public shared ({ caller }) func editMessage(
    id : Nat,
    newContent : Text
  ) : async Result.Result<Bool, Error> {
    
    if (Text.size(newContent) == 0 or Text.size(newContent) > MAX_MESSAGE_LENGTH) {
      return #err(#InvalidInput);
    };
    
    switch (findMessage(id)) {
      case null { return #err(#NotFound) };
      case (?message) {
        if (message.deleted) {
          return #err(#NotFound);
        };
        
        let canEdit = Principal.equal(message.sender, caller)
          or isModOrAdmin(caller);
        
        if (not canEdit) {
          return #err(#Unauthorized);
        };
        
        // Check edit window (only for non-moderators)
        if (not isModOrAdmin(caller) 
            and (now() - message.timestamp) > EDIT_WINDOW_SECONDS) {
          return #err(#NoPermission);
        };

        messages := Array.map(messages, func(m : Message) : Message {
          if (m.id == id) {
            { m with 
              content = newContent;
              edited = true;
            }
          } else m
        });
        
        #ok(true)
      };
    }
  };

  public shared ({ caller }) func softDeleteMessage(id : Nat) : async Result.Result<Bool, Error> {
    if (not isModOrAdmin(caller)) {
      return #err(#Unauthorized);
    };

    messages := Array.map(messages, func(m : Message) : Message {
      if (m.id == id) {
        { m with deleted = true }
      } else m
    });
    
    #ok(true)
  };

  public shared ({ caller }) func pinMessage(id : Nat) : async Result.Result<Bool, Error> {
    if (not isModOrAdmin(caller)) {
      return #err(#Unauthorized);
    };

    // Unpin all other messages first (single pinned message)
    messages := Array.map(messages, func(m : Message) : Message {
      if (m.id == id) {
        { m with pinned = true }
      } else {
        { m with pinned = false }
      }
    });
    
    #ok(true)
  };

  public query func searchMessages(
    query : Text,
    limit : Nat,
    offset : Nat
  ) : async [Message] {
    
    let lowerQuery = Text.map(query, Prim.charToLower);
    var results = Buffer.Buffer<Message>(limit);
    var count : Nat = 0;
    
    for (msg in messages.vals()) {
      if (not msg.deleted 
          and Text.contains(Text.map(msg.content, Prim.charToLower), #text lowerQuery)) {
        if (count >= offset and results.size() < limit) {
          results.add(msg);
        };
        count += 1;
      };
    };
    
    Buffer.toArray(results)
  };

  public query func getMessagesPage(
    page : Nat,
    size : Nat,
    roomId : ?Nat,
    fromUser : ?Principal
  ) : async [Message] {
    
    var filtered = messages;
    
    // Filter by room if specified
    switch (roomId) {
      case (?rId) {
        // For simplicity, assuming room filtering is done elsewhere
        // In a real implementation, you'd have a roomId field in Message
      };
      case null {};
    };
    
    // Filter by user if specified
    filtered := switch (fromUser) {
      case (?user) {
        Array.filter(filtered, func(m : Message) : Bool {
          Principal.equal(m.sender, user)
        })
      };
      case null filtered;
    };
    
    // Remove deleted messages
    filtered := Array.filter(filtered, func(m : Message) : Bool {
      not m.deleted
    });
    
    // Sort by timestamp (newest first)
    filtered := Array.sort(filtered, func(a : Message, b : Message) : Order.Order {
      if (a.timestamp > b.timestamp) { #greater }
      else if (a.timestamp < b.timestamp) { #less }
      else { #equal }
    });
    
    // Pagination
    let total = filtered.size();
    let start = page * size;
    
    if (start >= total) {
      return [];
    };
    
    let end = Nat.min(start + size, total);
    Array.subArray(filtered, start, end - start)
  };

  public query func getThread(root : Nat) : async [Message] {
    Array.filter(messages, func(m : Message) : Bool {
      m.id == root 
      or (switch (m.replyTo) {
        case (?replyId) replyId == root;
        case null false;
      })
    })
  };

  // ===========================================================================
  // REACTIONS
  // ===========================================================================

  public shared ({ caller }) func toggleReaction(
    messageId : Nat,
    emoji : Text
  ) : async Result.Result<Bool, Error> {
    
    if (Text.size(emoji) > 10) { // Basic validation
      return #err(#InvalidInput);
    };
    
    switch (findMessage(messageId)) {
      case null { return #err(#NotFound) };
      case (?message) {
        if (message.deleted) {
          return #err(#NotFound);
        };

        var found = false;
        var updatedReactions : [Reaction] = [];
        
        // Remove existing reaction from same user with same emoji
        for (reaction in message.reactions.vals()) {
          if (Principal.equal(reaction.reactor, caller) 
              and Text.equal(reaction.emoji, emoji)) {
            found := true;
            // Skip adding this one (remove it)
          } else {
            updatedReactions := Array.append(updatedReactions, [reaction]);
          };
        };
        
        // If not found, add new reaction (with limit check)
        if (not found) {
          if (updatedReactions.size() >= MAX_REACTIONS_PER_MESSAGE) {
            return #err(#InvalidInput);
          };
          
          updatedReactions := Array.append(updatedReactions, [{
            reactor = caller;
            emoji = emoji;
            timestamp = now();
          }]);
        };

        messages := Array.map(messages, func(m : Message) : Message {
          if (m.id == messageId) {
            { m with reactions = updatedReactions }
          } else m
        });
        
        #ok(true)
      };
    }
  };

  public query func getMessageReactions(messageId : Nat) : async ?[Reaction] {
    switch (findMessage(messageId)) {
      case null null;
      case (?message) ?message.reactions;
    }
  };

  // ===========================================================================
  // ADMIN UTILITIES & STATISTICS
  // ===========================================================================

  public shared ({ caller }) func clearMessages(
    olderThanDays : ?Nat
  ) : async Result.Result<Nat, Error> {
    
    if (not isAdmin(caller)) {
      return #err(#Unauthorized);
    };

    let beforeCount = messages.size();
    let cutoff = switch (olderThanDays) {
      case (?days) now() - (days * 24 * 60 * 60);
      case null 0; // Clear all if not specified
    };

    messages := Array.filter(messages, func(m : Message) : Bool {
      m.timestamp >= cutoff and m.pinned // Keep pinned messages
    });
    
    let afterCount = messages.size();
    #ok(beforeCount - afterCount)
  };

  public shared ({ caller }) func promoteUser(
    p : Principal,
    newRole : UserRole
  ) : async Result.Result<Bool, Error> {
    
    if (not isAdmin(caller)) {
      return #err(#Unauthorized);
    };

    updateUser(p, func(u) { { u with role = newRole } });
    #ok(true)
  };

  public query ({ caller }) func whoAmI() : async ?User {
    findUser(caller)
  };

  public query func getStats() : async {
    totalUsers : Nat;
    totalMessages : Nat;
    totalRooms : Nat;
    onlineUsers : Nat;
    dailyActiveUsers : Nat;
    storageUsed : Nat; // Approximate
  } {
    let currentTime = now();
    let dayStart = currentTime - (currentTime % (24 * 60 * 60));
    
    let onlineUsersCount = Array.filter(users, func(u : User) : Bool {
      (currentTime - u.lastSeen) < 300 // 5 minutes
    }).size();
    
    let dailyActiveUsersCount = Array.filter(users, func(u : User) : Bool {
      u.lastSeen >= dayStart
    }).size();
    
    {
      totalUsers = users.size();
      totalMessages = messages.size();
      totalRooms = chatRooms.size();
      onlineUsers = onlineUsersCount;
      dailyActiveUsers = dailyActiveUsersCount;
      storageUsed = (users.size() * 100) + (messages.size() * 200); // Rough estimate
    }
  };

  // ===========================================================================
  // BACKUP & RESTORE (Simplified)
  // ===========================================================================

  public query ({ caller }) func exportData() : async ?{
    users : [User];
    messages : [Message];
    rooms : [ChatRoom];
  } {
    if (not isAdmin(caller)) {
      return null;
    };
    
    ?{
      users = users;
      messages = messages;
      rooms = chatRooms;
    }
  };

  // Version info for upgrade compatibility
  public query func version() : async Text {
    "ChatChain v4.0.0"
  };
}

// ============================================================================
// Result module for better error handling
// ============================================================================

module Result {
  public type Result<Ok, Err> = {
    #ok : Ok;
    #err : Err;
  };
};





