# UI Polish Design

**Goal:** Transform the plain, basic UI into a polished, native macOS feel with subtle depth and shadows.

**Direction:** Subtle depth through soft shadows, layered surfaces, and gentle gradients. Think native macOS apps - refined but not flashy.

---

## Color System

### Surface Hierarchy
- **Base:** Popup background (slightly elevated from desktop)
- **Cards:** Provider sections on subtle card surfaces with soft shadows
- **Elements:** Progress bars and interactive elements with micro-depth

### Progress Bar Gradients
| State | From | To |
|-------|------|-----|
| Green (0-50%) | `#34C759` | `#30D158` |
| Yellow (50-80%) | `#FF9F0A` | `#FFB340` |
| Red (80%+) | `#FF3B30` | `#FF6961` |

---

## Provider Cards

Each provider becomes a card with subtle elevation instead of flat rows with dividers.

### Styling
- Corner radius: 8pt
- Shadow: `shadow(color: .black.opacity(0.08), radius: 3, y: 1)`
- Border: `Color.primary.opacity(0.06)`, 1pt
- Background: Slight tint to lift off base

### Expanded State
Content area is slightly inset with its own subtle background, creating visual hierarchy between header and details.

```
┌─────────────────────────────────────────┐
│  ▼  🧠  Claude                     27%  │  ← Header row
│  ┌───────────────────────────────────┐  │
│  │  Session      ████░░░░░░░   42%   │  │  ← Inset content area
│  │  All models   ██░░░░░░░░░   27%   │  │
│  │  Weekly       █░░░░░░░░░░    8%   │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

---

## Progress Bars

### Changes from Current
- Height: 8px (up from 6px)
- Corner radius: 4pt (fully rounded ends)
- Fill: Linear gradient using color pairs above
- Track: Inner shadow effect with `Color.primary.opacity(0.06)`
- Filled portion: Subtle top highlight

### Animation
Smooth width transitions using existing `.easeInOut` timing.

---

## Footer Redesign

### Current
Horizontal row: `Refresh | Updated 2 min ago | Settings | Quit`

### New Design
```
┌─────────────────────────────────────────┐
│  ↻      Updated 2 minutes ago       ⚙︎  │
└─────────────────────────────────────────┘
```

### Changes
- **Remove Quit button** - Redundant (right-click menu bar or Cmd+Q)
- **Icon-only buttons** for Refresh (left) and Settings (right)
- **Centered timestamp** - Given room to breathe
- **Circular hover states** on icon buttons

### Button Styling
- Hit area: 24x24pt
- Icon size: 12pt
- Hover: Circular background `Color.primary.opacity(0.08)`
- Refresh: Spins during loading

---

## Files to Modify

1. `Views/ProviderRow.swift` - Card styling, inset content area, progress bar updates
2. `Views/MenuBarView.swift` - Footer redesign, remove quit, card container styling
3. `Models.swift` - Add gradient color pairs to UsageItem

---

## Out of Scope

- Menu bar icon changes
- Settings window changes
- Empty state changes (can be polished later)
