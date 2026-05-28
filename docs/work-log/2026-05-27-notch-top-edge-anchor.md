# 2026-05-27: Notch Top Edge Anchor

## Problem

After the full-width hosted panel refactor, the black bridge no longer suffered from horizontal clipping, but the real MacBook screenshot still showed a gap above the bridge. The bridge was drawn below the navigation/menu bar area instead of touching the top edge.

## Root Cause

The geometry code treated `screenFrame.maxY` as the correct physical top anchor for the hosted panel. On a notched display, the more specific source of the notch/menu-bar top area is `NSScreen.auxiliaryTopLeftArea` and `NSScreen.auxiliaryTopRightArea`.

If those auxiliary areas extend above `screenFrame.maxY`, anchoring the panel to `screenFrame.maxY` leaves the hosted panel too low, creating the visible top gap.

## Changes

- Added `topEdgeY` to `NotchGeometry`.
- For notched displays, `topEdgeY` is computed as:
  - `max(screenFrame.maxY, auxiliaryTopLeftArea.maxY, auxiliaryTopRightArea.maxY)`
- For no-notch fallback, `topEdgeY` remains `screenFrame.maxY`.
- Updated hosted frames:
  - `frames.collapsed.maxY == geometry.topEdgeY`
  - `frames.expanded.maxY == geometry.topEdgeY`
- Updated `notchRegion(...)` to follow `geometry.topEdgeY` so hover detection stays aligned with the visible notch area.

## Tests Added

- `geometryUsesAuxiliaryTopEdgeWhenItExceedsScreenFrame`
- `collapsedTopUsesAuxiliaryTopEdgeWhenItExceedsScreenFrame`
- `expandedTopUsesAuxiliaryTopEdgeWhenItExceedsScreenFrame`

These tests simulate a display where auxiliary top areas end above `screenFrame.maxY`, matching the visual symptom reported from the screenshot.

## Verification

- `swift test`: 97 tests passed.
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`: build succeeded.

## Follow-Up Notes

If the top gap still appears on hardware, the next diagnostic should log the real runtime values of:

- `screen.frame`
- `screen.safeAreaInsets`
- `screen.auxiliaryTopLeftArea`
- `screen.auxiliaryTopRightArea`
- hosted window frame after `setFrame`

That will show whether macOS is clamping the window frame or whether the auxiliary areas still do not represent the real drawable top edge.
