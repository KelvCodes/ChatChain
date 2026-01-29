
    banned : Bool;
    bannedUntil : ?Int;
    lastSeen : Int;
    status : UserStatus;
    joined : Int;
    messageCount : Nat;
    reputation : Int;
    preferences : UserPreferences;
    isVerified : Bool;
  };
  
  public type Reaction = {
    reactor : Principal;
    emoji : Text;
    timestamp : Int;
  };
  
  public type Attachment = {
    id : Text;
    name : Text;
    type : Text;
    size : Nat;
    hash : Text;
    uploadedBy : Principal;
    timestamp : Int;
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
    endsAt : ?Int;
    voters : [Principal];
  };
  
  public type Message = {
    id : Nat;
    sender : Principal;
    content : Text;
    timestamp : Int;
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
    encryptionKey : ?Text;
  };
  
  public type ChatRoom = {
    id : Nat;
    name : Text;
    description : ?Text;
    roomType : ChatRoomType;
    moderators : [Principal];
    createdBy : Principal;
    createdAt : Int;
    messageCount : Nat;
    isArchived : Bool;
    lastActivity : Int;
    icon : ?Text;
    rules : ?Text;
    maxMembers : ?Nat;
  };
  
  public type Notification = {
    id : Nat;
    userId : Principal;
    type : NotificationType;
    messageId : ?Nat;
    roomId : ?Nat;
    fromUser : ?Principal;
    content : Text;
    timestamp : Int;
    read : Bool;
  };
  
  public type TypingIndicator = {
    userId : Principal;
    roomId : Nat;
    timestamp : Int;
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
    #InsufficientCycles;
  };
  
  public type Result<T, E> = Result.Result<T, E>;
  
  // Constants
  let EDIT_WINDOW_SECONDS : Int = 900; // 15 minutes
  let MAX_MESSAGE_LENGTH : Nat = 5000;
  let MAX_DISPLAY_NAME_LENGTH : Nat = 50;
  let RATE_LIMIT_SECONDS : Nat = 1;
  let MAX_MESSAGES_PER_USER_PER_DAY : Nat = 5000;
  let MESSAGE_RETENTION_DAYS : Int = 365;
  let MAX_PINNED_MESSAGES : Nat = 10;
  let MAX_UPLOAD_SIZE_BYTES : Nat = 10_000_000;
  let TYPING_INDICATOR_TIMEOUT : Int = 10_000_000_000; // 10 seconds in nanoseconds
  let NOTIFICATION_RETENTION_DAYS : Int = 30;
  let DEFAULT_PAGE_SIZE : Nat = 50;
  let MAX_SEARCH_RESULTS : Nat = 100;
  
  // ===========================================================================
  // STABLE STATE
  // ===========================================================================
  
  stable var nextMessageId : Nat = 0;
  stable var nextRoomId : Nat = 0;
  stable var nextNotificationId : Nat = 0;
  stable var nextAttachmentId : Nat = 0;
  stable var canisterCreatedAt : Int = Time.now();
  
  // Stable storage
  stable var stableUsers : [(Principal, User)] = [];
  stable var stableMessages : [(Nat, Message)] = [];
  stable var stableRooms : [(Nat, ChatRoom)] = [];
  stable var stableUserRoomMembership : [(Principal, [Nat])] = [];
  stable var stableRoomMembers : [(Nat, [Principal])] = [];
  stable var stableMessagesByRoom : [(Nat, [Nat])] = [];
  
  // ===========================================================================
  // IN-MEMORY STATE
  // ===========================================================================
  
  private let users = HashMap.HashMap<Principal, User>(0, Principal.equal, Principal.hash);
  private let messages = HashMap.HashMap<Nat, Message>(0, Nat.equal, Hash.hash);
  private let rooms = HashMap.HashMap<Nat, ChatRoom>(0, Nat.equal, Hash.hash);
  
  // Indexes
  private let userByUsername = TrieMap.TrieMap<Text, Principal>(Text.equal, Text.hash);
  private let userRoomMembership = HashMap.HashMap<Principal, Buffer.Buffer<Nat>>(0, Principal.equal, Principal.hash);
  private let roomMembers = HashMap.HashMap<Nat, Buffer.Buffer<Principal>>(0, Nat.equal, Hash.hash);
  private let messagesByRoom = HashMap.HashMap<Nat, Buffer.Buffer<Nat>>(0, Nat.equal, Hash.hash);
  
  // Rate limiting with cleanup
  private let messageRateLimiter = RateLimiter();
  
  // Cache for frequent queries
  private let onlineUsersCache = TrieMap.TrieMap<Nat, [User]>(Nat.equal, Hash.hash);
  private var lastCacheUpdate : Int = 0;
  private let CACHE_TTL : Int = 30_000_000_000; // 30 seconds
  
  // ===========================================================================
  // RATE LIMITER MODULE
  // ===========================================================================
  
  private class RateLimiter() {
    let dailyMessageCount = TrieMap.TrieMap<Principal, (Int, Nat)>(Principal.equal, Principal.hash);
    let lastMessageTime = TrieMap.TrieMap<Principal, Int>(Principal.equal, Principal.hash);
    let lastCleanup : Int = Time.now();
    
    public func checkRateLimit(userId : Principal) : Bool {
      let now = Time.now();
      
      // Clean old entries hourly
      if (now - lastCleanup > 3_600_000_000_000) {
        cleanupOldEntries(now);
      };
      
      // Check message interval
      switch (lastMessageTime.get(userId)) {
        case (?lastTime) {
          if (now - lastTime < RATE_LIMIT_SECONDS * 1_000_000_000) {
            return true;
          };
        };
        case null {};
      };
      lastMessageTime.put(userId, now);
      
      // Check daily limit
      let dayStart = now - (now % (24 * 60 * 60 * 1_000_000_000));
      switch (dailyMessageCount.get(userId)) {
        case (?(lastDay, count)) {
          if (lastDay == dayStart) {
            if (count >= MAX_MESSAGES_PER_USER_PER_DAY) {
              return true;
            };
            dailyMessageCount.put(userId, (dayStart, count + 1));
          } else {
            dailyMessageCount.put(userId, (dayStart, 1));
          };
        };
        case null {
          dailyMessageCount.put(userId, (dayStart, 1));
        };
      };
      
      false
    };
    
    private func cleanupOldEntries(now : Int) {
      let dayAgo = now - (24 * 60 * 60 * 1_000_000_000);
      
      // Clean old daily counts
      let toRemove = Buffer.Buffer<Principal>(100);
      for ((userId, (lastDay, _)) in dailyMessageCount.entries()) {
        if (lastDay < dayAgo) {
          toRemove.add(userId);
        };
      };
      for (userId in toRemove.vals()) {
        dailyMessageCount.delete(userId);
      };
      
      // Clean old message times (older than 1 minute)
      let minuteAgo = now - 60_000_000_000;
      let timeToRemove = Buffer.Buffer<Principal>(100);
      for ((userId, time) in lastMessageTime.entries()) {
        if (time < minuteAgo) {
          timeToRemove.add(userId);
        };
      };
      for (userId in timeToRemove.vals()) {
        lastMessageTime.delete(userId);
      };
    };
  };
  
  // ===========================================================================
  // INITIALIZATION
  // ===========================================================================
  
  system func preupgrade() {
    stableUsers := Iter.toArray(users.entries());
    stableMessages := Iter.toArray(messages.entries());
    stableRooms := Iter.toArray(rooms.entries());
    
    stableUserRoomMembership := Iter.toArray(
      userRoomMembership.entries()
      .map(func ((p, b) : (Principal, Buffer.Buffer<Nat>)) : (Principal, [Nat]) {
        (p, Buffer.toArray(b))
      })
    );
    
    stableRoomMembers := Iter.toArray(
      roomMembers.entries()
      .map(func ((roomId, b) : (Nat, Buffer.Buffer<Principal>)) : (Nat, [Principal]) {
        (roomId, Buffer.toArray(b))
      })
    );
    
    stableMessagesByRoom := Iter.toArray(
      messagesByRoom.entries()
      .map(func ((roomId, b) : (Nat, Buffer.Buffer<Nat>)) : (Nat, [Nat]) {
        (roomId, Buffer.toArray(b))
      })
    );
  };
  
  system func postupgrade() {
    // Load users
    for ((id, user) in stableUsers.vals()) {
      users.put(id, user);
      userByUsername.put(user.username, user.id);
    };
    
    // Load messages
    for ((id, message) in stableMessages.vals()) {
      messages.put(id, message);
    };
    
    // Load rooms
    for ((id, room) in stableRooms.vals()) {
      rooms.put(id, room);
    };
    
    // Load user room membership
    for ((p, arr) in stableUserRoomMembership.vals()) {
      userRoomMembership.put(p, Buffer.fromArray<Nat>(arr));
    };
    
    // Load room members
    for ((roomId, arr) in stableRoomMembers.vals()) {
      roomMembers.put(roomId, Buffer.fromArray<Principal>(arr));
    };
    
    // Load messages by room
    for ((roomId, arr) in stableMessagesByRoom.vals()) {
      messagesByRoom.put(roomId, Buffer.fromArray<Nat>(arr));
    };
  };
  
  // ===========================================================================
  // UTILITY FUNCTIONS
  // ===========================================================================
  
  private func now() : Int = Time.now();
  
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
  
  private func isAdmin(userId : Principal) : Bool {
    switch (users.get(userId)) {
      case (?user) { user.role == #Admin or user.role == #Owner };
      case null false;
    }
  };
  
  private func isModOrAdmin(userId : Principal) : Bool {
    switch (users.get(userId)) {
      case (?user) { user.role == #Admin or user.role == #Moderator or user.role == #Owner };
      case null false;
    }
  };
  
  private func isBanned(userId : Principal) : Bool {
    switch (users.get(userId)) {
      case (?user) {
        switch (user.bannedUntil) {
          case (?until) { user.banned and until > now() };
          case null user.banned;
        }
      };
      case null false;
    }
  };
  
  private func extractMentions(text : Text) : [Principal] {
    let words = Text.split(text, #char ' ');
    let mentions = Buffer.Buffer<Principal>(5);
    
    for (word in words) {
      if (Text.startsWith(word, #text "@")) {
        let username = Text.trimStart(word, #char '@');
        switch (userByUsername.get(username)) {
          case (?userId) mentions.add(userId);
          case null {};
        };
      };
    };
    
    Buffer.toArray(mentions)
  };
  
  private func updateUser(userId : Principal, update : User -> User) {
    switch (users.get(userId)) {
      case (?user) {
        let updated = update(user);
        users.put(userId, updated);
        if (user.username != updated.username) {
          userByUsername.delete(user.username);
          userByUsername.put(updated.username, userId);
        };
      };
      case null {};
    };
  };
  
  private func incrementMessageCount(userId : Principal) {
    updateUser(userId, func(user) { 
      { user with 
        messageCount = user.messageCount + 1;
        lastSeen = now();
      }
    });
  };
  
  private func updateRoomActivity(roomId : Nat) {
    switch (rooms.get(roomId)) {
      case (?room) {
        rooms.put(roomId, {
          room with
          messageCount = room.messageCount + 1;
          lastActivity = now();
        });
      };
      case null {};
    };
  };
  
  private func periodicCleanup() {
    let now = Time.now();
    let cutoff = now - (MESSAGE_RETENTION_DAYS * 24 * 60 * 60 * 1_000_000_000);
    
    // Clean old messages (keep pinned messages)
    let oldMessages = Buffer.Buffer<Nat>(100);
    for ((id, msg) in messages.entries()) {
      if (msg.timestamp < cutoff and not msg.pinned) {
        oldMessages.add(id);
      };
    };
    
    for (msgId in oldMessages.vals()) {
      messages.delete(msgId);
    };
  };
  
  // ===========================================================================
  // USER MANAGEMENT
  // ===========================================================================
  
  public shared ({ caller }) func registerUser(
    username : Text,
    displayName : Text,
    bio : ?Text
  ) : async Result<User, Error> {
    
    if (not isValidUsername(username)) {
      return #err(#InvalidInput);
    };
    
    if (not isValidDisplayName(displayName)) {
      return #err(#InvalidInput);
    };
    
    if (users.get(caller) != null) {
      return #err(#AlreadyExists);
    };
    
    if (userByUsername.get(username) != null) {
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
    
    users.put(caller, user);
    userByUsername.put(username, caller);
    
    #ok(user)
  };
  
  public shared ({ caller }) func updateProfile(
    newDisplayName : ?Text,
    newUsername : ?Text,
    newBio : ?Text,
    newAvatar : ?Text,
    newStatus : ?UserStatus,
    newPreferences : ?UserPreferences
  ) : async Result<User, Error> {
    
    switch (users.get(caller)) {
      case null { return #err(#NotFound) };
      case (?user) {
        if (isBanned(caller)) { return #err(#Banned) };
        
        let finalUsername = switch (newUsername) {
          case (?username) {
            if (not isValidUsername(username)) {
              return #err(#InvalidInput);
            };
            if (username != user.username and userByUsername.get(username) != null) {
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
          lastSeen = now();
        };
        
        updateUser(caller, func(_) { updatedUser });
        #ok(updatedUser)
      };
    }
  };
  
  public query func searchUsers(
    query : Text,
    limit : Nat,
    offset : Nat
  ) : async [User] {
    
    if (query == "") {
      let allUsers = Iter.toArray(users.vals());
      let start = Nat.min(offset, allUsers.size());
      let end = Nat.min(start + limit, allUsers.size());
      return Array.tabulate(end - start, func(i) { allUsers[start + i] });
    };
    
    let lowerQuery = Text.map(query, Prim.charToLower);
    let results = Buffer.Buffer<User>(limit);
    var count : Nat = 0;
    
    for ((_, user) in users.entries()) {
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
  
  public query func getUser(principalOrUsername : Text) : async ?User {
    // Try as Principal first
    switch (Principal.fromText(principalOrUsername)) {
      case (?principal) {
        users.get(principal)
      };
      case null {
        // Try as username
        switch (userByUsername.get(principalOrUsername)) {
          case (?principal) users.get(principal);
          case null null;
        };
      };
    }
  };
  
  // ===========================================================================
  // ROOM MANAGEMENT
  // ===========================================================================
  
  public shared ({ caller }) func createRoom(
    name : Text,
    description : ?Text,
    roomType : ChatRoomType,
    icon : ?Text,
    rules : ?Text,
    maxMembers : ?Nat
  ) : async Result<ChatRoom, Error> {
    
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
    
    rooms.put(id, room);
    
    // Add creator to room
    switch (userRoomMembership.get(caller)) {
      case (?buffer) buffer.add(id);
      case null {
        let buffer = Buffer.Buffer<Nat>(5);
        buffer.add(id);
        userRoomMembership.put(caller, buffer);
      };
    };
    
    let membersBuffer = Buffer.Buffer<Principal>(1);
    membersBuffer.add(caller);
    roomMembers.put(id, membersBuffer);
    messagesByRoom.put(id, Buffer.Buffer<Nat>(100));
    
    #ok(room)
  };
  
  public shared ({ caller }) func joinRoom(roomId : Nat) : async Result<Bool, Error> {
    switch (rooms.get(roomId)) {
      case null { return #err(#NotFound) };
      case (?room) {
        if (room.isArchived) {
          return #err(#InvalidInput);
        };
        
        if (isBanned(caller)) {
          return #err(#Banned);
        };
        
        // Check if room is full
        switch (room.maxMembers) {
          case (?max) {
            switch (roomMembers.get(roomId)) {
              case (?members) {
                if (members.size() >= max) {
                  return #err(#RoomFull);
                };
              };
              case null {};
            };
          };
          case null {};
        };
        
        // For private rooms, check if user has invite
        if (room.roomType == #Private) {
          // Implementation for invite checking would go here
          return #err(#NoPermission);
        };
        
        // Add to user's room list
        switch (userRoomMembership.get(caller)) {
          case (?buffer) {
            if (not Buffer.contains(buffer, roomId, Nat.equal)) {
              buffer.add(roomId);
            };
          };
          case null {
            let buffer = Buffer.Buffer<Nat>(5);
            buffer.add(roomId);
            userRoomMembership.put(caller, buffer);
          };
        };
        
        // Add to room's member list
        switch (roomMembers.get(roomId)) {
          case (?buffer) {
            if (not Buffer.contains(buffer, caller, Principal.equal)) {
              buffer.add(caller);
            };
          };
          case null {
            let buffer = Buffer.Buffer<Principal>(10);
            buffer.add(caller);
            roomMembers.put(roomId, buffer);
          };
        };
        
        #ok(true)
      };
    }
  };
  
  public query func getRooms(
    roomType : ?ChatRoomType,
    limit : Nat,
    offset : Nat
  ) : async [ChatRoom] {
    
    let filteredRooms = Buffer.Buffer<ChatRoom>(limit);
    var count : Nat = 0;
    
    for ((_, room) in rooms.entries()) {
      if (room.isArchived) continue;
      
      switch (roomType) {
        case (?typeFilter) {
          if (room.roomType != typeFilter) continue;
        };
        case null {};
      };
      
      if (count >= offset and filteredRooms.size() < limit) {
        filteredRooms.add(room);
      };
      count += 1;
    };
    
    Buffer.toArray(filteredRooms)
  };
  
  // ===========================================================================
  // MESSAGE MANAGEMENT
  // ===========================================================================
  
  public shared ({ caller }) func sendMessage(
    content : Text,
    roomId : Nat,
    replyTo : ?Nat,
    messageType : MessageType,
    poll : ?Poll,
    metadata : ?Blob
  ) : async Result<Message, Error> {
    
    if (isBanned(caller)) {
      return #err(#Banned);
    };
    
    if (Text.size(content) > MAX_MESSAGE_LENGTH) {
      return #err(#MessageTooLong);
    };
    
    if (messageRateLimiter.checkRateLimit(caller)) {
      return #err(#RateLimited);
    };
    
    // Check room membership
    var hasAccess = false;
    switch (userRoomMembership.get(caller)) {
      case (?buffer) {
        hasAccess := Buffer.contains(buffer, roomId, Nat.equal);
      };
      case null {};
    };
    
    if (not hasAccess) {
      return #err(#NoPermission);
    };
    
    let id = nextMessageId;
    nextMessageId += 1;
    
    let mentions = extractMentions(content);
    let nowTime = now();
    
    let message : Message = {
      id = id;
      sender = caller;
      content = content;
      timestamp = nowTime;
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
    
    messages.put(id, message);
    
    // Add to room's message index
    switch (messagesByRoom.get(roomId)) {
      case (?buffer) buffer.add(id);
      case null {
        let buffer = Buffer.Buffer<Nat>(100);
        buffer.add(id);
        messagesByRoom.put(roomId, buffer);
      };
    };
    
    // Update statistics
    incrementMessageCount(caller);
    updateRoomActivity(roomId);
    
    // Periodic cleanup every 100 messages
    if (id % 100 == 0) {
      periodicCleanup();
    };
    
    #ok(message)
  };
  
  public shared ({ caller }) func editMessage(
    messageId : Nat,
    newContent : Text
  ) : async Result<Message, Error> {
    
    switch (messages.get(messageId)) {
      case null { return #err(#NotFound) };
      case (?message) {
        if (not Principal.equal(message.sender, caller)) {
          return #err(#Unauthorized);
        };
        
        if (now() - message.timestamp > EDIT_WINDOW_SECONDS * 1_000_000_000) {
          return #err(#InvalidInput);
        };
        
        if (Text.size(newContent) > MAX_MESSAGE_LENGTH) {
          return #err(#MessageTooLong);
        };
        
        let updatedMessage = {
          message with
          content = newContent;
          edited = true;
          mentions = extractMentions(newContent);
        };
        
        messages.put(messageId, updatedMessage);
        #ok(updatedMessage)
      };
    }
  };
  
  public shared ({ caller }) func deleteMessage(messageId : Nat) : async Result<Bool, Error> {
    switch (messages.get(messageId)) {
      case null { return #err(#NotFound) };
      case (?message) {
        if (not Principal.equal(message.sender, caller) and not isModOrAdmin(caller)) {
          return #err(#Unauthorized);
        };
        
        messages.put(messageId, { message with deleted = true });
        #ok(true)
      };
    }
  };
  
  public query func getMessages(
    roomId : Nat,
    limit : Nat,
    before : ?Nat
  ) : async [Message] {
    
    let actualLimit = Nat.min(limit, DEFAULT_PAGE_SIZE);
    let results = Buffer.Buffer<Message>(actualLimit);
    
    switch (messagesByRoom.get(roomId)) {
      case (?messageIds) {
        let size = messageIds.size();
        if (size == 0) return [];
        
        // Find starting index
        let startIdx = switch (before) {
          case (?msgId) {
            var foundIdx = size;
            for (i in Iter.range(0, size - 1)) {
              if (messageIds.get(i) == msgId) {
                foundIdx := i;
              };
            };
            if (foundIdx > 0) foundIdx - 1 else 0
          };
          case null size - 1;
        };
        
        // Collect messages
        var idx = startIdx;
        var count = 0;
        while (idx >= 0 and count < actualLimit) {
          let msgId = messageIds.get(idx);
          switch (messages.get(msgId)) {
            case (?msg) {
              if (not msg.deleted) {
                results.add(msg);
                count += 1;
              };
            };
            case null {};
          };
          idx -= 1;
        };
      };
      case null {};
    };
    
    // Return in chronological order
    Buffer.toArray(results)
  };
  
  // ===========================================================================
  // CACHED QUERIES
  // ===========================================================================
  
  public query ({ caller }) func whoAmI() : async ?User {
    users.get(caller)
  };
  
  public query func getOnlineUsers(roomId : ?Nat) : async [User] {
    let now = Time.now();
    
    // Check cache first
    switch (roomId) {
      case (?id) {
        switch (onlineUsersCache.get(id)) {
          case (?cached) {
            if (now - lastCacheUpdate < CACHE_TTL) {
              return cached;
            };
          };
          case null {};
        };
      };
      case null {};
    };
    
    let onlineThreshold = 300_000_000_000; // 5 minutes
    let results = Buffer.Buffer<User>(50);
    
    for ((_, user) in users.entries()) {
      if (user.banned) continue;
      
      let isOnline = (now - user.lastSeen) < onlineThreshold;
      var inRoom = true;
      
      switch (roomId) {
        case (?rId) {
          switch (userRoomMembership.get(user.id)) {
            case (?buffer) inRoom := Buffer.contains(buffer, rId, Nat.equal);
            case null inRoom := false;
          };
        };
        case null {};
      };
      
      if (isOnline and inRoom) {
        results.add(user);
      };
    };
    
    let result = Buffer.toArray(results);
    
    // Update cache
    switch (roomId) {
      case (?id) {
        onlineUsersCache.put(id, result);
      };
      case null {};
    };
    
    result
  };
  
  public query func getRoomStatistics(roomId : Nat) : async ?{
    room : ChatRoom;
    totalMessages : Nat;
    activeUsers : Nat;
    messagesToday : Nat;
    topPosters : [(Principal, Nat)];
  } {
    switch (rooms.get(roomId)) {
      case null null;
      case (?room) {
        let userMessageCounts = TrieMap.TrieMap<Principal, Nat>(Principal.equal, Principal.hash);
        var totalMessages : Nat = 0;
        var messagesToday : Nat = 0;
        let activeUsers = TrieMap.TrieMap<Principal, Bool>(Principal.equal, Principal.hash);
        
        let dayAgo = now() - (24 * 60 * 60 * 1_000_000_000);
        let weekAgo = now() - (7 * 24 * 60 * 60 * 1_000_000_000);
        
        // Count messages
        switch (messagesByRoom.get(roomId)) {
          case (?messageIds) {
            for (msgId in messageIds.vals()) {
              switch (messages.get(msgId)) {
                case (?msg) {
                  if (not msg.deleted) {
                    totalMessages += 1;
                    
                    // Count per user
                    switch (userMessageCounts.get(msg.sender)) {
                      case (?count) userMessageCounts.put(msg.sender, count + 1);
                      case null userMessageCounts.put(msg.sender, 1);
                    };
                    
                    // Count today's messages
                    if (msg.timestamp >= dayAgo) {
                      messagesToday += 1;
                    };
                    
                    // Active users (last week)
                    if (msg.timestamp >= weekAgo) {
                      activeUsers.put(msg.sender, true);
                    };
                  };
                };
                case null {};
              };
            };
          };
          case null {};
        };
        
        // Get top posters
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
        
        ?{
          room = room;
          totalMessages = totalMessages;
          activeUsers = activeUsers.size();
          messagesToday = messagesToday;
          topPosters = top5;
        }
      };
    }
  };
  
  public query func version() : async Text {
    "ChatChain v5.2.0"
  };
  
  public query func getSystemHealth() : async {
    canisterId : Principal;
    version : Text;
    uptime : Int;
    userCount : Nat;
    messageCount : Nat;
    roomCount : Nat;
    storageSize : Nat;
    isHealthy : Bool;
  } {
    // Estimate storage size
    let storageSize = (users.size() * 500) + (messages.size() * 200) + (rooms.size() * 300);
    
    {
      canisterId = Principal.fromActor(ChatChain);
      version = "5.2.0";
      uptime = now() - canisterCreatedAt;
      userCount = users.size();
      messageCount = messages.size();
      roomCount = rooms.size();
      storageSize = storageSize;
      isHealthy = true;
    }
  };
  
  // ===========================================================================
  // ADMIN FUNCTIONS
  // ===========================================================================
  
  public shared ({ caller }) func deleteOldMessages(
    daysOld : Nat
  ) : async Result<Nat, Error> {
    
    if (not isAdmin(caller)) {
      return #err(#Unauthorized);
    };
    
    let cutoff = now() - (daysOld * 24 * 60 * 60 * 1_000_000_000);
    let deleted = Buffer.Buffer<Nat>(100);
    
    for ((id, msg) in messages.entries()) {
      if (msg.timestamp < cutoff and not msg.pinned) {
        deleted.add(id);
      };
    };
    
    let count = deleted.size();
    for (id in deleted.vals()) {
      messages.delete(id);
    };
    
    #ok(count)
  };
  
  public shared ({ caller }) func backupData() : async Result<{
    users : [User];
    messages : [Message];
    rooms : [ChatRoom];
    timestamp : Int;
  }, Error> {
    
    if (not isAdmin(caller)) {
      return #err(#Unauthorized);
    };
    
    #ok({
      users = Iter.toArray(users.vals());
      messages = Iter.toArray(messages.vals());
      rooms = Iter.toArray(rooms.vals());
      timestamp = now();
    })
  };
  
  // ===========================================================================
  // BATCH OPERATIONS
  // ===========================================================================
  
  public shared ({ caller }) func batchSendMessages(
    messages : [{
      content : Text;
      roomId : Nat;
    }]
  ) : async Result<[Message], Error> {
    
    if (isBanned(caller)) {
      return #err(#Banned);
    };
    
    let results = Buffer.Buffer<Message>(messages.size());
    
    for (msg in messages.vals()) {
      if (Text.size(msg.content) > MAX_MESSAGE_LENGTH) {
        return #err(#MessageTooLong);
      };
      
      // Check room membership for each message
      var hasAccess = false;
      switch (userRoomMembership.get(caller)) {
        case (?buffer) {
          hasAccess := Buffer.contains(buffer, msg.roomId, Nat.equal);
        };
        case null {};
      };
      
      if (not hasAccess) {
        return #err(#NoPermission);
      };
    };
    
    // Send all messages
    for (msg in messages.vals()) {
      let id = nextMessageId;
      nextMessageId += 1;
      
      let newMessage : Message = {
        id = id;
        sender = caller;
        content = msg.content;
        timestamp = now();
        edited = false;
        deleted = false;
        pinned = false;
        reactions = [];
        replyTo = null;
        threadId = null;
        roomId = msg.roomId;
        mentions = extractMentions(msg.content);
        attachments = [];
        messageType = #Text;
        poll = null;
        metadata = null;
        encryptionKey = null;
      };
      
      this.messages.put(id, newMessage);
      
      // Add to room's message index
      switch (messagesByRoom.get(msg.roomId)) {
        case (?buffer) buffer.add(id);
        case null {
          let buffer = Buffer.Buffer<Nat>(100);
          buffer.add(id);
          messagesByRoom.put(msg.roomId, buffer);
        };
      };
      
      results.add(newMessage);
      incrementMessageCount(caller);
      updateRoomActivity(msg.roomId);
    };
    
    #ok(Buffer.toArray(results))
  };
}





































