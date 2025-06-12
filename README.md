
# ChatChain

**ChatChain** is a decentralized chat application built on the Internet Computer (ICP), leveraging blockchain technology to provide a secure, scalable, and serverless messaging platform. The app features a modern, responsive user interface with real-time messaging, user authentication via Internet Identity, and persistent message storage in a Motoko canister.

---

## 🚀 Features

- **Decentralized Messaging**: Send and receive messages stored securely on the ICP blockchain.
- **User Authentication**: Register and authenticate users via Internet Identity.
- **Responsive UI**: A sleek, gradient-styled interface with a user list, chat window, and settings modal.
- **Real-Time Updates**: Polls for new messages every 5 seconds to keep conversations fresh.
- **Scalable Backend**: Uses a Motoko canister for persistent storage of users and messages.
- **Open Source**: Built with vanilla JavaScript, HTML, CSS, and Motoko for easy customization.

---

## 🔧 Prerequisites

Ensure the following are installed:

- **DFX SDK** (v0.15.0 or later):  
  ```bash
  sh -ci "$(curl -fsSL https://smartcontracts.org/install.sh)"


* **Node.js**: Version 16 or later – [Download](https://nodejs.org)
* **npm**: Comes with Node.js
* **Git**: For cloning the repo
* **Internet Identity**: Use [https://identity.ic0.app](https://identity.ic0.app) or deploy a local instance

---

## 📁 Project Structure

```
ChatChain/
├── src/
│   ├── frontend/
│   │   ├── assets/
│   │   │   ├── css/
│   │   │   │   └── styles.css
│   │   │   └── js/
│   │   │       └── index.js
│   │   ├── index.html
│   │   └── declarations/
│   │       └── ChatChain/
│   │           ├── ChatChain.d.ts
│   │           └── ChatChain.js
│   ├── backend/
│   │   ├── main.mo
│   │   └── canister_ids.json
├── dfx.json
├── package.json
├── webpack.config.js
└── README.md
```

---

## ⚙️ Setup Instructions

### 1. Clone the Repository

```bash
git clone <repository-url>
cd ChatChain
```

### 2. Install Dependencies

```bash
npm install
```

### 3. Start Local ICP Replica

```bash
dfx start --background
```

### 4. Deploy Canisters

```bash
dfx deploy
```

This generates `canister_ids.json` and frontend declarations.

### 5. Update Canister ID

In `src/frontend/assets/js/index.js`, replace:

```js
const canisterId = 'YOUR_CANISTER_ID';
```

with your actual backend canister ID (e.g., `'ryjl3-tyaaa-aaaaa-aaaba-cai'`).

---

## 🧪 Run the Frontend

```bash
npm start
```

Visit [http://localhost:9000](http://localhost:9000) in your browser.

---

## 🧪 Test the App

1. Open the app in a browser.
2. Click the gear icon to log in using Internet Identity.
3. Enter a username to register.
4. Choose a user from the list to start a chat.
5. Send messages! They are stored in the canister and polled every 5 seconds.

---

## 🚢 Deployment to ICP Mainnet

### 1. Deploy to Mainnet

```bash
dfx deploy --network ic
```

### 2. Update Canister ID & Host

Update `index.js`:

```js
const canisterId = 'YOUR_ic_CANISTER_ID';
const host = 'https://icp-api.io';
```

### 3. Access the App

Visit:

```
https://<ChatChain_frontend_id>.icp0.io
```

Or host the frontend statically (e.g., on Vercel) and point it to the backend.

---

## 🛠 Development Notes

### Internet Identity

Use [https://identity.ic0.app](https://identity.ic0.app) for auth. For local testing:

```bash
dfx deploy internet_identity --network local
```

Update `index.js` with the local Identity canister ID.

### Regenerate Canister Bindings

After modifying `main.mo`:

```bash
dfx generate ChatChain_backend
```

### Frontend Bundling

Webpack outputs to `dist/`. Ensure `webpack.config.js` includes `declarations/`.

### Local Testing

Set:

```js
const host = 'http://127.0.0.1:4943';
```

To reset local:

```bash
dfx start --clean --background
```

---

## 🔄 Extending Functionality

* **Private Messaging**: Include recipient Principals in message types.
* **Message Deletion/Pagination**: Add for scalability.
* **File Uploads**: Store metadata (large files may need multiple canisters).

---

## 📦 Dependencies

### Backend

* **Motoko** (via DFX)
* **Internet Computer SDK (DFX)**

### Frontend

* `@dfinity/agent` – Canister interactions
* `@dfinity/auth-client` – Internet Identity authentication
* `@dfinity/identity` – Principal management
* `webpack`, `webpack-cli`, `webpack-dev-server` – Bundling
* `html-webpack-plugin`, `css-loader`, `style-loader`, `copy-webpack-plugin` – Webpack setup
* `font-awesome` – Icons (via CDN)

Install all with:

```bash
npm install
```

---

## ⚠️ Known Limitations

* **Polling Delay**: Not fully real-time. Explore PubSub when available.
* **Static Online Status**: Users always appear "online." Improve via real-time tracking.
* **Memory Storage**: All messages stored in-memory. Add pagination or archiving for production.
* **Anonymous Messages**: Unregistered users can message. Enforce auth in `registerUser`.

---

## 🤝 Contributing

Contributions are welcome!

```bash
# Fork the repo
git checkout -b feature/your-feature
# Make changes
git commit -m 'Add your feature'
git push origin feature/your-feature
```

Then, open a **Pull Request** on GitHub.

---

## 📄 License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.

---

## 📬 Contact

For questions or support, open an issue or reach out to the maintainers.

```


