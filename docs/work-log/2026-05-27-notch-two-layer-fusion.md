# 2026-05-27: Notch Two-Layer Fusion

## Background

The previous notch fusion implementation still looked detached from the MacBook notch. The panel did not visually extend into the top menu bar areas beside the notch. User feedback clarified that the design must be split into two visual parts:

1. The menu bar region beside the notch.
2. The body below the notch.

The animation should feel like the notch expands outward first, then opens downward, and collapses in the reverse order.

## Root Cause

The active implementation used a single `NSPanel`, but `NotchGeometryCalculator.notchFrames()` still sized that hosted panel to `notchGapWidth + 40`. `NotchEarView` then tried to draw the left and right menu-bar ears inside that narrow panel. The drawing was clipped by the panel bounds, so it could never reach the real menu bar areas beside the notch.

This differed from the previous plan that described a multi-panel ear/body architecture. The shipped code was effectively a narrow single-panel implementation.

## Key Changes

- Updated `NotchGeometryCalculator.notchFrames()`:
  - On notched displays, hosted collapsed and expanded frames now span `screenFrame.width`.
  - The hosted frame top remains aligned to `screenFrame.maxY`, so the panel reaches the top menu bar area.
  - No-notch fallback remains centered and narrow.
- Added `NotchFusionLayout` and `notchFusionLayout(...)`:
  - Computes local drawing rects for `leftBridge`, `rightBridge`, and `body`.
  - Separates menu bar bridge geometry from body geometry.
  - Uses `expansionProgress` with a bridge-first phase and body-second phase.
- Added `NotchFusionView`:
  - Draws only the visible black bridge/body shapes inside the transparent full-width panel.
  - Keeps the physical notch gap transparent and places widget content only in the body below the menu bar.
  - Replaces separate collapsed/expanded hosted views from `NotchHostRootView`.
- Updated `NotchHostState` and `NotchHostPanelManager`:
  - Stores `screenFrame` for local/global geometry conversion.
  - Tracks `expansionProgress`.
  - Sets hosted progress to `0` for collapsed and `1` for expanded.
- Updated the Xcode project to include `NotchFusionView.swift`.

## Tests Added

- `collapsedHostFrameSpansFullScreenWidthOnNotchedDisplay`
- `expandedHostFrameSpansFullScreenWidthOnNotchedDisplay`
- `fusionLayoutPlacesBridgeInMenuBarAndBodyBelowIt`
- `fusionLayoutExpandsBridgeBeforeBodyContent`

These tests guard against the original clipping bug and verify that the bridge/body geometry stays separated.

## Verification

- `swift test`: 94 tests passed.
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`: build succeeded.

## Follow-Up Notes

- The bridge currently expands to a capped width near the notch, not the full menu bar width. This avoids covering too much of the system menu bar while still giving the notch a wider anchored area.
- Real MacBook visual tuning is still needed for exact values such as bridge max width, black opacity, and spring timing.
- If pure black still looks detached from the system menu bar, the next iteration should test an `NSVisualEffectView` or a calibrated translucent material behind the bridge/body.
