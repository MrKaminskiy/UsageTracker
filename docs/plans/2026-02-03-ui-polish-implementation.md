# UI Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add subtle depth and shadows to the UI for a polished, native macOS feel.

**Architecture:** Add gradient color pairs to Models.swift, update ProviderRow with card styling and improved progress bars, redesign MenuBarView footer with icon-only buttons.

**Tech Stack:** SwiftUI, macOS 14+

---

## Task 1: Add Gradient Color Pairs to Models

**Files:**
- Modify: `Sources/UsageTracker/Models.swift:15-21`

**Step 1: Add gradient color property to UsageItem**

Replace the existing `color` computed property with a `gradientColors` property that returns a tuple of start/end colors:

```swift
var gradientColors: (start: Color, end: Color) {
    switch percentage {
    case 0..<50:
        return (Color(red: 0.204, green: 0.780, blue: 0.349),  // #34C759
                Color(red: 0.188, green: 0.820, blue: 0.345))  // #30D158
    case 50..<80:
        return (Color(red: 1.0, green: 0.624, blue: 0.039),    // #FF9F0A
                Color(red: 1.0, green: 0.702, blue: 0.251))    // #FFB340
    default:
        return (Color(red: 1.0, green: 0.231, blue: 0.188),    // #FF3B30
                Color(red: 1.0, green: 0.412, blue: 0.380))    // #FF6961
    }
}

var color: Color {
    gradientColors.start
}
```

**Step 2: Build to verify no compile errors**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add Sources/UsageTracker/Models.swift
git commit -m "feat: add gradient color pairs for progress bars"
```

---

## Task 2: Update Progress Bars in ProviderRow

**Files:**
- Modify: `Sources/UsageTracker/Views/ProviderRow.swift:73-109` (UsageItemRow)

**Step 1: Replace the progress bar implementation**

Update the `UsageItemRow` body to use taller, gradient-filled progress bars:

```swift
struct UsageItemRow: View {
    let item: UsageItem

    var body: some View {
        HStack(spacing: 8) {
            Text(item.label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track with inset shadow effect
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                        )

                    // Filled portion with gradient
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [item.gradientColors.start, item.gradientColors.end],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * min(item.percentage / 100, 1))
                        .overlay(
                            // Subtle top highlight
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.25), Color.white.opacity(0)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: geometry.size.width * min(item.percentage / 100, 1))
                        )
                }
            }
            .frame(height: 8)

            Text("\(Int(item.percentage))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .trailing)

            if let resetLabel = item.resetLabel {
                Text(resetLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.leading, 24)
    }
}
```

**Step 2: Build to verify no compile errors**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add Sources/UsageTracker/Views/ProviderRow.swift
git commit -m "feat: update progress bars with gradients and depth"
```

---

## Task 3: Add Card Styling to Provider Rows

**Files:**
- Modify: `Sources/UsageTracker/Views/ProviderRow.swift:1-71` (ProviderRow)

**Step 1: Wrap provider content in a card container**

Update `ProviderRow` to add card styling:

```swift
struct ProviderRow: View {
    @Binding var provider: Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            providerHeader
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            if case .notConnected(let url) = provider.status {
                HStack {
                    Spacer()
                    Button("View Usage") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            } else if provider.isExpanded && !provider.items.isEmpty {
                // Inset content area
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(provider.items) { item in
                        UsageItemRow(item: item)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.03))
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var providerHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                provider.isExpanded.toggle()
            }
        } label: {
            HStack {
                Image(systemName: provider.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 12)

                Image(systemName: provider.icon)
                    .font(.system(size: 12))
                    .foregroundColor(provider.displayColor)

                Text(provider.name)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                switch provider.status {
                case .loading:
                    ProgressView()
                        .scaleEffect(0.6)
                case .notConnected:
                    Text("Not connected")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                case .error(let message):
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .help(message)
                case .loaded:
                    Text("\(Int(provider.maxPercentage))%")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
```

**Step 2: Build to verify no compile errors**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add Sources/UsageTracker/Views/ProviderRow.swift
git commit -m "feat: add card styling to provider rows"
```

---

## Task 4: Update Provider List Spacing in MenuBarView

**Files:**
- Modify: `Sources/UsageTracker/Views/MenuBarView.swift:50-60`

**Step 1: Update providerList to use card spacing instead of dividers**

```swift
private var providerList: some View {
    VStack(alignment: .leading, spacing: 8) {
        ForEach($appState.providers) { $provider in
            ProviderRow(provider: $provider)
        }
    }
}
```

**Step 2: Build to verify no compile errors**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add Sources/UsageTracker/Views/MenuBarView.swift
git commit -m "feat: update provider list spacing for cards"
```

---

## Task 5: Redesign Footer with Icon-Only Buttons

**Files:**
- Modify: `Sources/UsageTracker/Views/MenuBarView.swift:62-99`

**Step 1: Create a reusable icon button style**

Add this above the `MenuBarView` struct:

```swift
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(width: 24, height: 24)
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color.primary.opacity(0.12) : Color.clear)
            )
            .contentShape(Circle())
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
}
```

**Step 2: Replace the footer implementation**

```swift
private var footer: some View {
    HStack {
        Button {
            Task {
                await appState.refresh()
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(appState.isLoading ? 360 : 0))
                .animation(
                    appState.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                    value: appState.isLoading
                )
        }
        .buttonStyle(.icon)
        .disabled(appState.isLoading)

        Spacer()

        if let lastUpdated = appState.lastUpdated {
            Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }

        Spacer()

        SettingsLink {
            Image(systemName: "gear")
        }
        .buttonStyle(.icon)
    }
}
```

**Step 3: Build to verify no compile errors**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build`
Expected: Build succeeded

**Step 4: Commit**

```bash
git add Sources/UsageTracker/Views/MenuBarView.swift
git commit -m "feat: redesign footer with icon-only buttons"
```

---

## Task 6: Add Hover State to Icon Buttons

**Files:**
- Modify: `Sources/UsageTracker/Views/MenuBarView.swift` (IconButtonStyle)

**Step 1: Update IconButtonStyle with hover support**

Replace the `IconButtonStyle` with a hover-aware version:

```swift
struct IconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(width: 24, height: 24)
            .background(
                Circle()
                    .fill(
                        configuration.isPressed ? Color.primary.opacity(0.12) :
                        isHovered ? Color.primary.opacity(0.08) : Color.clear
                    )
            )
            .contentShape(Circle())
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
```

**Step 2: Build to verify no compile errors**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add Sources/UsageTracker/Views/MenuBarView.swift
git commit -m "feat: add hover state to icon buttons"
```

---

## Task 7: Final Build and Test

**Step 1: Clean build**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build`
Expected: Build succeeded

**Step 2: Run the app to visually verify**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift run`
Expected: App launches, menu bar icon appears, clicking shows polished UI with:
- Provider cards with shadows and borders
- Gradient progress bars with depth
- Icon-only footer with hover states

**Step 3: Final commit if any adjustments made**

```bash
git add -A
git commit -m "chore: final UI polish adjustments"
```
