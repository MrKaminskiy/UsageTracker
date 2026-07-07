# Claude Usage Insights & Popover Polish — Design

**Date:** 2026-07-07
**Status:** Approved by user (sections 1–3)

## Goal

Bring the data from Claude Code's `/usage` screen into UsageTracker: extra usage
credits, local usage insights (context-size and subagent warnings), skills and
subagent breakdowns, and daily aggregate stats — presented in a new Claude
drill-in detail page. Alongside it, a set of small polish fixes to the existing
popover.

## Scope decisions (user-confirmed)

- All four data categories: extra credits, usage insights, skills/subagents
  breakdown, session stats.
- Session stats reinterpreted as a **today aggregate** (since local midnight,
  across all sessions), not a single-session view.
- Placement: **drill-in detail page** inside the popover (not inline expansion,
  not a separate window).
- Design revision: **polish + integrate** — keep the current card/bar structure.
- Architecture: **unified analyzer** (Approach A) — one incremental-cached pass
  over transcripts produces cost estimate and all insights at refresh time.

## Architecture

### ClaudeInsightsAnalyzer (new actor, absorbs ClaudeCostEstimator)

One pass over `~/.claude/projects/**/*.jsonl` per refresh cycle. Per-file
in-memory cache keyed by `(path, mtime, size)`: unchanged files return their
cached per-file summary and are never re-parsed. This also makes the existing
monthly cost estimate incremental (today it re-reads every file each refresh).

Output:

```swift
struct ClaudeInsights: Equatable, Sendable {
    var monthlyCost: Double?              // existing cost estimate (current month)
    var contextShareOver150k: Double?     // % of last-24h tokens from requests with >150k context
    var subagentShare: Double?            // % of last-24h tokens from subagent-heavy sessions
    var skills: [UsageShare]              // top 5 skills, % of last-24h tokens
    var subagents: [UsageShare]           // top 5 subagent types, % of last-24h tokens
    var today: TodayStats                 // since local midnight
}

struct UsageShare: Equatable, Sendable {
    var name: String
    var share: Double                     // 0–100
}

struct TodayStats: Equatable, Sendable {
    var cost: Double                      // estimated, existing pricing tables
    var sessionCount: Int
    var totalTokens: Int
    var linesAdded: Int
    var linesRemoved: Int
}
```

### Metric definitions (all approximate, computed from local transcripts)

- **Context >150k share**: per-request context size = `input_tokens +
  cache_read_input_tokens + cache_creation_input_tokens`. Metric = share of
  total last-24h tokens from requests whose context exceeds 150k.
- **Subagent-heavy share**: requests with `isSidechain: true` are subagent
  requests. A session is subagent-heavy when >25% of its tokens are sidechain
  tokens. Metric = those sessions' token share of all last-24h tokens.
- **Skills**: `tool_use` blocks invoking the `Skill` tool. Attribution: tokens
  from the invocation to the end of that user turn belong to the skill.
- **Subagents**: sidechain tokens grouped by the spawning `Task`/`Agent` tool
  call's `subagent_type`; sidechains that can't be matched go into "other".
- **Today stats**: sessions/tokens/cost since local midnight; lines
  added/removed parsed from `Edit`/`Write` tool results where present.

The UI labels all of this "approximate · local sessions on this Mac",
mirroring Claude Code's own disclaimer.

### Insight thresholds

Warning insights render only when meaningful:

- Context insight: shown when `contextShareOver150k >= 40`.
- Subagent insight: shown when `subagentShare >= 30`.

Below thresholds the section shows one quiet line:
`✓ No usage warnings — last 24h looks efficient`.

### Extra usage credits (API-side, no analyzer involvement)

`ClaudeProvider` already decodes `extra_usage`. When `is_enabled == true`,
append a fifth `UsageItem`: label "Extra credits", `current = used_credits`,
`limit = monthly_limit`, value text rendered as `$used of $limit` instead of a
percentage.

## UI

### Navigation

`MenuBarView` gains a two-screen state enum (`.list`, `.claudeDetail`) with a
horizontal slide transition and animated popover height. The enum is generic
enough to add other providers' detail pages later, but only Claude gets one now.

Entry: a `chevron.right.circle` button on the right side of the Claude card
header, revealed on card hover (matches the existing `UsageItemRow` hover
idiom). Header click still toggles expand/collapse. Exit: `← Claude` back
button or Esc.

### Claude detail page (340pt wide)

Top to bottom:

1. **Header**: back button, Claude icon + name, plan badge from
   `subscriptionType` (e.g. "Max 20x").
2. **Limit bars**: Session / Weekly / Sonnet / Opus, slightly larger than the
   main list, each with an **absolute** reset time ("resets 4:40 PM",
   "resets Sat 11 PM") — the detail page has room for real times where the main
   list uses compact relative labels.
3. **Extra credits bar** (only if enabled): `$used of $limit`.
4. **Insights · last 24h · approx.**: each insight is one bold stat line plus
   one muted single-line hint (e.g. "/compact mid-task, /clear between tasks").
   Amber warning icon. Quiet all-clear line when below thresholds.
5. **Top skills / Top agents**: two compact columns, top 5 each, `% of usage`.
   Names truncate with hover tooltips. Section hidden entirely when nothing was
   used in 24h.
6. **Today**: `$4.12 est · 6 sessions` / `1.2M tokens · +296 / −6 lines`.
7. **Footer link**: "Open claude.ai usage ↗" → https://claude.ai/settings/usage.

Sections whose data is unavailable (no `~/.claude/projects`, no parseable
transcripts) hide rather than showing zeros.

## Popover polish (main list)

1. Fix width mismatch: `NSPopover.contentSize` (320) vs `MenuBarView` frame
   (340); popover sizes itself from SwiftUI content.
2. Amber `⚠` badge next to "Claude" in the main list whenever any insight
   crosses its threshold — the glanceable bridge to the detail page.
3. `.monospacedDigit()` on all numeric text (header %, reset labels) to stop
   horizontal jitter on refresh.
4. When an item's bar is in the red band, its percentage label takes the same
   red instead of secondary gray.
5. Threshold tuning: bar colors become green <60, amber 60–85, red >85
   (currently 50/80).
6. Row label column widens 80 → 92pt so "Extra credits" fits.
7. Drill-in chevron is hover-revealed on the Claude card.

## Error handling

- Analyzer degrades per-file: unreadable/malformed files are skipped and never
  poison the whole `ClaudeInsights`. Malformed lines within a file are skipped
  (existing estimator behavior).
- If nothing is parseable, insight/skills/today sections hide — same treatment
  as Claude Code not being installed.
- Extra credits inherit ClaudeProvider's existing network error handling.
- Analyzer runs off the main actor; a slow first scan never blocks the popover.

## Testing

Unit tests with fixture `.jsonl` files under `Tests/`:

- Context-share math (requests straddling the 150k boundary).
- Sidechain attribution and the 25% subagent-heavy session rule.
- Skill turn-scoped attribution.
- Today boundary: midnight rollover, local timezone.
- Cache invalidation: file mtime/size change re-parses; unchanged file doesn't.
- Malformed-line and malformed-file skipping.
- Insight threshold visibility logic (40% / 30% cutoffs, all-clear state).
- Existing cost-estimator tests must keep passing against the refactored
  analyzer.

UI is verified manually via the running app (popover drill-in, hover
affordances, badge visibility).

## Out of scope

- Persistent history / trends / sparklines (Approach C — possible later on top
  of the analyzer).
- Detail pages for other providers (navigation supports it; not built now).
- Any change to the menu bar icon itself.
