// Content script for Suno usage extraction

(function() {
  'use strict';

  const PROVIDER_ID = 'suno';

  // Extract usage data from Suno
  function extractUsageData() {
    // Suno shows credits in the UI - look for credit indicators
    // Common patterns: "X credits", "X / Y credits", progress bars

    const allText = document.body.innerText;

    // Try to find credit count patterns
    // Pattern 1: "X credits remaining" or "X credits left"
    let match = allText.match(/(\d+)\s*credits?\s*(remaining|left)/i);
    if (match) {
      const remaining = parseFloat(match[1]);
      // Estimate total based on common plans (50 free, 2500 pro, 10000 premier)
      const total = remaining > 2500 ? 10000 : (remaining > 50 ? 2500 : 50);
      const used = total - remaining;
      return {
        providerId: PROVIDER_ID,
        items: [{
          label: 'Credits',
          current: (used / total) * 100,
          limit: 100,
          resetLabel: null
        }],
        timestamp: Date.now() / 1000
      };
    }

    // Pattern 2: "X / Y credits" or "X of Y"
    match = allText.match(/(\d+)\s*(?:\/|of)\s*(\d+)\s*credits?/i);
    if (match) {
      const used = parseFloat(match[1]);
      const total = parseFloat(match[2]);
      if (total > 0) {
        return {
          providerId: PROVIDER_ID,
          items: [{
            label: 'Credits',
            current: (used / total) * 100,
            limit: 100,
            resetLabel: null
          }],
          timestamp: Date.now() / 1000
        };
      }
    }

    // Pattern 3: Look for elements with credit-related classes/attributes
    const creditElements = document.querySelectorAll('[class*="credit"], [data-credits], [aria-label*="credit"]');
    for (const el of creditElements) {
      const text = el.textContent || el.getAttribute('aria-label') || '';
      const numMatch = text.match(/(\d+)/);
      if (numMatch) {
        const value = parseFloat(numMatch[1]);
        // If it looks like a credit count
        if (value > 0 && value <= 10000) {
          return {
            providerId: PROVIDER_ID,
            items: [{
              label: 'Credits',
              current: value,
              limit: 100,
              resetLabel: null
            }],
            timestamp: Date.now() / 1000
          };
        }
      }
    }

    return null;
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
      setTimeout(sendUsageData, 1000);
    }
  }).observe(document.body, { subtree: true, childList: true });
})();
