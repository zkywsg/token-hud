# Hosted Surface State Boundary

Date: 2026-06-23

## Context

The hosted notch HUD repeatedly showed expanded card fragments on launch and clipped content after re-expanding. Earlier fixes adjusted card width and height, but the latest screenshots showed a deeper state-boundary issue.

## Root Cause

- The hosted overlay window uses the expanded surface frame even when visually collapsed.
- The visible collapsed/expanded state depends on `hostState.expansionProgress`.
- Restore, layout-input changes, screen changes, and AppKit resize callbacks can all reassert the expanded frame.
- `windowDidResize(_:)` previously treated any hosted resize as a detach signal, which was too broad for system reflow and frame reassertion.
- `NotchHostedSurfaceView.bodyPanel` constructed expanded content even when the collapsed body height/opacity was near zero, relying only on clipping and opacity to hide it.

This combination allowed one-frame or persistent mismatches: hosted mode could be collapsed logically but still show expanded card fragments, or expanded content could be clipped because the body height estimate was too low.

## Fix

- Added `NotchHostedResizePolicy`:
  - ignore resize while the manager is resetting hosted frame;
  - reassert hosted frame for non-drag hosted resize/reflow;
  - detach only during an active expanded drag.
- Added `NotchHostedBodyPresentationPolicy` to prevent expanded content construction while body height or opacity is too low.
- Added `enterHostedCollapsed(...)` in `NotchHostPanelManager` and routed hosted restore/toggle paths through it.
- Updated `windowDidResize(_:)` to use the new resize policy.
- Updated `NotchExpandedLayoutPolicy` to account for widget content rows as well as service card rows, so 3 services / 7 widgets no longer gets a two-row body estimate.

## Verification

- `swift test --filter NotchSurfacePolicy --filter NotchExpandedLayoutPolicy`: passed, 35 tests.
- `swift test`: passed, 176 tests.
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`: passed.
- `git diff --check`: passed.

Manual verification still matters because the bug is a real hosted-window visual state issue.
