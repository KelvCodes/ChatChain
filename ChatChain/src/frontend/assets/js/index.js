ait actor.getUsers();
  for (const [principal, name] of users) {
    if (principal.toString() === currentUserPrincipal.toString()) {
      currentUserName = name;
      break;
    }
  }
}

// ================== INITIALIZE APP ==================
function initializeApp() {
  populateUserList(); // Show list of registered users
  setupEventListeners(); // Setup UI interaction events
  pollMessages(); // Start polling for new messages
  addWelcomeMessages(); // Show welcome message in chat window
}

// ================== POPULATE USER LIST FROM CANISTER ==================
async function populateUserList() {
  const users = await actor.getUsers();
  userList.innerHTML = ''; // Clear current list
  
  users.forEach(([principal, name]) => {
    const li = document.createElement('li');
    li.innerHTML = `
      <div class="user-avatar">${name[0]}</div> <!-- First letter as avatar -->
      <span>${name}</span>
      <div class="user-status" style="background: #10b981"></div> <!-- Green dot for online -->
    `;
    
    // When user is clicked, start chat
    li.addEventListener('click', () => startChatWith(name));
    userList.appendChild(li);
  });
}

// ================== SETUP EVENT LISTENERS ==================
function setupEventListeners() {
  chatForm.addEventListener('submit', handleMessageSend); // Handle send button
  settingsBtn.addEventListener('click', openSettings); // Open settings modal
  settingsModal.addEventListener('click', (e) => {
    if (e.target === settingsModal) {
      closeSettings(); // Close modal if clicked outside content
    }
  });

  // Dynamically add Login button to settings modal
  const modalContent = settingsModal.querySelector('.modal-content');
  const loginButton = document.createElement('button');
  loginButton.innerText = 'Login with Internet Identity';
  loginButton.style = 'margin-top: 1rem; padding: 0.5rem 1rem; background: #10b981; color: white; border: none; border-radius: 5px; cursor: pointer;';
  loginButton.addEventListener('click', handleLogin);
  modalContent.appendChild(loginButton);
}

// ================== HANDLE INTERNET IDENTITY LOGIN ==================
async function handleLogin() {
  await authClient.login({
    identityProvider: 'https://identity.ic0.app', // Official II provider
    onSuccess: async () => {
      currentUserPrincipal = (await authClient.getIdentity()).getPrincipal();
      
      // Prompt the user for a username after login
      const name = prompt('Enter your username:');
      if (name) {
        const success = await actor.registerUser(name);
        if (success) {
          currentUserName = name;
          await populateUserList(); // Refresh user list
          closeSettings();
        } else {
          alert('Username already taken or already registered.');
        }
      }
    }
  });
}

// ================== START CHAT WITH A USER ==================
function startChatWith(userName) {
  if (!hasStartedChat) {
    chatWindow.innerHTML = ''; // Clear chat window if first chat
    hasStartedChat = true;
  }
  addMessage('system', `Started conversation with ${userName}`, true);
}

// ================== HANDLE MESSAGE SENDING ==================
async function handleMessageSend(e) {
  e.preventDefault(); // Prevent page refresh
  
  const message = messageInput.value.trim();
  if (message === '') return; // Skip empty messages

  if (!hasStartedChat) {
    chatWindow.innerHTML = '';
    hasStartedChat = true;
  }

  // Send message to ICP canister
  await actor.sendMessage(message);

  // Add my message to the chat UI
  addMessage(currentUserName, message);

  // Clear input box
  messageInput.value = '';
}

// ================== ADD MESSAGE TO CHAT WINDOW ==================
function addMessage(sender, text, isSystem = false) {
  const messageDiv = document.createElement('div');
  messageDiv.classList.add('message');
  
  if (isSystem) {
    // System messages (like notifications)
    messageDiv.innerHTML = `
      <div style="text-align: center; color: #64748b; font-style: italic; padding: 1rem;">
        ${text}
      </div>
    `;
  } else {
    // Chat messages from users
    const isSentByMe = sender === currentUserName;
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




































