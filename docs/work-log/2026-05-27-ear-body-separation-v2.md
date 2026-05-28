# 2026-05-27: Ear+Body Separation (v2) — 3-Panel Notch Fusion

## Problem
The previous single-panel approach with SwiftUI GeometryReader-drawn ears failed completely — "完全没有延伸到导航栏". The SwiftUI ear rendering couldn't properly cover the menu bar area.

## Solution: 3-Panel Architecture
Separate the notch overlay into 3 independent NSPanels:

1. **Left Ear Panel** — covers menu bar area left of the notch
2. **Right Ear Panel** — covers menu bar area right of the notch
3. **Body Panel** — thin strip (collapsed) or content area (expanded) below the notch

### Key design decisions:
- Ear panels are pure AppKit (black `NSPanel` with `backgroundColor = .black`, `isOpaque = true`)
- No SwiftUI rendering for ears — avoids the GeometryReader clipping issue
- Global mouse monitor (not tracking area) for notch region hover detection
- `notchRegion()` returns full menu bar width + 20pt below for generous hover target

## Files changed:
- **`NotchHostPanelManager.swift`** — Added `earManager` property, global mouse monitor, ear show/hide in state transitions
- **`NotchCollapsedView.swift`** — Simplified to `Rectangle().fill(Color.black)` (ears are separate panels)
- **`NotchExpandedView.swift`** — Removed GeometryReader ear drawing, kept content-only
- **`NotchHostState.swift`** — Removed `leftFillWidth`/`rightFillWidth` (no longer needed)
- **`NotchGeometryCalculator.swift`** — No changes (already has `leftEar`/`rightEar` in `NotchFrames`)
- **`NotchEarPanelManager.swift`** — No changes (already written)
- **Deleted `NotchCollapsedChrome.swift`** — Dead code referencing removed properties
- **Deleted `CollapsedWidgetIndicator.swift`** — Only used by NotchCollapsedChrome
- **Tests** — Updated for new frame geometry (body no longer includes menu bar height)

## Frame geometry changes:
- **Collapsed**: `height = collapsedBodyHeight` (8pt), `maxY = screen.maxY - menuBarHeight`
- **Expanded**: `height = expandedHeight` (110pt), `maxY = screen.maxY - menuBarHeight`
- **Ears**: `height = menuBarHeight`, positioned at screen top

## Build & test: BUILD SUCCEEDED, 93 tests pass.
