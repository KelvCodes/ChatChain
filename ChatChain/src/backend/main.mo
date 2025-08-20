
 An array of messages sent on or after the given timestamp
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

















































































































