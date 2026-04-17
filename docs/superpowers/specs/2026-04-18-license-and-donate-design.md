# License + Donate Button — Design

**Date:** 2026-04-18
**Status:** Approved

## Goal

Give UsageTracker a proper open-source license and a simple way for users to tip the developer.

## Motivation

- The About tab already links to `LICENSE` on GitHub (`AboutTab.swift:65-67`), but no `LICENSE` file exists in the repo — the link currently 404s.
- No funding mechanism exists. The developer wants to accept voluntary donations via Buy Me a Coffee.

## Scope

Two deliverables:

1. **MIT license** — `LICENSE` file at repo root + short "License" section in `README.md`.
2. **Donate row** — a "Buy me a coffee" link in the About tab of Settings.

Out of scope:
- GitHub Sponsors / `FUNDING.yml` (not using Sponsors).
- Separate "Support" card or prominent button in the main popover (disproportionate for a menu bar utility).
- Any changes to the menu bar icon, popover, or other tabs.

## Design

### 1. LICENSE file

Create `LICENSE` at the repo root containing the standard MIT license text with:

```
Copyright (c) 2026 Kaminskiy Nikita
```

Add a short "License" section to the end of `README.md`:

> Released under the MIT License. See [LICENSE](LICENSE) for details.

The existing About tab link (`AboutTab.swift:65-67`) that points to `github.com/MrKaminskiy/UsageTracker/blob/main/LICENSE` starts working automatically once the file is pushed.

### 2. Donate row in AboutTab

**Location:** `Sources/UsageTracker/Views/Settings/Tabs/AboutTab.swift`, inside the existing `SettingsCard` at lines 56-68. The row is inserted **above** "GitHub repository" (top of the card) to give it light visual priority without introducing a second card.

**Visuals:**
- SF Symbol: `cup.and.saucer.fill`
- Icon color: `.accentColor` (differentiates it from the grey utility icons — subtle, not shouty)
- Label: `"Buy me a coffee"`
- Trailing external-link arrow (same `arrow.up.right.square` as other rows)

**URL handling:**
- Add a single constant at the top of `AboutTab.swift`:
  ```swift
  // TODO: Set Buy Me a Coffee handle before release
  private let buyMeACoffeeURL = "https://buymeacoffee.com/YOUR_HANDLE"
  ```
- The row uses this constant. When the handle is known, it's a one-line edit.

**Reuse:** The row uses the existing `aboutLink(label:icon:urlString:)` helper. The only change to the helper is allowing an optional accent tint for the icon — either via a new parameter with a default (`tint: Color = .secondary`) or by inlining a slightly different row variant. Pick whichever keeps the file cleaner during implementation.

### Resulting card order in About tab

1. Buy me a coffee *(new, accent icon)*
2. GitHub repository
3. Report an issue
4. License

## Files touched

- `LICENSE` *(new)*
- `README.md` *(add License section)*
- `Sources/UsageTracker/Views/Settings/Tabs/AboutTab.swift` *(URL constant + donate row + optional icon tint)*

## Testing / verification

- `swift build` succeeds.
- Manual: open Settings → About. Confirm the "Buy me a coffee" row appears at the top of the card with an accent-colored icon, and clicking it opens the placeholder URL in the browser.
- Manual: confirm the "License" row still links to `…/blob/main/LICENSE` and that file resolves once pushed.

## Risks

- **Placeholder URL ships accidentally.** Mitigated by the `// TODO:` comment and the fact that the constant is at the top of the file, easy to spot in review.
- **Icon tint inconsistency.** Small; confined to one row. The accent color already appears elsewhere in the app (e.g. update-available card), so it's in-keeping.
