
  
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
    avatar : ?Text;
    role : UserRole;
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
    createdAt : Int;
    messageCount : Nat;
    isArchived : Bool;
    lastActivity : Int;
    icon : ?Text;
    rules : ?Text;
    maxMembers : ?Nat;
  };

  public type NotificationType = {
    #Mention;
    #Reply;
    #Reaction;
    #Invite;
    #System;
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

  // ===========================================================================
  // CONSTANTS
  // ===========================================================================
  
  let EDIT_WINDOW_SECONDS : Int = 15 * 60;
  let MAX_MESSAGE_LENGTH : Nat = 5000;
  let MAX_DISPLAY_NAME_LENGTH : Nat = 50;
  let RATE_LIMIT_SECONDS : Nat = 1;
  let MAX_MESSAGES_PER_USER_PER_DAY : Nat = 5000;
  let MESSAGE_RETENTION_DAYS : Int = 365;
  let MAX_REACTIONS_PER_MESSAGE : Nat = 50;
  let MAX_PINNED_MESSAGES : Nat = 10;
  let MAX_UPLOAD_SIZE_BYTES : Nat = 10_000_000;
  let MAX_USER_BLOCKLIST_SIZE : Nat = 1000;
  let TYPING_INDICATOR_TIMEOUT : Int = 10;
  let NOTIFICATION_RETENTION_DAYS : Int = 30;
  let MAX_SEARCH_RESULTS : Nat = 100;
  let DEFAULT_PAGE_SIZE : Nat = 50;

  // ===========================================================================
  // STABLE STATE
  // ===========================================================================
  
  stable var nextMessageId : Nat = 0;
  stable var nextRoomId : Nat = 0;
  stable var nextNotificationId : Nat = 0;
  stable var nextAttachmentId : Nat = 0;
  stable var canisterCreatedAt : Int = Time.now();
  
  // Stable maps
  stable var usersEntries : [(Principal, User)] = [];
  stable var messagesEntries : [(Nat, Message)] = [];
  stable var chatRoomsEntries : [(Nat, ChatRoom)] = [];
  stable var attachmentsEntries : [(Text, Attachment)] = [];
  
  stable var userRoomMembershipEntries : [(Principal, [Nat])] = [];
  stable var roomMembersEntries : [(Nat, [Principal])] = [];
  stable var userBlocklistEntries : [(Principal, [Principal])] = [];
  stable var typingIndicatorsEntries : [(Nat, [TypingIndicator])] = [];
  stable var readReceiptsEntries : [(Nat, [(Principal, Int)])] = [];
  stable var pollVotesEntries : [(Nat, [Principal])] = [];
  stable var roomInvitesEntries : [(Nat, [Principal])] = [];
  stable var notificationsByUserEntries : [(Principal, [Notification])] = [];
  stable var messagesByRoomEntries : [(Nat, [Nat])] = [];
  stable var pinnedMessagesEntries : [(Nat, [Nat])] = [];
  stable var dailyMessageCountEntries : [(Principal, Nat)] = [];
  stable var lastMessageTimeEntries : [(Principal, Int)] = [];

  // ===========================================================================
  // IN-MEMORY STATE
  // ===========================================================================
  
  private let users = HashMap.HashMap<Principal, User>(0, Principal.equal, Principal.hash);
  private let messages = HashMap.HashMap<Nat, Message>(0, Nat.equal, Hash.hash);
  private let chatRooms = HashMap.HashMap<Nat, ChatRoom>(0, Nat.equal, Hash.hash);
  private let attachments = TrieMap.TrieMap<Text, Attachment>(Text.equal, Text.hash);
  
  // Indexes
  private let userByUsername = TrieMap.TrieMap<Text, Principal>(Text.equal, Text.hash);
  private let userRoomMembership = HashMap.HashMap<Principal, Buffer.Buffer<Nat>>(0, Principal.equal, Principal.hash);
  private let roomMembers = HashMap.HashMap<Nat, Buffer.Buffer<Principal>>(0, Nat.equal, Hash.hash);
  private let userBlocklist = HashMap.HashMap<Principal, Buffer.Buffer<Principal>>(0, Principal.equal, Principal.hash);
  private let typingIndicators = HashMap.HashMap<Nat, Buffer.Buffer<TypingIndicator>>(0, Nat.equal, Hash.hash);
  private let readReceipts = HashMap.HashMap<Nat, HashMap.HashMap<Principal, Int>>(0, Nat.equal, Hash.hash);
  private let pollVotes = HashMap.HashMap<Nat, Buffer.Buffer<Principal>>(0, Nat.equal, Hash.hash);
  private let roomInvites = HashMap.HashMap<Nat, Buffer.Buffer<Principal>>(0, Nat.equal, Hash.hash);
  private let notificationsByUser = HashMap.HashMap<Principal, Buffer.Buffer<Notification>>(0, Principal.equal, Principal.hash);
  private let messagesByRoom = HashMap.HashMap<Nat, Buffer.Buffer<Nat>>(0, Nat.equal, Hash.hash);
  private let pinnedMessages = HashMap.HashMap<Nat, Buffer.Buffer<Nat>>(0, Nat.equal, Hash.hash);
  
  // Rate limiting
  private let dailyMessageCount = HashMap.HashMap<Principal, Nat>(0, Principal.equal, Principal.hash);
  private let lastMessageTime = HashMap.HashMap<Principal, Int>(0, Principal.equal, Principal.hash);
  
  // ===========================================================================
  // INITIALIZATION
  // ===========================================================================
  
  system func preupgrade() {
    usersEntries := Iter.toArray(users.entries());
    messagesEntries := Iter.toArray(messages.entries());
    chatRoomsEntries := Iter.toArray(chatRooms.entries());
    attachmentsEntries := Iter.toArray(attachments.entries());
    
    userRoomMembershipEntries := Iter.toArray(
      userRoomMembership.entries()
      .map(func ((p, b) : (Principal, Buffer.Buffer<Nat>)) : (Principal, [Nat]) {
        (p, Buffer.toArray(b))
      })
    );
    
    roomMembersEntries := Iter.toArray(
      roomMembers.entries()
      .map(func ((roomId, b) : (Nat, Buffer.Buffer<Principal>)) : (Nat, [Principal]) {
        (roomId, Buffer.toArray(b))
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
      .map(func ((msgId, map) : (Nat, HashMap.HashMap<Principal, Int>)) : (Nat, [(Principal, Int)]) {
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
    
    notificationsByUserEntries := Iter.toArray(
      notificationsByUser.entries()
      .map(func ((p, b) : (Principal, Buffer.Buffer<Notification>)) : (Principal, [Notification]) {
        (p, Buffer.toArray(b))
      })
    );
    
    messagesByRoomEntries := Iter.toArray(
      messagesByRoom.entries()
      .map(func ((roomId, b) : (Nat, Buffer.Buffer<Nat>)) : (Nat, [Nat]) {
        (roomId, Buffer.toArray(b))
      })
    );
    
    pinnedMessagesEntries := Iter.toArray(
      pinnedMessages.entries()
      .map(func ((roomId, b) : (Nat, Buffer.Buffer<Nat>)) : (Nat, [Nat]) {
        (roomId, Buffer.toArray(b))
      })
    );
    
    dailyMessageCountEntries := Iter.toArray(dailyMessageCount.entries());
    lastMessageTimeEntries := Iter.toArray(lastMessageTime.entries());
  };
  
  system func postupgrade() {
    // Load users
    for ((id, user) in usersEntries.vals()) {
      users.put(id, user);
      userByUsername.put(user.username, user.id);
    };
    
    // Load messages
    for ((id, message) in messagesEntries.vals()) {
      messages.put(id, message);
    };
    
    // Load chat rooms
    for ((id, room) in chatRoomsEntries.vals()) {
      chatRooms.put(id, room);
    };
    
    // Load attachments
    for ((id, attachment) in attachmentsEntries.vals()) {
      attachments.put(id, attachment);
    };
    
    // Helper function to load buffers
    func loadBuffer<T>(entries : [(Nat, [T])], size : Nat) : HashMap.HashMap<Nat, Buffer.Buffer<T>> {
      let map = HashMap.HashMap<Nat, Buffer.Buffer<T>>(size, Nat.equal, Hash.hash);
      for ((id, arr) in entries.vals()) {
        map.put(id, Buffer.fromArray<T>(arr));
      };
      map
    };
    
    func loadUserBuffer<T>(entries : [(Principal, [T])], size : Nat) : HashMap.HashMap<Principal, Buffer.Buffer<T>> {
      let map = HashMap.HashMap<Principal, Buffer.Buffer<T>>(size, Principal.equal, Principal.hash);
      for ((p, arr) in entries.vals()) {
        map.put(p, Buffer.fromArray<T>(arr));
      };
      map
    };
    
    // Load all buffers
    userRoomMembership := loadUserBuffer(userRoomMembershipEntries, userRoomMembershipEntries.size());
    roomMembers := loadBuffer(roomMembersEntries, roomMembersEntries.size());
    userBlocklist := loadUserBuffer(userBlocklistEntries, userBlocklistEntries.size());
    typingIndicators := loadBuffer(typingIndicatorsEntries, typingIndicatorsEntries.size());
    roomInvites := loadBuffer(roomInvitesEntries, roomInvitesEntries.size());
    notificationsByUser := loadUserBuffer(notificationsByUserEntries, notificationsByUserEntries.size());
    messagesByRoom := loadBuffer(messagesByRoomEntries, messagesByRoomEntries.size());
    pinnedMessages := loadBuffer(pinnedMessagesEntries, pinnedMessagesEntries.size());
    
    // Load poll votes
    for ((pollId, arr) in pollVotesEntries.vals()) {
      pollVotes.put(pollId, Buffer.fromArray<Principal>(arr));
    };
    
    // Load read receipts
    for ((msgId, entries) in readReceiptsEntries.vals()) {
      let map = HashMap.HashMap<Principal, Int>(16, Principal.equal, Principal.hash);
      for ((p, time) in entries.vals()) {
        map.put(p, time);
      };
      readReceipts.put(msgId, map);
    };
    
    // Load rate limiting data
    for ((p, count) in dailyMessageCountEntries.vals()) {
      dailyMessageCount.put(p, count);
    };
    
    for ((p, time) in lastMessageTimeEntries.vals()) {
      lastMessageTime.put(p, time);
    };
  };
  
  // ===========================================================================
  // PRIVATE HELPERS
  // ===========================================================================
  
  private func now() : Int {
    Time.now()
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
  
  private func isAdmin(p : Principal) : Bool {
    switch (users.get(p)) {
      case (?user) { user.role == #Admin or user.role == #Owner };
      case null false;
    }
  };
  
  private func isModOrAdmin(p : Principal) : Bool {
    switch (users.get(p)) {
      case (?user) { user.role == #Admin or user.role == #Moderator or user.role == #Owner };
      case null false;
    }
  };
  
  private func isBanned(p : Principal) : Bool {
    switch (users.get(p)) {
      case (?user) {
        switch (user.bannedUntil) {
          case (?until) {
            user.banned and until > now()
          };
          case null user.banned;
        }
      };
      case null true;
    }
  };
  
  private func checkRateLimit(p : Principal) : Bool {
    let currentTime = now();
    
    // Check message interval
    switch (lastMessageTime.get(p)) {
      case (?lastTime) {
        if (currentTime - lastTime < RATE_LIMIT_SECONDS * 1_000_000_000) {
          return true;
        };
      };
      case null {};
    };
    
    lastMessageTime.put(p, currentTime);
    
    // Check daily limit
    let dayStart = currentTime - (currentTime % (24 * 60 * 60 * 1_000_000_000));
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
  
  private func extractMentions(text : Text) : [Principal] {
    let words = Text.split(text, #char ' ');
    let mentions = Buffer.Buffer<Principal>(10);
    
    for (word in words) {
      if (Text.startsWith(word, #text "@")) {
        let username = Text.trimStart(word, #char '@');
        switch (userByUsername.get(username)) {
          case (?user) mentions.add(user);
          case null {};
        };
      };
    };
    
    Buffer.toArray(mentions)
  };
  
  private func createNotification(
    userId : Principal,
    type : NotificationType,
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
    
    switch (notificationsByUser.get(userId)) {
      case (?buffer) buffer.add(notification);
      case null {
        let buffer = Buffer.Buffer<Notification>(10);
        buffer.add(notification);
        notificationsByUser.put(userId, buffer);
      };
    };
    
    id
  };
  
  private func updateUser(p : Principal, update : User -> User) {
    switch (users.get(p)) {
      case (?user) {
        let updated = update(user);
        users.put(p, updated);
        // Update username index if changed
        if (user.username != updated.username) {
          userByUsername.delete(user.username);
          userByUsername.put(updated.username, p);
        };
      };
      case null {};
    };
  };
  
  private func incrementMessageCount(p : Principal) {
    updateUser(p, func(user) { 
      { 
        user with 
        messageCount = user.messageCount + 1;
        lastSeen = now();
      }
    });
  };
  
  private func cleanOldData() {
    let cutoff = now() - (MESSAGE_RETENTION_DAYS * 24 * 60 * 60 * 1_000_000_000);
    
    // Clean old messages (except pinned)
    let oldMessages = Buffer.Buffer<Nat>(100);
    for ((id, msg) in messages.entries()) {
      if (msg.timestamp < cutoff and not msg.pinned) {
        oldMessages.add(id);
      };
    };
    
    for (id in oldMessages.vals()) {
      messages.delete(id);
      // Remove from indexes
      switch (messages.get(id)) {
        case (?msg) {
          switch (messagesByRoom.get(msg.roomId)) {
            case (?buffer) {
              let index = Buffer.indexOf(id, buffer, Nat.equal);
              switch (index) {
                case (?i) buffer.remove(i);
                case null {};
              };
            };
            case null {};
          };
        };
        case null {};
      };
    };
    
    // Clean old notifications
    let notificationCutoff = now() - (NOTIFICATION_RETENTION_DAYS * 24 * 60 * 60 * 1_000_000_000);
    for ((userId, buffer) in notificationsByUser.entries()) {
      let newBuffer = Buffer.Buffer<Notification>(buffer.size());
      for (notification in buffer.vals()) {
        if (notification.timestamp >= notificationCutoff) {
          newBuffer.add(notification);
        };
      };
      notificationsByUser.put(userId, newBuffer);
    };
    
    // Reset daily message counts periodically
    if (now() % (24 * 60 * 60 * 1_000_000_000) < 60_000_000_000) { // Once per hour
      dailyMessageCount.clear();
    };
  };
  
  // ===========================================================================
  // USER MANAGEMENT
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
    
    #ok(true)
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
  
  // ===========================================================================
  // CHAT ROOMS
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
    
    chatRooms.put(id, room);
    
    // Add creator to room membership
    switch (userRoomMembership.get(caller)) {
      case (?buffer) { buffer.add(id) };
      case null {
        let buffer = Buffer.Buffer<Nat>(5);
        buffer.add(id);
        userRoomMembership.put(caller, buffer);
      };
    };
    
    // Add to room members
    let membersBuffer = Buffer.Buffer<Principal>(1);
    membersBuffer.add(caller);
    roomMembers.put(id, membersBuffer);
    
    #ok(room)
  };
  
  public shared ({ caller }) func joinRoom(
    roomId : Nat
  ) : async Result<Bool, Error> {
    
    switch (chatRooms.get(roomId)) {
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
        
        // Check if private room requires invite
        if (room.roomType == #Private) {
          var hasInvite = false;
          switch (roomInvites.get(roomId)) {
            case (?invites) {
              hasInvite := Buffer.contains(invites, caller, Principal.equal);
            };
            case null {};
          };
          if (not hasInvite) {
            return #err(#NoPermission);
          };
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
  
  // ===========================================================================
  // MESSAGES
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
    
    if (checkRateLimit(caller)) {
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
    
    messages.put(id, message);
    
    // Update room message index
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
    
    // Update room activity
    switch (chatRooms.get(roomId)) {
      case (?room) {
        chatRooms.put(roomId, {
          room with
          messageCount = room.messageCount + 1;
          lastActivity = now();
        });
      };
      case null {};
    };
    
    // Periodic cleanup
    if (id % 100 == 0) {
      cleanOldData();
    };
    
    #ok(message)
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
        var count : Nat = 0;
        
        // Iterate backwards for pagination
        let size = messageIds.size();
        let startIdx = switch (before) {
          case (?msgId) {
            var idx = size;
            for (i in Iter.range(0, size - 1)) {
              if (messageIds.get(i) == msgId) {
                idx := i;
              };
            };
            if (idx > 0) idx - 1 else 0
          };
          case null size - 1;
        };
        
        var idx = startIdx;
        while (count < actualLimit and idx >= 0) {
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
  // NOTIFICATIONS
  // ===========================================================================
  
  public shared ({ caller }) func getNotifications(
    unreadOnly : Bool,
    limit : Nat,
    offset : Nat
  ) : async [Notification] {
    
    let results = Buffer.Buffer<Notification>(limit);
    var count : Nat = 0;
    
    switch (notificationsByUser.get(caller)) {
      case (?buffer) {
        // Iterate in reverse (newest first)
        let size = buffer.size();
        var idx = size - 1;
        
        while (idx >= 0 and results.size() < limit) {
          let notification = buffer.get(idx);
          if (not unreadOnly or not notification.read) {
            if (count >= offset) {
              results.add(notification);
            };
            count += 1;
          };
          idx -= 1;
        };
      };
      case null {};
    };
    
    Buffer.toArray(results)
  };
  
  // ===========================================================================
  // QUERIES
  // ===========================================================================
  
  public query ({ caller }) func whoAmI() : async ?User {
    users.get(caller)
  };
  
  public query func getOnlineUsers(roomId : ?Nat) : async [User] {
    let currentTime = now();
    let results = Buffer.Buffer<User>(50);
    let onlineThreshold = 300 * 1_000_000_000; // 5 minutes in nanoseconds
    
    for ((_, user) in users.entries()) {
      if (user.banned) continue;
      
      let isOnline = (currentTime - user.lastSeen) < onlineThreshold;
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
    
    Buffer.toArray(results)
  };
  
  public query func getRoomStatistics(roomId : Nat) : async ?{
    room : ChatRoom;
    totalMessages : Nat;
    activeUsers : Nat;
    messagesToday : Nat;
    topPosters : [(Principal, Nat)];
  } {
    switch (chatRooms.get(roomId)) {
      case null null;
      case (?room) {
        let userMessageCounts = HashMap.HashMap<Principal, Nat>(0, Principal.equal, Principal.hash);
        var totalMessages : Nat = 0;
        var messagesToday : Nat = 0;
        let activeUsers = HashMap.HashMap<Principal, Bool>(0, Principal.equal, Principal.hash);
        
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
    "ChatChain v5.1.0"
  };
  
  public query func getSystemHealth() : async {
    canisterId : Principal;
    version : Text;
    uptime : Int;
    userCount : Nat;
    messageCount : Nat;
    roomCount : Nat;
    isHealthy : Bool;
  } {
    {
      canisterId = Principal.fromActor(ChatChain);
      version = "5.1.0";
      uptime = now() - canisterCreatedAt;
      userCount = users.size();
      messageCount = messages.size();
      roomCount = chatRooms.size();
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
      rooms = Iter.toArray(chatRooms.vals());
      timestamp = now();
    })
  };
}























