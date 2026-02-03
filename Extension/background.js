// Background service worker for UsageTracker extension

const SERVER_URL = 'http://localhost:19284';

// Send usage data to native app
async function sendToApp(data) {
  try {
    const response = await fetch(SERVER_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    });
    return response.ok;
  } catch (error) {
    console.error('UsageTracker: Failed to send data', error);
    return false;
  }
}

// Listen for messages from content scripts
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'USAGE_DATA') {
    sendToApp(message.data).then(success => {
      sendResponse({ success });
    });
    return true; // Keep channel open for async response
  }
});

// Check server connection periodically
async function checkConnection() {
  try {
    const response = await fetch(SERVER_URL, { method: 'OPTIONS' });
    await chrome.storage.local.set({ connected: response.ok });
  } catch {
    await chrome.storage.local.set({ connected: false });
  }
}

// Check connection every 30 seconds
setInterval(checkConnection, 30000);
checkConnection();
