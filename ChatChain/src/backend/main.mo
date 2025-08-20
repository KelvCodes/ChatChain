
  /// @param content The message text content
  publ.caller;
      content = content;
      timestamp = Time.now();
    };

    // Add to buffer and persist to stable variable
    messageBuffer.add(newMessage);
    messages := messageBuffer.toArray();
  };

  /// Retrieves all messages.
  public query func getMessages(): async [Message] {
    messages;
  };

  /// Retrieves messages sent since a specific timestamp.
  ///
  /// @param timestamp The earliest time to retrieve messages from
  /// @return An array of messages sent on or after the given timestamp
  public query func getMessagesSince(timestamp: Time.Time): async [Message] {
    Array.filter(
      messages,
      func(msg: Message): Bool {
        msg.timestamp >= timestamp
      }
    )
  };

  // -------------------------------
  // UTILITY FUNCTIONS
  // -------------------------------

  /// Clears all messages (for testing or admin use).
  public func clearMessages(): async () {
    messageBuffer.clear();
    messages := [];
  };
};











































































































