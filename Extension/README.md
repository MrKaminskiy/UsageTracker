# UsageTracker Browser Extension

This extension sends usage data from web-based AI services to the UsageTracker menu bar app.

## Supported Services

- ChatGPT (chatgpt.com)
- More coming soon...

## Installation

### Chrome / Brave / Edge

1. Open `chrome://extensions/` (or `brave://extensions/`, `edge://extensions/`)
2. Enable "Developer mode" (toggle in top right)
3. Click "Load unpacked"
4. Select the `Extension` folder from this project

### Firefox (coming soon)

Firefox support requires a different manifest format.

## How It Works

1. The extension runs content scripts on supported AI service websites
2. It extracts usage information from the page
3. Data is sent to `localhost:19284` where UsageTracker listens
4. The menu bar app displays the aggregated usage

## Privacy

- All data stays on your machine
- No data is sent to any external servers
- The extension only reads from pages you visit

## Troubleshooting

**"UsageTracker not running"**
- Make sure the UsageTracker app is running
- Check that port 19284 is not blocked by firewall

**Usage not updating**
- Visit the service's usage/settings page to trigger extraction
- Some services only show usage in specific sections
