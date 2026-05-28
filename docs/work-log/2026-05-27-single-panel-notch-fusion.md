# 2026-05-27: Single Full-Width Panel — Notch Fusion

## Problem
The 3-panel approach (separate ear panels) failed — ear panels didn't render in the menu bar area. "仍然在导航栏的下方，没有进入到导航栏".

## Root Cause
The body panel was positioned at `screen.maxY - menuBarHeight` (bottom of menu bar), not at `screen.maxY` (screen top). Separate ear panels at `.screenSaver` level were created but likely didn't render visibly above the menu bar due to macOS restrictions.

## Solution: Single Full-Width Panel with SwiftUI Ears
Switch to a single panel that covers the ENTIRE notch region (ears + body), with SwiftUI drawing the ears inside it:

1. **Panel frame**: extends from `screen.maxY - menuBarHeight - bodyHeight` to `screen.maxY`
   - Panel top = screen top → SwiftUI ears render IN the menu bar area
2. **SwiftUI VStack**: body content at top, ear rectangles at bottom
   - Body: thin strip (collapsed) or content area (expanded)
   - Ears: black rectangles flanking the notch gap, drawn via `NotchEarView`

### Why this works:
- The panel's top edge is at `screen.maxY` (the physical top of the screen)
- SwiftUI's VStack places the body first, then the ears below
- The ears occupy the bottom `menuBarHeight` of the panel → exactly the menu bar area
- The gap between ears is transparent (clear background) → camera shows through
- `isOpaque = false` + `backgroundColor = .clear` → transparent outside drawn areas

## Files changed:
- **`NotchGeometryCalculator.swift`** — Panel frame now at `screen.maxY`; removed `leftEar`/`rightEar` from `NotchFrames`
- **`NotchHostPanelManager.swift`** — Removed `NotchEarPanelManager`; single panel approach
- **`NotchCollapsedView.swift`** — VStack: body strip + NotchEarView
- **`NotchExpandedView.swift`** — VStack: content body + NotchEarView
- **`NotchEarView.swift`** (new) — Shared ear drawing component: HStack with left/right black rectangles + transparent gap
- **Deleted `NotchEarPanelManager.swift`** — No longer needed
- **Tests** — Updated for new frame geometry (panel includes menu bar height)

## Frame geometry:
- `collapsed.maxY = screen.maxY` (panel top at screen top)
- `collapsed.height = menuBarHeight + collapsedBodyHeight` (ears + body)
- `expanded.maxY = screen.maxY`
- `expanded.height = menuBarHeight + expandedHeight`

## Build: SUCCEEDED. Tests: 90/90 pass.
