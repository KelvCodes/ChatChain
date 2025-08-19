

// DOM Elements
const chatWindow = document.getElementById('chatWindow');
const chatForm = document.getElementById('chatForm');
const messageInput = document.getElementById('messageInput');
const userList = document.getElementById('userList');
const settingsBtn = document.getElementById('settingsBtn');
const settingsModal = document.getElementById('settingsModal');

// ICP Configuration
const canisterId = 'YOUR_CANISTER_ID'; // Replace with your deployed canister ID
const host = 'https://icp-api.io'; // Use 'http://127.0.0.1:4943' for local development
let actor;
let authClient;
let currentUserPrincipal;
let currentUserName = 'Anonymous';
let hasStartedChat = false;

// Initialize ICP connection
async function initializeICP() {
  // Create AuthClient for Internet Identity
  authClient = await AuthClient.create();
  
  // Check if user is authenticated
  if (await authClient.isAuthenticated()) {
    currentUserPrincipal = (await authClient.getIdentity()).getPrincipal();
    await fetchUserName();
  } else {
    currentUserPrincipal = null; // Anonymous
  }

  // Initialize agent and actor
  const agent = new HttpAgent({ host });
  // For local development, fetch canister IDs
  if (host.includes('127.0.0.1')) {
    await agent.fetchRootKey();
  }
  actor = Actor.createActor(idlFactory, { agent, canisterId });

  // Initialize app
  initializeApp();
}

// Fetch current user's name
async function fetchUserName() {
  const users = await actor.getUsers();
  for (const [principal, name] of users) {
    if (principal.toString() === currentUserPrincipal.toString()) {
      currentUserName = name;
      break;
    }
  }
}

// Initialize app
function initializeApp() {
  populateUserList();
  setupEventListeners();
  pollMessages();
  addWelcomeMessages();
}

// Populate user list from canister
async function populateUserList() {
  const users = await actor.getUsers();
  userList.innerHTML = '';
  users.forEach(([principal, name]) => {
    const li = document.createElement('li');
    li.innerHTML = `
      <div class="user-avatar">${name[0]}</div>
      <span>${name}</span>
      <div class="user-status" style="background: #10b981"></div>
    `;
    li.addEventListener('click', () => startChatWith(name));
    userList.appendChild(li);
  });
}

// Setup event listeners
function setupEventListeners() {
  chatForm.addEventListener('submit', handleMessageSend);
  settingsBtn.addEventListener('click', openSettings);
  settingsModal.addEventListener('click', (e) => {
    if (e.target === settingsModal) {
      closeSettings();
    }
  });

  // Add login button to settings modal
  const modalContent = settingsModal.querySelector('.modal-content');
  const loginButton = document.createElement('button');
  loginButton.innerText = 'Login with Internet Identity';
  loginButton.style = 'margin-top: 1rem; padding: 0.5rem 1rem; background: #10b981; color: white; border: none; border-radius: 5px; cursor: pointer;';
  loginButton.addEventListener('click', handleLogin);
  modalContent.appendChild(loginButton);
}

// Handle Internet Identity login
async function handleLogin() {
  await authClient.login({
    identityProvider: 'https://identity.ic0.app',
    onSuccess: async () => {
      currentUserPrincipal = (await authClient.getIdentity()).getPrincipal();
      // Prompt for username
      const name = prompt('Enter your username:');
      if (name) {
        const success = await actor.registerUser(name);
        if (success) {
          currentUserName = name;
          await populateUserList();
          closeSettings();
        } else {
          alert('Username already taken or already registered.');
        }
      }
    }
  });
}

// Start chat with user
function startChatWith(userName) {
  if (!hasStartedChat) {
    chatWindow.innerHTML = '';
    hasStartedChat = true;
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







