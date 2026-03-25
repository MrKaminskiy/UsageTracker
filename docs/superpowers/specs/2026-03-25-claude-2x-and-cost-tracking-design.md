# Claude 2x Usage Indicator & API Cost Tracking

## Overview

Two new features for the Claude provider in UsageTracker:

1. **2x capacity indicator** — show when Anthropic's promotional double-capacity window is active
2. **API cost estimate** — parse local Claude Code session logs to estimate what the usage would cost on the API

## Feature 1: 2x Usage Indicator

### Detection Logic

Time-based detection. No API field exists; Anthropic activates the boost silently.

Rules (all times in US Eastern):
- **Promo window**: configurable start/end dates (current: 2026-03-13 to 2026-03-28)
- **Weekends**: always 2x
- **Weekdays**: 2x when hour < 8 or hour >= 14 ET (peak = 8:00–14:00 ET, no boost)

Implementation: `Sources/UsageTracker/Providers/Claude2xDetector.swift`

```swift
struct Claude2xStatus {
    let isActive: Bool
}

struct Claude2xDetector {
    func currentStatus() -> Claude2xStatus
}
```

### Configuration

Stored in `~/.usagetracker/claude_2x.json`:

```json
{
  "promoStart": "2026-03-13T00:00:00-05:00",
  "promoEnd": "2026-03-28T23:59:59-07:00",
  "peakHoursET": { "start": 8, "end": 14 }
}
```

User can edit this file to update dates for future promos without rebuilding. If the file doesn't exist, no 2x indicator is shown (no promo active).

### UI

Small pill badge in the Claude provider header, next to the name:

```
▼ 🧠 Claude  ⚡2x   6%
```

- Pill: rounded rectangle, accent color (blue/indigo), small font
- Contains "⚡2x" text
- Only visible when 2x is active
- Hidden entirely when not in a promo period or during peak hours

The badge refreshes whenever the provider data refreshes (on the existing timer).

## Feature 2: API Cost Estimate

### Data Source

Parse JSONL session files from `~/.claude/projects/*/*.jsonl` (and nested `subagents/` dirs).

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

### Pricing Table

Hardcoded in source, easily updatable:

| Model pattern | Input $/MTok | Output $/MTok | Cache Write $/MTok | Cache Read $/MTok |
|---|---|---|---|---|
| `opus-4-6` / `opus-4-5` | $15 | $75 | $18.75 | $1.50 |
| `sonnet-4-6` / `sonnet-4-5` | $3 | $15 | $3.75 | $0.30 |
| `haiku-4-5` | $0.80 | $4 | $1.00 | $0.08 |

Unknown models fall back to Sonnet pricing.

### Cost Estimator

Implementation: `Sources/UsageTracker/Providers/ClaudeCostEstimator.swift`

```swift
struct CostEstimate {
    let totalCost: Double          // total $ this month
    let costByModel: [String: Double]  // per-model breakdown
    let tokenCounts: TokenCounts
    let periodStart: Date          // first day of current month
    let periodEnd: Date            // now
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

Logic:
1. Glob all `~/.claude/projects/*/*.jsonl` and `~/.claude/projects/*/subagents/*.jsonl`
2. For each file, check modification date — skip files not modified this month
3. Parse line-by-line, extract entries where `timestamp` is in the current calendar month
4. Sum token counts by model from `usage` blocks in assistant messages
5. Apply pricing table
6. Cache results in `~/.usagetracker/cost_cache.json` keyed by file path + modification date to avoid re-parsing unchanged files on subsequent refreshes

### UI

New row in the Claude provider card, below existing usage rows, separated by a thin divider:

```
  Session       ████░░░░░░   0%    4h 20m
  Weekly        █░░░░░░░░░   6%    3d
  Sonnet        █░░░░░░░░░   2%    6d
  ───────────────────────────────────────
  API cost est.              $47.23 this month
```

- Thin separator line (Divider or custom line) between usage rows and cost row
- Label "API cost est." on the left, aligned with other labels
- Dollar amount right-aligned where percentages normally go
- "this month" in tertiary text where reset labels normally go
- No progress bar for this row

### Integration with ClaudeProvider

`ClaudeProvider.fetchUsage()` will also call `ClaudeCostEstimator.estimateCurrentMonth()` and include the cost in its return value. This requires either:
- Adding an optional `costEstimate` field to the `Provider` model, or
- Adding a special `UsageItem` with a flag indicating it's a cost row (not a percentage bar)

**Chosen approach**: Add an optional `metadata` dict to `Provider` to carry the cost estimate. The `ProviderRow` view checks for this metadata on the Claude provider and renders the cost row accordingly.

```swift
struct Provider {
    // ... existing fields ...
    var metadata: [String: String]  // e.g. ["apiCostEstimate": "47.23"]
}
```

## Files to Create/Modify

### New files
- `Sources/UsageTracker/Providers/Claude2xDetector.swift` — 2x detection logic + config loading
- `Sources/UsageTracker/Providers/ClaudeCostEstimator.swift` — JSONL parsing + cost calculation

### Modified files
- `Sources/UsageTracker/Models.swift` — Add `metadata` dict to `Provider`
- `Sources/UsageTracker/Providers/ClaudeProvider.swift` — Call 2xDetector and CostEstimator, include results in returned Provider
- `Sources/UsageTracker/Views/ProviderRow.swift` — Render 2x badge in header, render cost row with separator

## Edge Cases

- **No JSONL files**: cost shows as $0.00
- **No `claude_2x.json` config**: 2x indicator never shown (safe default)
- **Malformed JSONL lines**: skip silently, continue parsing
- **Unknown model IDs**: fall back to Sonnet pricing
- **Large number of JSONL files**: file-level mod-date filtering + caching keeps it fast
- **Month boundary**: cost resets at the start of each calendar month
