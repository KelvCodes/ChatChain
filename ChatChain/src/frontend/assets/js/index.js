 = document.createElement('div');
  messageDiv.classList.add('message');
  
  if (isSystem) {
    // System messages ByMe = sender === currentUserName;
    messageDiv.classList.add(isSentByMe ? 'me' : 'them');

    // Add timestamp
    const time = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    messageDiv.innerHTML = `
      ${!isSentByMe ? `<div class="message-sender">${sender}</div>` : ''}
      <div class="message-content">${text}</div>
      <div class="message-time">${time}</div>
    `;
  }

  chatWindow.appendChild(messageDiv);
  scrollToBottom();
}

// ================== POLL MESSAGES FROM CANISTER ==================
async function pollMessages() {
  let lastTimestamp = 0; // Keep track of last seen message
  setInterval(async () => {
    const newMessages = await actor.getMessagesSince(lastTimestamp);
    
    for (const msg of newMessages) {
      // Match sender principal to username
      const users = await actor.getUsers();
      let senderName = 'Anonymous';
      for (const [principal, name] of users) {
        if (principal.toString() === msg.sender.toString()) {
          senderName = name;
          break;
        }
      }

      // Display incoming message
      addMessage(senderName, msg.content);
      lastTimestamp = Number(msg.timestamp); // Update last seen timestamp
    }
  }, 5000); // Poll every 5 seconds
}

// ================== SCROLL CHAT TO BOTTOM ==================
function scrollToBottom() {
  chatWindow.scrollTop = chatWindow.scrollHeight;
}

// ================== SETTINGS MODAL FUNCTIONS ==================
function openSettings() {
  settingsModal.style.display = 'block';
}

function closeSettings() {
  settingsModal.style.display = 'none';
}

// ================== ADD WELCOME MESSAGE ==================
function addWelcomeMessages() {
  setTimeout(() => {
    addMessage('System', 'Welcome to ChatChain! Click on a user to start chatting.', true);
  }, 1000);
}

// ================== APP ENTRY POINT ==================
document.addEventListener('DOMContentLoaded', () => {
  initializeICP(); // Start app once DOM is loaded
});

// ================== UX ENHANCEMENTS ==================
// Keep message input focused
messageInput.addEventListener('blur', () => {
  setTimeout(() => messageInput.focus(), 100);
});

// Press Enter to send message (Shift+Enter for new line)
messageInput.addEventListener('keypress', (e) => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    chatForm.dispatchEvent(new Event('submit'));
  }
});











































































