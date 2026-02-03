// Popup script for UsageTracker extension

async function updateStatus() {
  const { connected } = await chrome.storage.local.get('connected');
  const dot = document.getElementById('statusDot');
  const text = document.getElementById('statusText');

  if (connected) {
    dot.className = 'dot connected';
    text.textContent = 'Connected to UsageTracker';
  } else {
    dot.className = 'dot disconnected';
    text.textContent = 'UsageTracker not running';
  }
}

updateStatus();
