# OpenRouter Provider Design

## Overview
Add OpenRouter usage tracking to the menu bar app, showing credit spending via the `/api/v1/key` endpoint.

## Provider Details
- **ID:** `"openrouter"`
- **Name:** `"OpenRouter"`
- **Icon:** `"arrow.trianglehead.branch"`
- **API Key prefix:** `sk-or-`
- **Config file:** `~/.usagetracker/openrouter.json`
- **Setup URL:** `https://openrouter.ai/settings/keys`

## API
- **Endpoint:** `GET https://openrouter.ai/api/v1/key`
- **Auth:** `Authorization: Bearer {apiKey}`
- **Response fields used:** `usage_monthly`, `usage_daily`, `limit`, `limit_remaining`

## Usage Items

With credit limit set (`limit` non-null):
- "Monthly Spend" — bar showing `usage_monthly / limit`, resetLabel `"$X.XX / $Y.YY"`
- "Daily Spend" — resetLabel `"$X.XX today"`

Without credit limit (`limit` null):
- "Monthly Spend" — no bar (current=0, limit=0), resetLabel `"$X.XX"`
- "Daily Spend" — resetLabel `"$X.XX today"`

## Settings UI
- Enable/disable toggle
- API key input with `sk-or-` prefix validation
- Validation via `GET /api/v1/key` (200 = valid)

## Files to Change
1. **New:** `Sources/UsageTracker/Providers/OpenRouterProvider.swift`
2. **Edit:** `Sources/UsageTracker/Models.swift` — default provider order/enabled
3. **Edit:** `Sources/UsageTracker/App.swift` — register provider
4. **Edit:** `Sources/UsageTracker/Views/SettingsView.swift` — settings UI + validation
