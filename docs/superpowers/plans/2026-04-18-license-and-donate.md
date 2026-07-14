# License + Donate Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an MIT LICENSE to the repo and a "Buy me a coffee" donate row in the Settings → About tab.

**Architecture:** Drop a standard MIT `LICENSE` at the repo root and append a short License section to `README.md`. In `AboutTab.swift`, add a constant for the donate URL (placeholder handle), extend the existing `aboutLink(...)` helper with an optional icon tint, and insert a new "Buy me a coffee" row at the top of the existing `SettingsCard`.

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-04-18-license-and-donate-design.md`

---

## File Structure

- **Create:** `LICENSE` — MIT license text, root of repo.
- **Modify:** `README.md` — append a "License" section at the end.
- **Modify:** `Sources/UsageTracker/Views/Settings/Tabs/AboutTab.swift` — add URL constant, extend `aboutLink` with a tint parameter, insert donate row at the top of the card.

No test files. This is UI + static file work; verification is `swift build` + manual About-tab check.

---

### Task 1: Add MIT LICENSE file

**Files:**
- Create: `LICENSE`

- [ ] **Step 1: Create the LICENSE file with standard MIT text**

Write `LICENSE` at the repo root with exactly this content:

```
MIT License

Copyright (c) 2026 Kaminskiy Nikita

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Verify the file was created**

Run: `ls LICENSE && head -3 LICENSE`
Expected: `LICENSE` listed, first three lines showing `MIT License`, blank, `Copyright (c) 2026 Kaminskiy Nikita`.

- [ ] **Step 3: Commit**

```bash
git add LICENSE
git commit -m "$(cat <<'EOF'
docs: add MIT LICENSE

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Add License section to README

**Files:**
- Modify: `README.md` (append at end)

- [ ] **Step 1: Check the current end of README.md**

Run: `tail -5 README.md`
Expected: Read the last lines so the new section is appended cleanly with a blank line above it.

- [ ] **Step 2: Append the License section**

Append this content to the end of `README.md` (include a blank line before the `## License` heading if the file doesn't already end with one):

```markdown
## License

Released under the MIT License. See [LICENSE](LICENSE) for details.
```

- [ ] **Step 3: Verify**

Run: `tail -4 README.md`
Expected: Output ends with the new `## License` section and its body.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs(readme): add License section

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Add donate URL constant and extend `aboutLink` helper

**Files:**
- Modify: `Sources/UsageTracker/Views/Settings/Tabs/AboutTab.swift`

- [ ] **Step 1: Add the donate URL constant**

At the top of `AboutTab.swift`, immediately after the `import AppKit` line, insert:

```swift
// TODO: Set Buy Me a Coffee handle before release
private let buyMeACoffeeURL = "https://buymeacoffee.com/YOUR_HANDLE"
```

The resulting top of the file should look like:

```swift
// Sources/UsageTracker/Views/Settings/Tabs/AboutTab.swift
import SwiftUI
import AppKit

// TODO: Set Buy Me a Coffee handle before release
private let buyMeACoffeeURL = "https://buymeacoffee.com/YOUR_HANDLE"

struct AboutTab: View {
```

- [ ] **Step 2: Extend `aboutLink` with an optional tint parameter**

Replace the existing `aboutLink(label:icon:urlString:)` function (currently at `AboutTab.swift:82-100`) with this version that accepts a `tint` color defaulting to `.secondary`:

```swift
    private func aboutLink(label: String, icon: String, urlString: String, tint: Color = .secondary) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 12))
            Spacer()
            if let url = URL(string: urlString) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .settingsRowPadding()
    }
```

The only changes from the original:
- Add `tint: Color = .secondary` parameter.
- Change `.foregroundStyle(.secondary)` on the icon to `.foregroundStyle(tint)`.

All existing callers (lines 57-67) continue to work unchanged because `tint` has a default.

- [ ] **Step 3: Verify build still compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` with no errors. Existing `aboutLink` call sites work because the new parameter has a default.

- [ ] **Step 4: Commit**

```bash
git add Sources/UsageTracker/Views/Settings/Tabs/AboutTab.swift
git commit -m "$(cat <<'EOF'
refactor(settings): add donate URL constant and tint param to aboutLink

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Add "Buy me a coffee" row at the top of the About card

**Files:**
- Modify: `Sources/UsageTracker/Views/Settings/Tabs/AboutTab.swift`

- [ ] **Step 1: Insert the donate row at the top of the SettingsCard**

Locate the existing `SettingsCard` block in `AboutTab.swift` (currently at lines 56-68 — three `aboutLink` rows separated by `SettingsCardDivider()`):

```swift
                SettingsCard {
                    aboutLink(label: "GitHub repository",
                              icon: "chevron.left.forwardslash.chevron.right",
                              urlString: "https://github.com/MrKaminskiy/UsageTracker")
                    SettingsCardDivider()
                    aboutLink(label: "Report an issue",
                              icon: "exclamationmark.bubble",
                              urlString: "https://github.com/MrKaminskiy/UsageTracker/issues")
                    SettingsCardDivider()
                    aboutLink(label: "License",
                              icon: "doc.text",
                              urlString: "https://github.com/MrKaminskiy/UsageTracker/blob/main/LICENSE")
                }
```

Replace it with:

```swift
                SettingsCard {
                    aboutLink(label: "Buy me a coffee",
                              icon: "cup.and.saucer.fill",
                              urlString: buyMeACoffeeURL,
                              tint: .accentColor)
                    SettingsCardDivider()
                    aboutLink(label: "GitHub repository",
                              icon: "chevron.left.forwardslash.chevron.right",
                              urlString: "https://github.com/MrKaminskiy/UsageTracker")
                    SettingsCardDivider()
                    aboutLink(label: "Report an issue",
                              icon: "exclamationmark.bubble",
                              urlString: "https://github.com/MrKaminskiy/UsageTracker/issues")
                    SettingsCardDivider()
                    aboutLink(label: "License",
                              icon: "doc.text",
                              urlString: "https://github.com/MrKaminskiy/UsageTracker/blob/main/LICENSE")
                }
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` with no errors.

- [ ] **Step 3: Manual verification**

Run the app:

```bash
.build/debug/UsageTracker &
```

Then:
- Right-click the menu bar icon → Settings → About tab.
- Confirm the first row reads "Buy me a coffee" with an accent-colored `cup.and.saucer.fill` icon.
- Confirm the arrow button opens `https://buymeacoffee.com/YOUR_HANDLE` in the browser (will 404 — that's expected until the handle is set).
- Confirm the remaining rows ("GitHub repository", "Report an issue", "License") still appear and link correctly.
- Confirm the "License" row now resolves to the real `LICENSE` file on GitHub once pushed (can verify locally by checking `ls LICENSE` at repo root).

Kill the app: bring UsageTracker to the foreground and Quit, or `kill %1`.

If the UI looks wrong, return to Task 3 or Task 4 and fix — do not proceed until the visual check passes.

- [ ] **Step 4: Commit**

```bash
git add Sources/UsageTracker/Views/Settings/Tabs/AboutTab.swift
git commit -m "$(cat <<'EOF'
feat(settings): add Buy me a coffee row to About tab

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Post-implementation follow-ups (not part of this plan)

- Replace `YOUR_HANDLE` in `buyMeACoffeeURL` with the real Buy Me a Coffee handle once the account is set up.
- Push `LICENSE` to `main` so the existing About-tab "License" link resolves.
