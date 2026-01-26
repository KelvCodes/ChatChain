
  let MAX_MESSAGES_PER_USER_PER_DAY : Nat = 5000;
  let MESSAGE_RETENTION_DAYS : Nat = 365;
  let MAX_REACTIONS_PER_MESSAGE : Nat = 50;
  let MAX_PINNED_MESSAGES : Nat = 10;
  let MAX_UPLOAD_SIZE_BYTES : Nat = 10_000_000; // 10MB
  let MAX_USER_BLOCKLIST_SIZE : Nat = 1000;
  let TYPING_INDICATOR_TIMEOUT : Nat = 10; // seconds

  // ===========================================================================
  // TYPES
  // ===========================================================================

  public type UserRole = { 
    #User; 
    #Moderator; 
    #Admin; 
    #Owner 
  };
  
  public type UserStatus = {
    #Online;
    #Away;
    #Offline;
    #DoNotDisturb;
    #Invisible;
  };

  public type UserPreferences = {
    theme : Text;
    notifications : Bool;
    language : Text;
    autoDeleteDMs : Bool;
    showReadReceipts : Bool;
  };

  public type User = {
    id : Principal;
    displayName : Text;
    username : Text;
    bio : ?Text;
    avatar : ?Text; // URL or hash
    role : UserRole;
    banned : Bool;
    bannedUntil : ?Nat;
    lastSeen : Nat;
    status : UserStatus;
    joined : Nat;
    messageCount : Nat;
    reputation : Int;
    preferences : UserPreferences;
    isVerified : Bool;
  };

  public type Reaction = {
    reactor : Principal;
    emoji : Text;
    timestamp : Nat;
  };

  public type Attachment = {
    id : Text;
    name : Text;
    type : Text; // MIME type
    size : Nat;
    hash : Text;
    uploadedBy : Principal;
    timestamp : Nat;
  };

  public type MessageType = {
    #Text;
    #Image;
    #File;
    #Voice;
    #System;
    #Poll;
  };

  public type PollOption = {
    id : Nat;
    text : Text;
    votes : [Principal];
  };

  public type Poll = {
    question : Text;
    options : [PollOption];
    multipleChoice : Bool;
    endsAt : ?Nat;
    voters : [Principal];
  };

  public type Message = {
    id : Nat;
    sender : Principal;
    content : Text;
    timestamp : Nat;
    edited : Bool;
    deleted : Bool;
    pinned : Bool;
    reactions : [Reaction];
    replyTo : ?Nat;
    threadId : ?Nat;
    roomId : Nat;
    mentions : [Principal];
    attachments : [Attachment];
    messageType : MessageType;
    poll : ?Poll;
    metadata : ?Blob;
    encryptionKey : ?Text; // For E2E encryption
  };

  public type ChatRoomType = {
    #Public;
    #Private;
    #DirectMessage;
    #Group;
    #Channel;
  };

  public type ChatRoom = {
    id : Nat;
    name : Text;
    description : ?Text;
    roomType : ChatRoomType;
    moderators : [Principal];
    createdBy : Principal;
    createdAt : Nat;
    messageCount : Nat;
    isArchived : Bool;
    lastActivity : Nat;
    icon : ?Text;
    rules : ?Text;
    maxMembers : ?Nat;
  };

  public type Notification = {
    id : Nat;
    userId : Principal;
    type : {
      #Mention;
      #Reply;
      #Reaction;
      #Invite;
      #System;
    };
    messageId : ?Nat;
    roomId : ?Nat;
    fromUser : ?Principal;
    content : Text;
    timestamp : Nat;
    read : Bool;
  };

  public type TypingIndicator = {
    userId : Principal;
    roomId : Nat;
    timestamp : Nat;
  };

  public type Error = {
    #Unauthorized;
    #NotFound;
    #InvalidInput;
    #RateLimited;
    #Banned;
    #NoPermission;
    #AlreadyExists;
    #RoomFull;
    #StorageLimitExceeded;
    #UserBlocked;
    #MessageTooLong;
    #InvalidAttachment;
    #PollEnded;
    #DuplicateVote;
    #EncryptionError;
  };

  public type Result<T, E> = Result.Result<T, E>;

  // ===========================================================================
  // STABLE STATE
  // ===========================================================================

  stable var users : [User] = [];
  stable var messages : [Message] = [];
  stable var chatRooms : [ChatRoom] = [];
  stable var notifications : [Notification] = [];
  stable var attachments : [Attachment] = [];
  stable var nextMessageId : Nat = 0;
  stable var nextRoomId : Nat = 0;
  stable var nextNotificationId : Nat = 0;
  stable var nextAttachmentId : Nat = 0;
  
  // Stable maps
  stable var lastSendMapEntries : [(Principal, Nat)] = [];
  stable var dailyMessageCountEntries : [(Principal, Nat)] = [];
  stable var userRoomMembershipEntries : [(Principal, [Nat])] = [];
  stable var userBlocklistEntries : [(Principal, [Principal])] = [];
  stable var typingIndicatorsEntries : [(Nat, [TypingIndicator])] = [];
  stable var readReceiptsEntries : [(Nat, [(Principal, Nat)])] = [];
  stable var pollVotesEntries : [(Nat, [Principal])] = [];
  stable var roomInvitesEntries : [(Nat, [Principal])] = [];

  // ===========================================================================
  // IN-MEMORY COLLECTIONS
  // ===========================================================================

  private var lastSendMap = HashMap.HashMap<Principal, Nat>(32, Principal.equal, Principal.hash);
  private var dailyMessageCount = HashMap.HashMap<Principal, Nat>(32, Principal.equal, Principal.hash);
  private var userRoomMembership = HashMap.HashMap<Principal, Buffer.Buffer<Nat>>(32, Principal.equal, Principal.hash);
  private var userBlocklist = HashMap.HashMap<Principal, Buffer.Buffer<Principal>>(32, Principal.equal, Principal.hash);
  private var typingIndicators = HashMap.HashMap<Nat, Buffer.Buffer<TypingIndicator>>(32, Nat.equal, Hash.hash);
  private var readReceipts = HashMap.HashMap<Nat, HashMap.HashMap<Principal, Nat>>(32, Nat.equal, Hash.hash);
  private var pollVotes = HashMap.HashMap<Nat, Buffer.Buffer<Principal>>(32, Nat.equal, Hash.hash);
  private var roomInvites = HashMap.HashMap<Nat, Buffer.Buffer<Principal>>(32, Nat.equal, Hash.hash);
  
  // Quick lookup indexes
  private var userByUsername = TrieMap.TrieMap<Text, Principal>(Text.equal, Text.hash);
  private var messagesByRoom = TrieMap.TrieMap<Nat, Buffer.Buffer<Nat>>(Nat.equal, Hash.hash);
  private var pinnedMessagesByRoom = TrieMap.TrieMap<Nat, Buffer.Buffer<Nat>>(Nat.equal, Hash.hash);

  // ===========================================================================
  // INITIALIZATION & UPGRADE
  // ===========================================================================

  system func preupgrade() {
    // Convert HashMaps to stable arrays
    lastSendMapEntries := Iter.toArray(lastSendMap.entries());
    dailyMessageCountEntries := Iter.toArray(dailyMessageCount.entries());
    
    userRoomMembershipEntries := Iter.toArray(
      userRoomMembership.entries()
      .map(func ((p, b) : (Principal, Buffer.Buffer<Nat>)) : (Principal, [Nat]) {
        (p, Buffer.toArray(b))
      })
    );
    
    userBlocklistEntries := Iter.toArray(
      userBlocklist.entries()
      .map(func ((p, b) : (Principal, Buffer.Buffer<Principal>)) : (Principal, [Principal]) {
        (p, Buffer.toArray(b))
      })
    );
    
    typingIndicatorsEntries := Iter.toArray(
      typingIndicators.entries()
      .map(func ((roomId, b) : (Nat, Buffer.Buffer<TypingIndicator>)) : (Nat, [TypingIndicator]) {
        (roomId, Buffer.toArray(b))
      })
    );
    
    readReceiptsEntries := Iter.toArray(
      readReceipts.entries()
      .map(func ((msgId, map) : (Nat, HashMap.HashMap<Principal, Nat>)) : (Nat, [(Principal, Nat)]) {
        (msgId, Iter.toArray(map.entries()))
      })
    );
    
    pollVotesEntries := Iter.toArray(
      pollVotes.entries()
      .map(func ((pollId, b) : (Nat, Buffer.Buffer<Principal>)) : (Nat, [Principal]) {
        (pollId, Buffer.toArray(b))
      })
    );
    
    roomInvitesEntries := Iter.toArray(
      roomInvites.entries()
      .map(func ((roomId, b) : (Nat, Buffer.Buffer<Principal>)) : (Nat, [Principal]) {
        (roomId, Buffer.toArray(b))
      })
    );
  };

  system func postupgrade() {
    // Reinitialize HashMaps
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
    
    userBlocklist := HashMap.fromIter<Principal, Buffer.Buffer<Principal>>(
      userBlocklistEntries.vals()
      .map(func ((p, arr) : (Principal, [Principal])) : (Principal, Buffer.Buffer<Principal>) {
        (p, Buffer.fromArray<Principal>(arr))
      }),
      userBlocklistEntries.size(),
      Principal.equal,
      Principal.hash
    );
    
    typingIndicators := HashMap.fromIter<Nat, Buffer.Buffer<TypingIndicator>>(
      typingIndicatorsEntries.vals()
      .map(func ((roomId, arr) : (Nat, [TypingIndicator])) : (Nat, Buffer.Buffer<TypingIndicator>) {
        (roomId, Buffer.fromArray<TypingIndicator>(arr))
      }),
      typingIndicatorsEntries.size(),
      Nat.equal,
      Hash.hash
    );
    
    readReceipts := HashMap.fromIter<Nat, HashMap.HashMap<Principal, Nat>>(
      readReceiptsEntries.vals()
      .map(func ((msgId, entries) : (Nat, [(Principal, Nat)])) : (Nat, HashMap.HashMap<Principal, Nat>) {
        let map = HashMap.HashMap<Principal, Nat>(16, Principal.equal, Principal.hash);
        for ((p, t) in entries.vals()) {
          map.put(p, t);
        };
        (msgId, map)
      }),
      readReceiptsEntries.size(),
      Nat.equal,
      Hash.hash
    );
    
    pollVotes := HashMap.fromIter<Nat, Buffer.Buffer<Principal>>(
      pollVotesEntries.vals()
      .map(func ((pollId, arr) : (Nat, [Principal])) : (Nat, Buffer.Buffer<Principal>) {
        (pollId, Buffer.fromArray<Principal>(arr))
      }),
      pollVotesEntries.size(),
      Nat.equal,
      Hash.hash
    );
    
    roomInvites := HashMap.fromIter<Nat, Buffer.Buffer<Principal>>(
      roomInvitesEntries.vals()
      .map(func ((roomId, arr) : (Nat, [Principal])) : (Nat, Buffer.Buffer<Principal>) {
        (roomId, Buffer.fromArray<Principal>(arr))
      }),
      roomInvitesEntries.size(),
      Nat.equal,
      Hash.hash
    );
    
    // Rebuild indexes
    rebuildIndexes();
  };

  private func rebuildIndexes() {
    userByUsername := TrieMap.TrieMap<Text, Principal>(Text.equal, Text.hash);
    for (user in users.vals()) {
      userByUsername.put(user.username, user.id);
    };
    
    messagesByRoom := TrieMap.TrieMap<Nat, Buffer.Buffer<Nat>>(Nat.equal, Hash.hash);
    pinnedMessagesByRoom := TrieMap.TrieMap<Nat, Buffer.Buffer<Nat>>(Nat.equal, Hash.hash);
    
    for (msg in messages.vals()) {
      // Index by room
      switch (messagesByRoom.get(msg.roomId)) {
        case (?buffer) buffer.add(msg.id);
        case null {
          let buffer = Buffer.Buffer<Nat>(100);
          buffer.add(msg.id);
          messagesByRoom.put(msg.roomId, buffer);
        };
      };
      
      // Index pinned messages
      if (msg.pinned) {
        switch (pinnedMessagesByRoom.get(msg.roomId)) {
          case (?buffer) buffer.add(msg.id);
          case null {
            let buffer = Buffer.Buffer<Nat>(10);
            buffer.add(msg.id);
            pinnedMessagesByRoom.put(msg.roomId, buffer);
          };
        };
      };
    };
  };

  // ===========================================================================
  // PRIVATE HELPERS
  // ===========================================================================

  private func now() : Nat {
    Time.toSeconds(Time.now())
  };

  private func isValidUsername(username : Text) : Bool {
    let size = Text.size(username);
    size >= 3 and size <= 30
    and Text.matches(username, #regex "^[a-zA-Z0-9_]+$")
  };

  private func isValidDisplayName(name : Text) : Bool {
    let size = Text.size(name);
    size > 0 and size <= MAX_DISPLAY_NAME_LENGTH
    and not Text.contains(name, #char '@')
    and not Text.contains(name, #char '/')
  };

  private func findUser(p : Principal) : ?User {
    Array.find(users, func(u : User) : Bool { Principal.equal(u.id, p) })
  };

  private func findUserByUsername(username : Text) : ?User {
    switch (userByUsername.get(username)) {
      case (?p) findUser(p);
      case null null;
    }
  };

  private func findMessage(id : Nat) : ?Message {
    Array.find(messages, func(m : Message) : Bool { m.id == id })
  };

  private func findRoom(id : Nat) : ?ChatRoom {
    Array.find(chatRooms, func(r : ChatRoom) : Bool { r.id == id })
  };

  private func isAdmin(p : Principal) : Bool {
    switch (findUser(p)) {
      case (?u) { u.role == #Admin or u.role == #Owner };
      case null false;
    }
  };

  private func isModOrAdmin(p : Principal) : Bool {
    switch (findUser(p)) {
      case (?u) { u.role == #Admin or u.role == #Moderator or u.role == #Owner };
      case null false;
    }
  };

  private func isBanned(p : Principal) : Bool {
    switch (findUser(p)) {
      case (?u) {
        switch (u.bannedUntil) {
          case (?until) {
            u.banned and until > now()
          };
          case null u.banned;
        }
      };
      case null true;
    }
  };

  private func updateUser(p : Principal, update : (User) -> User) : () {
    users := Array.map(users, func(u : User) : User {
      if (Principal.equal(u.id, p)) {
        let updated = update(u);
        // Update username index
        if (u.username != updated.username) {
          userByUsername.delete(u.username);
          userByUsername.put(updated.username, updated.id);
        };
        updated
      } else u
    });
  };

  private func incrementReputation(p : Principal, amount : Int) : () {
    updateUser(p, func(u) { 
      { u with reputation = u.reputation + amount }
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

  private func extractMentions(text : Text) : [Principal] {
    let words = Text.split(text, #char ' ');
    let mentions = Buffer.Buffer<Principal>(10);
    
    for (word in words) {
      if (Text.startsWith(word, #text "@")) {
        let username = Text.trimStart(word, #char '@');
        switch (findUserByUsername(username)) {
          case (?user) mentions.add(user.id);
          case null {};
        };
      };
    };
    
    Buffer.toArray(mentions)
  };

  private func createNotification(
    userId : Principal,
    type : {
      #Mention;
      #Reply;
      #Reaction;
      #Invite;
      #System;
    },
    messageId : ?Nat,
    roomId : ?Nat,
    fromUser : ?Principal,
    content : Text
  ) : Nat {
    let id = nextNotificationId;
    nextNotificationId += 1;
    
    let notification : Notification = {
      id = id;
      userId = userId;
      type = type;
      messageId = messageId;
      roomId = roomId;
      fromUser = fromUser;
      content = content;
      timestamp = now();
      read = false;
    };
    
    notifications := Array.append(notifications, [notification]);
    id
  };

  // ===========================================================================
  // USER MANAGEMENT (Enhanced)
  // ===========================================================================

  public shared ({ caller }) func registerUser(
    username : Text,
    displayName : Text,
    bio : ?Text
  ) : async Result<Bool, Error> {
    
    if (not isValidUsername(username)) {
      return #err(#InvalidInput);
    };
    
    if (not isValidDisplayName(displayName)) {
      return #err(#InvalidInput);
    };
    
    if (findUser(caller) != null) {
      return #err(#AlreadyExists);
    };
    
    if (findUserByUsername(username) != null) {
      return #err(#AlreadyExists);
    };

    let role = if (users.size() == 0) #Owner else #User;
    let nowTime = now();

    let user : User = {
      id = caller;
      displayName = displayName;
      username = username;
      bio = bio;
      avatar = null;
      role = role;
      banned = false;
      bannedUntil = null;
      lastSeen = nowTime;
      status = #Online;
      joined = nowTime;
      messageCount = 0;
      reputation = 0;
      preferences = {
        theme = "dark";
        notifications = true;
        language = "en";
        autoDeleteDMs = false;
        showReadReceipts = true;
      };
      isVerified = false;
    };

    users := Array.append(users, [user]);
    userByUsername.put(username, caller);
    
    #ok(true)
  };

  public shared ({ caller }) func updateProfile(
    newDisplayName : ?Text,
    newUsername : ?Text,
    newBio : ?Text,
    newAvatar : ?Text,
    newStatus : ?UserStatus,
    newPreferences : ?UserPreferences
  ) : async Result<Bool, Error> {
    
    switch (findUser(caller)) {
      case null { return #err(#NotFound) };
      case (?user) {
        if (isBanned(caller)) { return #err(#Banned) };
        
        let finalUsername = switch (newUsername) {
          case (?username) {
            if (not isValidUsername(username)) {
              return #err(#InvalidInput);
            };
            if (username != user.username and findUserByUsername(username) != null) {
              return #err(#AlreadyExists);
            };
            username
          };
          case null user.username;
        };
        
        let finalDisplayName = switch (newDisplayName) {
          case (?name) {
            if (not isValidDisplayName(name)) {
              return #err(#InvalidInput);
            };
            name
          };
          case null user.displayName;
        };

        let updatedUser = {
          user with
          displayName = finalDisplayName;
          username = finalUsername;
          bio = Option.get(newBio, user.bio);
          avatar = Option.get(newAvatar, user.avatar);
          status = Option.get(newStatus, user.status);
          preferences = Option.get(newPreferences, user.preferences);
        };
        
        updateUser(caller, func(_) { updatedUser });
        #ok(true)
      };
    }
  };

  public query func searchUsers(
    query : Text,
    limit : Nat,
    offset : Nat
  ) : async [User] {
    
    let lowerQuery = Text.map(query, Prim.charToLower);
    var results = Buffer.Buffer<User>(limit);
    var count : Nat = 0;
    
    for (user in users.vals()) {
      if (Text.contains(Text.map(user.username, Prim.charToLower), #text lowerQuery)
          or Text.contains(Text.map(user.displayName, Prim.charToLower), #text lowerQuery)) {
        if (count >= offset and results.size() < limit) {
          results.add(user);
        };
        count += 1;
      };
    };
    
    Buffer.toArray(results)
  };

  public shared ({ caller }) func blockUser(
    userToBlock : Principal
  ) : async Result<Bool, Error> {
    
    if (Principal.equal(caller, userToBlock)) {
      return #err(#InvalidInput);
    };
    
    switch (userBlocklist.get(caller)) {
      case (?buffer) {
        if (Buffer.contains(buffer, userToBlock, Principal.equal)) {
          return #ok(true); // Already blocked
        };
        if (buffer.size() >= MAX_USER_BLOCKLIST_SIZE) {
          return #err(#InvalidInput);
        };
        buffer.add(userToBlock);
      };
      case null {
        let buffer = Buffer.Buffer<Principal>(10);
        buffer.add(userToBlock);
        userBlocklist.put(caller, buffer);
      };
    };
    
    #ok(true)
  };

  public shared ({ caller }) func unblockUser(
    userToUnblock : Principal
  ) : async Result<Bool, Error> {
    
    switch (userBlocklist.get(caller)) {
      case (?buffer) {
        var found = false;
        let newBuffer = Buffer.Buffer<Principal>(buffer.size());
        
        for (user in buffer.vals()) {
          if (Principal.equal(user, userToUnblock)) {
            found := true;
          } else {
            newBuffer.add(user);
          };
        };
        
        if (found) {
          userBlocklist.put(caller, newBuffer);
          #ok(true)
        } else {
          #err(#NotFound)
        };
      };
      case null #err(#NotFound);
    }
  };

  public shared ({ caller }) func verifyUser(
    userId : Principal
  ) : async Result<Bool, Error> {
    
    if (not isAdmin(caller)) {
      return #err(#Unauthorized);
    };

    updateUser(userId, func(u) { { u with isVerified = true } });
    #ok(true)
  };

  // ===========================================================================
  // CHAT ROOMS (Enhanced)
  // ===========================================================================

  public shared ({ caller }) func createRoom(
    name : Text,
    description : ?Text,
    roomType : ChatRoomType,
    icon : ?Text,
    rules : ?Text,
    maxMembers : ?Nat
  ) : async Result<Nat, Error> {
    
    if (isBanned(caller)) {
      return #err(#Banned);
    };
    
    let id = nextRoomId;
    nextRoomId += 1;

    let room : ChatRoom = {
      id = id;
      name = name;
      description = description;
      roomType = roomType;
      moderators = [caller];
      createdBy = caller;
      createdAt = now();
      messageCount = 0;
      isArchived = false;
      lastActivity = now();
      icon = icon;
      rules = rules;
      maxMembers = maxMembers;
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

  public shared ({ caller }) func inviteToRoom(
    roomId : Nat,
    invitee : Principal
  ) : async Result<Bool, Error> {
    
    switch (findRoom(roomId)) {
      case null { return #err(#NotFound) };
      case (?room) {
        // Check permissions
        if (room.roomType == #Public) {
          return #err(#InvalidInput); // No need to invite to public rooms
        };
        
        if (not isModOrAdmin(caller) and not Array.find(room.moderators, func(p : Principal) : Bool { Principal.equal(p, caller }) != null) {
          return #err(#NoPermission);
        };
        
        // Check if room is full
        switch (room.maxMembers) {
          case (?max) {
            switch (userRoomMembership.get(roomId)) {
              case (?buffer) {
                if (buffer.size() >= max) {
                  return #err(#RoomFull);
                };
              };
              case null {};
            };
          };
          case null {};
        };

        // Add to invites
        switch (roomInvites.get(roomId)) {
          case (?buffer) {
            if (not Buffer.contains(buffer, invitee, Principal.equal)) {
              buffer.add(invitee);
            };
          };
          case null {
            let buffer = Buffer.Buffer<Principal>(10);
            buffer.add(invitee);
            roomInvites.put(roomId, buffer);
          };
        };

        // Create notification
        switch (findUser(caller)) {
          case (?inviter) {
            createNotification(
              invitee,
              #Invite,
              null,
              ?roomId,
              ?caller,
              "You've been invited to join " # room.name # " by " # inviter.displayName
            );
          };
          case null {};
        };
        
        #ok(true)
      };
    }
  };

  public shared ({ caller }) func updateRoom(
    roomId : Nat,
    newName : ?Text,
    newDescription : ?Text,
    newIcon : ?Text,
    newRules : ?Text,
    newMaxMembers : ?Nat
  ) : async Result<Bool, Error> {
    
    switch (findRoom(roomId)) {
      case null { return #err(#NotFound) };
      case (?room) {
        if (not isModOrAdmin(caller) and not Array.find(room.moderators, func(p : Principal) : Bool { Principal.equal(p, caller }) != null) {
          return #err(#NoPermission);
        };

        chatRooms := Array.map(chatRooms, func(r : ChatRoom) : ChatRoom {
          if (r.id == roomId) {
            {
              r with
              name = Option.get(newName, r.name);
              description = newDescription;
              icon = newIcon;
              rules = newRules;
              maxMembers = newMaxMembers;
            }
          } else r
        });
        
        #ok(true)
      };
    }
  };

  // ===========================================================================
  // MESSAGES (Enhanced with Attachments & Polls)
  // ===========================================================================

  public shared ({ caller }) func sendMessage(
    content : Text,
    roomId : Nat,
    replyTo : ?Nat,
    messageType : MessageType,
    poll : ?Poll,
    metadata : ?Blob
  ) : async Result<Nat, Error> {
    
    if (isBanned(caller)) {
      return #err(#Banned);
    };
    
    if (Text.size(content) > MAX_MESSAGE_LENGTH) {
      return #err(#MessageTooLong);
    };
    
    if (rateLimited(caller)) {
      return #err(#RateLimited);
    };
    
    // Check room membership
    switch (userRoomMembership.get(caller)) {
      case (?buffer) {
        if (not Buffer.contains(buffer, roomId, Nat.equal)) {
          return #err(#NoPermission);
        };
      };
      case null { return #err(#NoPermission) };
    };

    let id = nextMessageId;
    nextMessageId += 1;

    let mentions = extractMentions(content);
    
    // Create notifications for mentions
    for (mentioned in mentions.vals()) {
      if (not Principal.equal(mentioned, caller)) {
        createNotification(
          mentioned,
          #Mention,
          ?id,
          ?roomId,
          ?caller,
          "You were mentioned in a message"
        );
      };
    };

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
      threadId = null;
      roomId = roomId;
      mentions = mentions;
      attachments = [];
      messageType = messageType;
      poll = poll;
      metadata = metadata;
      encryptionKey = null;
    };

    messages := Array.append(messages, [message]);
    
    // Update indexes
    switch (messagesByRoom.get(roomId)) {
      case (?buffer) buffer.add(id);
      case null {
        let buffer = Buffer.Buffer<Nat>(100);
        buffer.add(id);
        messagesByRoom.put(roomId, buffer);
      };
    };
    
    // Update stats
    incrementMessageCount(caller);
    
    chatRooms := Array.map(chatRooms, func(r : ChatRoom) : ChatRoom {
      if (r.id == roomId) {
        { 
          r with 
          messageCount = r.messageCount + 1;
          lastActivity = now();
        }
      } else r
    });
    
    // Clean old messages periodically
    if (id % 100 == 0) {
      cleanOldMessages();
    };

    #ok(id)
  };

  public shared ({ caller }) func uploadAttachment(
    name : Text,
    type : Text,
    content : Blob,
    roomId : Nat
  ) : async Result<Text, Error> {
    
    if (isBanned(caller)) {
      return #err(#Banned);
    };
    
    if (content.size() > MAX_UPLOAD_SIZE_BYTES) {
      return #err(#StorageLimitExceeded);
    };
    
    // Check room membership
    switch (userRoomMembership.get(caller)) {
      case (?buffer) {
        if (not Buffer.contains(buffer, roomId, Nat.equal)) {
          return #err(#NoPermission);
        };
      };
      case null { return #err(#NoPermission) };
    };

    let id = "att_" # Nat.toText(nextAttachmentId);
    nextAttachmentId += 1;
    
    let hash = SHA256.fromBlob(content);
    
    let attachment : Attachment = {
      id = id;
      name = name;
      type = type;
      size = content.size();
      hash = hash;
      uploadedBy = caller;
      timestamp = now();
    };

    attachments := Array.append(attachments, [attachment]);
    
    #ok(id)
  };

  public shared ({ caller }) func voteInPoll(
    messageId : Nat,
    optionId : Nat
  ) : async Result<Bool, Error> {
    
    switch (findMessage(messageId)) {
      case null { return #err(#NotFound) };
      case (?message) {
        switch (message.poll) {
          case null { return #err(#InvalidInput) };
          case (?poll) {
            // Check if poll has ended
            switch (poll.endsAt) {
              case (?endsAt) {
                if (endsAt < now()) {
                  return #err(#PollEnded);
                };
              };
              case null {};
            };
            
            // Check if user has already voted
            if (Array.find(poll.voters, func(p : Principal) : Bool { Principal.equal(p, caller }) != null) {
              if (not poll.multipleChoice) {
                return #err(#DuplicateVote);
              };
            };
            
            // Find the option
            let updatedOptions = Array.map(poll.options, func(opt : PollOption) : PollOption {
              if (opt.id == optionId) {
                // Check if user already voted for this option
                if (Array.find(opt.votes, func(p : Principal) : Bool { Principal.equal(p, caller }) != null) {
                  // Remove vote
                  {
                    opt with
                    votes = Array.filter(opt.votes, func(p : Principal) : Bool {
                      not Principal.equal(p, caller)
                    })
                  }
                } else {
                  // Add vote
                  {
                    opt with
                    votes = Array.append(opt.votes, [caller])
                  }
                }
              } else opt
            });
            
            // Update message
            messages := Array.map(messages, func(m : Message) : Message {
              if (m.id == messageId) {
                switch (m.poll) {
                  case (?existingPoll) {
                    { 
                      m with 
                      poll = ?{
                        existingPoll with
                        options = updatedOptions
                      }
                    }
                  };
                  case null m;
                }
              } else m
            });
            
            #ok(true)
          };
        }
      };
    }
  };

  // ===========================================================================
  // TYPING INDICATORS & READ RECEIPTS
  // ===========================================================================

  public shared ({ caller }) func setTyping(
    roomId : Nat,
    isTyping : Bool
  ) : async Result<Bool, Error> {
    
    if (isTyping) {
      let indicator : TypingIndicator = {
        userId = caller;
        roomId = roomId;
        timestamp = now();
      };
      
      switch (typingIndicators.get(roomId)) {
        case (?buffer) {
          // Remove old indicators for this user
          let newBuffer = Buffer.Buffer<TypingIndicator>(buffer.size());
          for (ind in buffer.vals()) {
            if (not Principal.equal(ind.userId, caller)) {
              newBuffer.add(ind);
            };
          };
          newBuffer.add(indicator);
          typingIndicators.put(roomId, newBuffer);
        };
        case null {
          let buffer = Buffer.Buffer<TypingIndicator>(10);
          buffer.add(indicator);
          typingIndicators.put(roomId, buffer);
        };
      };
    } else {
      // Remove typing indicator
      switch (typingIndicators.get(roomId)) {
        case (?buffer) {
          let newBuffer = Buffer.Buffer<TypingIndicator>(buffer.size());
          for (ind in buffer.vals()) {
            if (not Principal.equal(ind.userId, caller)) {
              newBuffer.add(ind);
            };
          };
          typingIndicators.put(roomId, newBuffer);
        };
        case null {};
      };
    };
    
    #ok(true)
  };

  public query func getTypingUsers(roomId : Nat) : async [TypingIndicator] {
    let currentTime = now();
    switch (typingIndicators.get(roomId)) {
      case (?buffer) {
        // Filter out old indicators
        let active = Buffer.Buffer<TypingIndicator>(buffer.size());
        for (ind in buffer.vals()) {
          if (currentTime - ind.timestamp < TYPING_INDICATOR_TIMEOUT) {
            active.add(ind);
          };
        };
        Buffer.toArray(active)
      };
      case null [];
    }
  };

  public shared ({ caller }) func markAsRead(
    messageId : Nat
  ) : async Result<Bool, Error> {
    
    switch (findMessage(messageId)) {
      case null { return #err(#NotFound) };
      case (?message) {
        // Check if user has access to the room
        switch (userRoomMembership.get(caller)) {
          case (?buffer) {
            if (not Buffer.contains(buffer, message.roomId, Nat.equal)) {
              return #err(#NoPermission);
            };
          };
          case null { return #err(#NoPermission) };
        };

        switch (readReceipts.get(messageId)) {
          case (?map) {
            map.put(caller, now());
          };
          case null {
            let map = HashMap.HashMap<Principal, Nat>(16, Principal.equal, Principal.hash);
            map.put(caller, now());
            readReceipts.put(messageId, map);
          };
        };
        
        #ok(true)
      };
    }
  };

  public query func getReadReceipts(messageId : Nat) : async [(Principal, Nat)] {
    switch (readReceipts.get(messageId)) {
      case (?map) Iter.toArray(map.entries());
      case null [];
    }
  };

  // ===========================================================================
  // NOTIFICATIONS
  // ===========================================================================

  public shared ({ caller }) func getNotifications(
    unreadOnly : Bool,
    limit : Nat,
    offset : Nat
  ) : async [Notification] {
    
    let userNotifications = Array.filter(notifications, func(n : Notification) : Bool {
      Principal.equal(n.userId, caller)
    });
    
    let filtered = if (unreadOnly) {
      Array.filter(userNotifications, func(n : Notification) : Bool { not n.read })
    } else {
      userNotifications
    };
    
    // Sort by timestamp (newest first)
    let sorted = Array.sort(filtered, func(a : Notification, b : Notification) : Order.Order {
      if (a.timestamp > b.timestamp) { #greater }
      else if (a.timestamp < b.timestamp) { #less }
      else { #equal }
    });
    
    let start = offset;
    let end = Nat.min(start + limit, sorted.size());
    
    if (start >= sorted.size()) {
      return [];
    };
    
    Array.subArray(sorted, start, end - start)
  };

  public shared ({ caller }) func markNotificationAsRead(
    notificationId : Nat
  ) : async Result<Bool, Error> {
    
    var found = false;
    notifications := Array.map(notifications, func(n : Notification) : Notification {
      if (n.id == notificationId and Principal.equal(n.userId, caller)) {
        found := true;
        { n with read = true }
      } else n
    });
    
    if (found) {
      #ok(true)
    } else {
      #err(#NotFound)
    }
  };

  public shared ({ caller }) func clearNotifications(
    olderThanDays : ?Nat
  ) : async Result<Nat, Error> {
    
    let cutoff = switch (olderThanDays) {
      case (?days) now() - (days * 24 * 60 * 60);
      case null 0;
    };

    let beforeCount = notifications.size();
    notifications := Array.filter(notifications, func(n : Notification) : Bool {
      not Principal.equal(n.userId, caller) or n.timestamp >= cutoff
    });
    
    let afterCount = notifications.size();
    #ok(beforeCount - afterCount)
  };

  // ===========================================================================
  // SEARCH & ANALYTICS
  // ===========================================================================

  public query func advancedSearch(
    query : Text,
    roomId : ?Nat,
    fromUser : ?Principal,
    messageType : ?MessageType,
    startDate : ?Nat,
    endDate : ?Nat,
    limit : Nat,
    offset : Nat
  ) : async [Message] {
    
    let lowerQuery = Text.map(query, Prim.charToLower);
    var results = Buffer.Buffer<Message>(limit);
    var count : Nat = 0;
    
    for (msg in messages.vals()) {
      if (msg.deleted) continue;
      
      var matches = true;
      
      // Room filter
      switch (roomId) {
        case (?rId) matches := matches and msg.roomId == rId;
        case null {};
      };
      
      // User filter
      switch (fromUser) {
        case (?user) matches := matches and Principal.equal(msg.sender, user);
        case null {};
      };
      
      // Message type filter
      switch (messageType) {
        case (?mType) matches := matches and msg.messageType == mType;
        case null {};
      };
      
      // Date range filter
      switch (startDate) {
        case (?start) matches := matches and msg.timestamp >= start;
        case null {};
      };
      
      switch (endDate) {
        case (?end) matches := matches and msg.timestamp <= end;
        case null {};
      };
      
      // Content search
      if (query != "") {
        matches := matches and Text.contains(
          Text.map(msg.content, Prim.charToLower),
          #text lowerQuery
        );
      };
      
      if (matches) {
        if (count >= offset and results.size() < limit) {
          results.add(msg);
        };
        count += 1;
      };
    };
    
    Buffer.toArray(results)
  };

  public query func getAnalytics(
    startDate : Nat,
    endDate : Nat
  ) : async {
    totalMessages : Nat;
    activeUsers : Nat;
    newUsers : Nat;
    mostActiveRoom : ?Text;
    peakHour : Nat;
    messagesByType : [(Text, Nat)];
  } {
    
    let messagesInRange = Array.filter(messages, func(m : Message) : Bool {
      m.timestamp >= startDate and m.timestamp <= endDate
    });
    
    let usersInRange = Array.filter(users, func(u : User) : Bool {
      u.joined >= startDate and u.joined <= endDate
    });
    
    // Find most active room
    var roomActivity = HashMap.HashMap<Nat, Nat>(10, Nat.equal, Hash.hash);
    for (msg in messagesInRange.vals()) {
      switch (roomActivity.get(msg.roomId)) {
        case (?count) roomActivity.put(msg.roomId, count + 1);
        case null roomActivity.put(msg.roomId, 1);
      };
    };
    
    var mostActiveRoomId : ?Nat = null;
    var maxMessages : Nat = 0;
    for ((roomId, count) in roomActivity.entries()) {
      if (count > maxMessages) {
        maxMessages := count;
        mostActiveRoomId := ?roomId;
      };
    };
    
    let mostActiveRoomName = switch (mostActiveRoomId) {
      case (?id) {
        switch (findRoom(id)) {
          case (?room) ?room.name;
          case null null;
        }
      };
      case null null;
    };
    
    // Count messages by type
    var typeCounts = HashMap.HashMap<Text, Nat>(5, Text.equal, Text.hash);
    for (msg in messagesInRange.vals()) {
      let typeName = switch (msg.messageType) {
        case (#Text) "text";
        case (#Image) "image";
        case (#File) "file";
        case (#Voice) "voice";
        case (#System) "system";
        case (#Poll) "poll";
      };
      
      switch (typeCounts.get(typeName)) {
        case (?count) typeCounts.put(typeName, count + 1);
        case null typeCounts.put(typeName, 1);
      };
    };
    
    {
      totalMessages = messagesInRange.size();
      activeUsers = Array.size(Array.filter(users, func(u : User) : Bool {
        u.lastSeen >= startDate and u.lastSeen <= endDate
      }));
      newUsers = usersInRange.size();
      mostActiveRoom = mostActiveRoomName;
      peakHour = 0; // Simplified - would need hour calculation
      messagesByType = Iter.toArray(typeCounts.entries());
    }
  };

  // ===========================================================================
  // ADMIN UTILITIES
  // ===========================================================================

  public shared ({ caller }) func exportData(
    includeMessages : Bool,
    includeUsers : Bool,
    includeRooms : Bool
  ) : async Result<{
    users : [User];
    messages : [Message];
    rooms : [ChatRoom];
    attachments : [Attachment];
    timestamp : Nat;
  }, Error> {
    
    if (not isAdmin(caller)) {
      return #err(#Unauthorized);
    };
    
    #ok({
      users = if includeUsers then users else [];
      messages = if includeMessages then messages else [];
      rooms = if includeRooms then chatRooms else [];
      attachments = attachments;
      timestamp = now();
    })
  };

  public shared ({ caller }) func importData(
    data : {
      users : [User];
      messages : [Message];
      rooms : [ChatRoom];
      attachments : [Attachment];
    }
  ) : async Result<Bool, Error> {
    
    if (not isAdmin(caller)) {
      return #err(#Unauthorized);
    };
    
    // Backup current data
    let backup = {
      users = users;
      messages = messages;
      rooms = chatRooms;
      attachments = attachments;
    };
    
    try {
      // Import new data
      users := data.users;
      messages := data.messages;
      chatRooms := data.rooms;
      attachments := data.attachments;
      
      // Rebuild indexes
      rebuildIndexes();
      
      #ok(true)
    } catch (e) {
      // Restore backup on error
      users := backup.users;
      messages := backup.messages;
      chatRooms := backup.rooms;
      attachments := backup.attachments;
      rebuildIndexes();
      
      #err(#InvalidInput)
    }
  };

  public shared ({ caller }) func bulkDeleteMessages(
    roomId : Nat,
    startDate : Nat,
    endDate : Nat
  ) : async Result<Nat, Error> {
    
    if (not isAdmin(caller)) {
      return #err(#Unauthorized);
    };
    
    let beforeCount = messages.size();
    messages := Array.filter(messages, func(m : Message) : Bool {
      if (m.roomId == roomId 
          and m.timestamp >= startDate 
          and m.timestamp <= endDate
          and not m.pinned) {
        false
      } else {
        true
      }
    });
    
    let afterCount = messages.size();
    #ok(beforeCount - afterCount)
  };

  // ===========================================================================
  // QUERY ENDPOINTS
  // ===========================================================================

  public query ({ caller }) func whoAmI() : async ?User {
    findUser(caller)
  };

  public query func getOnlineUsers(roomId : ?Nat) : async [User] {
    let currentTime = now();
    Array.filter(users, func(u : User) : Bool {
      let isOnline = (currentTime - u.lastSeen) < 300;
      var inRoom = true;
      
      switch (roomId) {
        case (?rId) {
          switch (userRoomMembership.get(u.id)) {
            case (?buffer) inRoom := Buffer.contains(buffer, rId, Nat.equal);
            case null inRoom := false;
          };
        };
        case null {};
      };
      
      isOnline and inRoom and not u.banned
    })
  };

  public query func getRoomStatistics(roomId : Nat) : async ?{
    room : ChatRoom;
    totalMessages : Nat;
    activeUsers : Nat;
    messagesToday : Nat;
    topPosters : [(Principal, Nat)];
  } {
    switch (findRoom(roomId)) {
      case null null;
      case (?room) {
        let roomMessages = Array.filter(messages, func(m : Message) : Bool {
          m.roomId == roomId and not m.deleted
        });
        
        // Count messages per user
        var userMessageCounts = HashMap.HashMap<Principal, Nat>(32, Principal.equal, Principal.hash);
        for (msg in roomMessages.vals()) {
          switch (userMessageCounts.get(msg.sender)) {
            case (?count) userMessageCounts.put(msg.sender, count + 1);
            case null userMessageCounts.put(msg.sender, 1);
          };
        };
        
        // Get top 5 posters
        let topPostersArray = Iter.toArray(userMessageCounts.entries());
        let sortedPosters = Array.sort(topPostersArray, func(a : (Principal, Nat), b : (Principal, Nat)) : Order.Order {
          if (a.1 > b.1) { #greater }
          else if (a.1 < b.1) { #less }
          else { #equal }
        });
        
        let top5 = if (sortedPosters.size() > 5) {
          Array.subArray(sortedPosters, 0, 5)
        } else {
          sortedPosters
        };
        
        // Messages from last 24 hours
        let dayAgo = now() - (24 * 60 * 60);
        let messagesToday = Array.filter(roomMessages, func(m : Message) : Bool {
          m.timestamp >= dayAgo
        }).size();
        
        // Active users (posted in last 7 days)
        let weekAgo = now() - (7 * 24 * 60 * 60);
        let activeUsersSet = HashMap.HashMap<Principal, Bool>(32, Principal.equal, Principal.hash);
        for (msg in roomMessages.vals()) {
          if (msg.timestamp >= weekAgo) {
            activeUsersSet.put(msg.sender, true);
          };
        };
        
        ?{
          room = room;
          totalMessages = roomMessages.size();
          activeUsers = activeUsersSet.size();
          messagesToday = messagesToday;
          topPosters = top5;
        }
      };
    }
  };

  public query func version() : async Text {
    "ChatChain v5.0.0"
  };

  // ===========================================================================
  // SYSTEM HEALTH & MONITORING
  // ===========================================================================

  public query func getSystemHealth() : async {
    canisterId : Principal;
    version : Text;
    uptime : Nat;
    memoryUsage : Nat;
    cycleBalance : Nat;
    userCount : Nat;
    messageCount : Nat;
    roomCount : Nat;
    lastBackup : ?Nat;
    isHealthy : Bool;
  } {
    {
      canisterId = Principal.fromActor(ChatChain);
      version = "5.0.0";
      uptime = now();
      memoryUsage = 0; // Would need actual memory measurement
      cycleBalance = 0; // Would need cycle balance check
      userCount = users.size();
      messageCount = messages.size();
      roomCount = chatRooms.size();
      lastBackup = null;
      isHealthy = true;
    }
  };

  // ===========================================================================
  // PRIVATE FUNCTIONS
  // ===========================================================================

  // Hash function for HashMap
  private module Hash {
    public func hash(n : Nat) : Nat32 {
      CRC32.fromText(Nat.toText(n))
    };
  };

  // Periodically clean up old data
  private func periodicCleanup() {
    cleanOldMessages();
    
    // Clean old typing indicators
    let currentTime = now();
    for ((roomId, buffer) in typingIndicators.entries()) {
      let newBuffer = Buffer.Buffer<TypingIndicator>(buffer.size());
      for (ind in buffer.vals()) {
        if (currentTime - ind.timestamp < TYPING_INDICATOR_TIMEOUT) {
          newBuffer.add(ind);
        };
      };
      typingIndicators.put(roomId, newBuffer);
    };
    
    // Clean old notifications (older than 30 days)
    let notificationCutoff = now() - (30 * 24 * 60 * 60);
    notifications := Array.filter(notifications, func(n : Notification) : Bool {
      n.timestamp >= notificationCutoff
    });
  };
}

// ============================================================================
// END OF CHATCHAIN V5
// ============================================================================
























