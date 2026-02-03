// Content script for ChatGPT usage extraction

(function() {
  'use strict';

  const PROVIDER_ID = 'chatgpt';

  // Extract usage data from ChatGPT settings page
  function extractUsageData() {
    // ChatGPT shows usage in settings > subscription
    // This selector may need updating as ChatGPT changes their UI
    const usageElements = document.querySelectorAll('[data-testid="usage-bar"], .usage-indicator');

    if (usageElements.length === 0) {
      // Try alternative: look for text containing usage info
      const allText = document.body.innerText;
      const usageMatch = allText.match(/(\d+)\s*\/\s*(\d+)\s*(messages|requests)/i);

      if (usageMatch) {
        return {
          providerId: PROVIDER_ID,
          items: [{
            label: usageMatch[3] || 'Requests',
            current: parseFloat(usageMatch[1]),
            limit: parseFloat(usageMatch[2]),
            resetLabel: null
          }],
          timestamp: Date.now() / 1000
        };
      }
      return null;
    }

    const items = [];
    usageElements.forEach(el => {
      const label = el.getAttribute('aria-label') || 'Usage';
      const value = el.getAttribute('aria-valuenow') || '0';
      const max = el.getAttribute('aria-valuemax') || '100';

      items.push({
        label: label,
        current: parseFloat(value),
        limit: parseFloat(max),
        resetLabel: null
      });
    });

    return {
      providerId: PROVIDER_ID,
      items: items,
      timestamp: Date.now() / 1000
    };
  }

  // Send data to background script
  function sendUsageData() {
    const data = extractUsageData();
    if (data && data.items.length > 0) {
      chrome.runtime.sendMessage({ type: 'USAGE_DATA', data: data });
    }
  }

  // Run extraction when page is ready and periodically
  if (document.readyState === 'complete') {
    sendUsageData();
  } else {
    window.addEventListener('load', sendUsageData);
  }

  // Re-extract every 60 seconds while page is open
  setInterval(sendUsageData, 60000);

  // Also extract when user navigates within the SPA
  let lastUrl = location.href;
  new MutationObserver(() => {
    if (location.href !== lastUrl) {
      lastUrl = location.href;
      setTimeout(sendUsageData, 1000); // Wait for content to load
    }
  }).observe(document.body, { subtree: true, childList: true });
})();
