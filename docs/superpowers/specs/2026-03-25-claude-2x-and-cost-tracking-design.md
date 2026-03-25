# Claude 2x Usage Indicator & API Cost Tracking

## Overview

Two new features for the Claude provider in UsageTracker:

1. **2x capacity indicator** — show when Anthropic's promotional double-capacity window is active
2. **API cost estimate** — parse local Claude Code session logs to estimate what the usage would cost on the API

## Feature 1: 2x Usage Indicator

### Detection Logic

Time-based detection. No API field exists; Anthropic activates the boost silently.

Rules (all times in US Eastern):
- **Promo window**: configurable start/end dates. All rules below only apply when the current time is within the promo window. Outside the window, 2x is never active.
- **Weekends**: always 2x (during promo window)
- **Weekdays**: 2x when hour < 8 or hour >= 14 ET (peak = 8:00–14:00 ET, no boost)

Implementation: `Sources/UsageTracker/Providers/Claude2xDetector.swift`

```swift
struct Claude2xDetector {
    /// Returns nil if no promo config exists or current date is outside promo window.
    /// Returns true/false based on time-of-day rules when within a promo window.
    func check() -> Bool?
}
```

Returning `nil` means "no promo configured" — the UI hides the badge entirely. Returning `false` means "promo active but currently peak hours" — the UI can still hide the badge (same visual result, but the caller has the distinction if needed later).

### Configuration

Stored in `~/.usagetracker/claude_2x.json`:

```json
{
  "promoStart": "2026-03-13T00:00:00-05:00",
  "promoEnd": "2026-03-29T03:59:59-04:00",
  "peakHoursET": { "start": 8, "end": 14 }
}
```

Note: Late March is after DST switchover (March 8, 2026), so Eastern Daylight Time (EDT = UTC-04:00) applies. Both start and end timestamps must use the correct UTC offset for their respective dates (EST = -05:00 before March 8, EDT = -04:00 after).

User can edit this file to update dates for future promos without rebuilding. If the file doesn't exist, no 2x indicator is shown (no promo active).

### UI

Small pill badge in the Claude provider header, next to the name:

```
▼ 🧠 Claude  ⚡2x   6%
```

- Pill: rounded rectangle, accent color (blue/indigo), small font
- Contains "⚡2x" text
- Only visible when `check()` returns `true`
- Hidden when `check()` returns `nil` (no promo) or `false` (peak hours)

The badge refreshes whenever the provider data refreshes (on the existing timer).

## Feature 2: API Cost Estimate

### Data Source

Parse JSONL session files from `~/.claude/projects/` recursively (`**/*.jsonl`).

Each assistant message in these files contains:

```json
{
  "message": {
    "model": "claude-opus-4-6",
    "usage": {
      "input_tokens": 1,
      "output_tokens": 8,
      "cache_creation_input_tokens": 555,
      "cache_read_input_tokens": 42242
    }
  },
  "timestamp": "2026-03-25T14:56:07.802Z"
}
```

Note: The existing `extra_usage` field in the usage API (with `used_credits` and `monthly_limit`) tracks pay-as-you-go spend reported by Anthropic. The JSONL-based estimate complements this by covering all token usage across all models, regardless of billing tier, answering "what would this cost on the API?"

### Pricing Table

Hardcoded in source, easily updatable. Model matching uses **case-insensitive substring** on the `model` field (e.g., model `"claude-opus-4-6"` matches pattern `"opus-4-6"`). First match wins in the order listed:

| Model pattern | Input $/MTok | Output $/MTok | Cache Write $/MTok | Cache Read $/MTok |
|---|---|---|---|---|
| `opus-4-6` / `opus-4-5` | $15 | $75 | $18.75 | $1.50 |
| `sonnet-4-6` / `sonnet-4-5` | $3 | $15 | $3.75 | $0.30 |
| `haiku-4-5` | $0.80 | $4 | $1.00 | $0.08 |

Unknown models fall back to Sonnet pricing.

### Cost Estimator

Implementation: `Sources/UsageTracker/Providers/ClaudeCostEstimator.swift`

```swift
struct CostEstimate: Equatable {
    let totalCost: Double
    let periodStart: Date
    let periodEnd: Date
}

struct TokenCounts {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheWriteTokens: Int = 0
    var cacheReadTokens: Int = 0
}

actor ClaudeCostEstimator {
    func estimateCurrentMonth() async -> CostEstimate
}
```

**Lifetime**: `ClaudeCostEstimator` is instantiated once as a stored property of `ClaudeProvider` (same pattern as other dependencies). The actor's in-memory state persists across refreshes, and the file-based cache (`~/.usagetracker/cost_cache.json`) provides persistence across app restarts.

Logic:
1. Recursively find all `*.jsonl` files under `~/.claude/projects/`
2. For each file, check modification date — skip files not modified this month
3. Check file-level cache: if file path + modification date match a cached entry, use cached token counts
4. Otherwise parse line-by-line, extract entries where `timestamp` is in the current calendar month
5. Sum token counts by model from `usage` blocks in assistant messages
6. Apply pricing table
7. Update cache file

### UI

New row in the Claude provider card, below existing usage rows, separated by a thin divider:

```
  Session       ████░░░░░░   0%    4h 20m
  Weekly        █░░░░░░░░░   6%    3d
  Sonnet        █░░░░░░░░░   2%    6d
  ───────────────────────────────────────
  API cost est.              $47.23 this month
```

The cost row is a **custom HStack** (not a `UsageItemRow`), since it has no progress bar:
- Left: label "API cost est." with leading padding matching `UsageItemRow` alignment (padded to account for the green dot + label area)
- Center: empty (no bar)
- Right: dollar amount in monospaced font + "this month" in tertiary text
- The dollar amount column is wider than the percentage column to accommodate values like `$1,234.56`

If `~/.claude/projects/` is unreadable or the estimator encounters a directory-level error, the cost row is hidden (same as no data).

### Integration with ClaudeProvider

Add a typed optional field to `Provider`:

```swift
struct Provider {
    // ... existing fields ...
    var costEstimate: Double? = nil  // API cost estimate in dollars
}
```

`ClaudeProvider` holds a `ClaudeCostEstimator` instance and calls `estimateCurrentMonth()` during `fetchUsage()`. The result populates `costEstimate`. `ProviderRow` checks `provider.costEstimate` and renders the cost row when non-nil.

## Files to Create/Modify

### New files
- `Sources/UsageTracker/Providers/Claude2xDetector.swift` — 2x detection logic + config loading
- `Sources/UsageTracker/Providers/ClaudeCostEstimator.swift` — JSONL parsing + cost calculation

### Modified files
- `Sources/UsageTracker/Models.swift` — Add `costEstimate: Double?` to `Provider`
- `Sources/UsageTracker/Providers/ClaudeProvider.swift` — Instantiate 2xDetector and CostEstimator, include results in returned Provider
- `Sources/UsageTracker/Views/ProviderRow.swift` — Render 2x badge in header, render cost row with separator

## Edge Cases

- **No JSONL files**: cost shows as $0.00
- **No `claude_2x.json` config**: 2x indicator never shown (safe default)
- **Malformed JSONL lines**: skip silently, continue parsing
- **Unknown model IDs**: fall back to Sonnet pricing
- **Large number of JSONL files**: file-level mod-date filtering + per-file caching keeps it fast
- **Month boundary**: cost resets at the start of each calendar month
- **Unreadable `~/.claude/projects/`**: cost row hidden entirely
- **Cost estimator errors**: non-fatal, cost row hidden, usage rows still display normally
