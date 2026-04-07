# Design: Stabilize and Ship UsageTracker

**Date:** 2026-04-07  
**Status:** Approved

## Overview

Prepare UsageTracker for public release through three parallel tracks: stabilization (tests, audits, bug fixes), packaging (Makefile, code signing), and documentation (README).

Phase 4 (social/distribution) is out of scope — handled by the user.

---

## Core Features (must work before shipping)

1. **Session/Weekly utilization bars** — Claude quota usage fetched via OAuth API
2. **Cost estimate** — monthly spend parsed from `~/.claude/projects/*.jsonl`
3. **Provider auto-detection** — Claude, Cursor, Codex connect without configuration

---

## Phase 1: Stabilization

### 1.1 Resolve outstanding Git issues

- Resolve merge conflict in `Info.plist`
- Review and commit unstaged changes in `App.swift` and `ClaudeProvider.swift`

### 1.2 Update CLAUDE.md

Add to the existing file:
- Provider status table (tested / experimental / hidden)
- Definition of Done checklist (3 core features passing)
- Known issues section

### 1.3 Test harness

Existing tests cover `parseLine` and `costForTokens` in isolation. Gaps to fill:

- **File-level integration tests**: write temp `.jsonl` files with known content, point `estimateCurrentMonth()` at a temp directory, assert total cost matches expectation
- **Multi-file scenarios**: multiple projects, mixed months, overlapping date ranges
- **Edge cases**: empty files, all-malformed lines, unknown models, cache invalidation when file mod date changes

Tests use the Swift Testing framework (`@Test`, `#expect`) already in use.

### 1.4 Provider audit

For each API-key provider, read the source, run with real credentials where possible, and document behavior.

**Decision matrix:**
| Provider | Action |
|----------|--------|
| OpenAI | Audit + test (admin key = org spend; project key = daily usage) |
| ElevenLabs | Audit + test (character quota) |
| OpenRouter | Audit + test (credit balance) |
| Cursor | Keep as-is (auto-detected, tested) |
| Codex | Keep as-is (auto-detected, tested) |
| Runway | Hide by default; mark "not tested" in README |
| Stability | Hide by default; mark "not tested" in README |

"Hide by default" = provider is disabled in the default `AppConfig.enabledProviders` and shown with a disclaimer in Settings if manually re-enabled.

### 1.5 Refresh interval

Change default `refreshIntervalMinutes` from `10` to `5` in `Models.swift`.

### 1.6 Password prompts (keychain)

Root cause: `ClaudeProvider` reads from `"Claude Code-credentials"` — a keychain item created by the Claude Code CLI. macOS prompts because a different app is accessing it. Without code signing, the app identity is unstable across builds so "Always Allow" doesn't stick.

Fix: code signing (Phase 2) gives the app a stable identity. Once signed, user clicks "Always Allow" once and is never prompted again. No code change needed in Phase 1 — document as a known limitation until Phase 2 is complete.

---

## Phase 2: Packaging

### 2.1 Makefile

Add `Makefile` at repo root with targets:

```makefile
build    # swift build -c release
test     # swift test
sign     # invoke release script signing step
dmg      # build DMG
release  # full pipeline: build → sign → notarize → DMG
```

The existing `release.sh` stays as-is; Makefile provides standard entry points.

### 2.2 Release script audit

Review `release.sh` for:
- Hardcoded paths that break on fresh checkout
- Missing prerequisites (certificates, notarization credentials)
- Document required env vars / setup steps in CLAUDE.md

### 2.3 Code signing

Sign with Developer ID Application certificate. Notarize via `notarytool`. Staple ticket to DMG. Once signed, keychain "Always Allow" becomes persistent (fixes password prompt issue from 1.6).

### 2.4 GitHub Releases process

Manual flow (no CI):
1. `make release` locally
2. Tag: `git tag v0.x.0`
3. `git push --tags`
4. Create GitHub Release, attach DMG

Document steps in CLAUDE.md under a "Releasing" section.

---

## Phase 3: README

### Structure

```
# UsageTracker

<one-liner pitch>

<screenshot/GIF — placeholder until recorded>

## Install
## What It Shows
## Providers
## Build from Source
## Known Limitations
```

### Content decisions

- **Pitch**: "See your Claude Code usage limits in your macOS menu bar, live"
- **Install**: DMG download + `xattr -cr ~/Applications/UsageTracker.app` Gatekeeper workaround (for unsigned builds); signed builds need no workaround
- **Requirements**: macOS 13+, Claude Code CLI installed and logged in
- **Providers table**: lists each provider, what it shows, how to connect
  - Claude: auto-detected (Session %, Weekly %, Sonnet %, Opus %, cost estimate)
  - Cursor / Codex: auto-detected
  - OpenAI / ElevenLabs / OpenRouter: API key required, experimental
  - Runway / Stability: not tested, hidden by default
- **Known limitations**: filled after provider audit completes
- **No architecture section**

---

## Parallel execution plan

| Stream | Work | Dependency |
|--------|------|------------|
| A | Phase 1: Git cleanup → tests → provider audit → refresh fix | None |
| B | Phase 2: Makefile → release script audit → signing | None |
| C | Phase 3: README skeleton (all sections except Known Limitations) | None |
| — | Fill Known Limitations in README | Stream A audit complete |
| — | Sign + notarize | Stream B complete |

---

## Definition of Done

- [ ] Merge conflict resolved, repo clean
- [ ] `swift test` passes with new file-level integration tests
- [ ] Session % and Weekly % display correctly for a logged-in Claude account
- [ ] Cost estimate shows for current month
- [ ] Cursor and Codex auto-detect on a machine where they're installed
- [ ] OpenAI, ElevenLabs, OpenRouter: behavior documented (works or known-broken)
- [ ] Runway and Stability hidden by default
- [ ] Default refresh interval is 5 minutes
- [ ] `make build` and `make release` work from a fresh checkout
- [ ] App signed and notarized
- [ ] README complete with all sections
