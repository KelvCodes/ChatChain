// Import DFINITY libraries for interacting with canisters and authentication
import { Actor, HttpAgent } from '@dfinity/agent';
import { AuthClient } from '@dfinity/auth-client';
import { idlFactory } from '../../declarations/ChatChain/ChatChain'; // Adjust path based on your project structure

// ================== DOM ELEMENT REFERENCES ==================
const chatWindow = document.getElementById('chatWindow');
const chatForm = document.getElementById('chatForm');
const messageInput = document.getElementById('messageInput');
const userList = document.getElementById('userList');
const settingsBtn = document.getElementById('settingsBtn');
const settingsModal = document.getElementById('settingsModal');

// ================== ICP CONFIGURATION ==================
const canisterId = 'YOUR_CANISTER_ID'; // Replace with your deployed canister ID
const host = 'https://icp-api.io'; // For production; use 'http://127.0.0.1:4943' for local dev
let actor; // Will represent the connection to the backend canister
let authClient; // Internet Identity authentication client
let currentUserPrincipal; // Principal (unique identifier) of the current logged-in user
let currentUserName = 'Anonymous'; // Default username if not logged in
let hasStartedChat = false; // Tracks if a chat session has begun

// ================== INITIALIZE CONNECTION TO ICP ==================
async function initializeICP() {
  // Create AuthClient instance for handling login/authentication
  authClient = await AuthClient.create();
  
  // Check if the user is already authenticated
  if (await authClient.isAuthenticated()) {
    currentUserPrincipal = (await authClient.getIdentity()).getPrincipal();
    await fetchUserName(); // Try to fetch the username if authenticated
  } else {
    currentUserPrincipal = null; // User is anonymous
  }

  // Create an agent to talk to the IC canister
  const agent = new HttpAgent({ host });
  
  // If running locally, fetch the root key for certificate validation
  if (host.includes('127.0.0.1')) {
    await agent.fetchRootKey();
  }

  // Create actor (connection object) for interacting with canister methods
  actor = Actor.createActor(idlFactory, { agent, canisterId });

  // Launch the app after initializing ICP
  initializeApp();
}

// ================== FETCH CURRENT USER'S NAME ==================
async function fetchUserName() {
  const users = await actor.getUsers();
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


