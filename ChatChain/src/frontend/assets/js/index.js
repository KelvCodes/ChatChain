ue;
  }
  addMessage('system', `Started conversation with ${userName}`, true);
}

// Handle message sending
async function handleMessageSend(e) {
  e.preventDefault();
  const message = messageInput.value.trim();
  if (message === '') return;

  if (!hasStartedChat) {
    chatWindow.innerHTML = '';
    hasStartedChat = true;
  }

  // Send message to canister
  await actor.sendMessage(message);
  addMessage(currentUserName, message);
  messageInput.value = '';
}

// Add message to chat
function addMessage(sender, text, isSystem = false) {
  const messageDiv = document.createElement('div');
  messageDiv.classList.add('message');
  
  if (isSystem) {
    messageDiv.innerHTML = `
      <div style="text-align: center; color: #64748b; font-style: italic; padding: 1rem;">
        ${text}
      </div>
    `;
  } else {
    const isSentByMe = sender === currentUserName;
    messageDiv.classList.add(isSentByMe ? 'me' : 'them');
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

// Poll messages from canister
async function pollMessages() {
  let lastTimestamp = 0;
  setInterval(async () => {
    const newMessages = await actor.getMessagesSince(lastTimestamp);
    for (const msg of newMessages) {
      // Find username for sender
      const users = await actor.getUsers();
      let senderName = 'Anonymous';
      for (const [principal, name] of users) {
        if (principal.toString() === msg.sender.toString()) {
          senderName = name;
          break;
        }
      }
      addMessage(senderName, msg.content);
      lastTimestamp = Number(msg.timestamp);
    }
  }, 5000); // Poll every 5 seconds
}

// Scroll to bottom
function scrollToBottom() {
  chatWindow.scrollTop = chatWindow.scrollHeight;
}

// Settings modal functions
function openSettings() {
  settingsModal.style.display = 'block';
}

function closeSettings() {
  settingsModal.style.display = 'none';
}

// Add welcome messages
function addWelcomeMessages() {
  setTimeout(() => {
    addMessage('System', 'Welcome to ChatChain! Click on a user to start chatting.', true);
  }, 1000);
}

// Initialize the app
document.addEventListener('DOMContentLoaded', () => {
  initializeICP();
});

// Auto-focus message input
messageInput.addEventListener('blur', () => {
  setTimeout(() => messageInput.focus(), 100);
});

// Enter key handling
messageInput.addEventListener('keypress', (e) => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    chatForm.dispatchEvent(new Event('submit'));
  }

});
































































