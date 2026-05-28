# 2026-05-28: Notch Host Top Overshoot

## Problem

The black bridge still appeared below the macOS menu bar, leaving a visible empty strip above it. A previous fix introduced `topEdgeY` using the auxiliary top areas, but the real device still showed no visual improvement.

## Root Cause

Runtime behavior indicates that `screenFrame.maxY` and the auxiliary area top edge can still describe the lower boundary of the menu bar/notch area for the purpose of placing this overlay. The remaining gap height visually matches the menu bar height.

The SwiftUI drawing was already at local `y = 0`; the issue was the global `NSPanel` frame. Therefore this iteration changes the host window's top anchor, not SwiftUI padding or drawing offsets.

## Change

Added `NotchGeometryCalculator.hostTopY(for:)`:

```swift
geometry.hasNotch ? geometry.topEdgeY + geometry.menuBarHeight : geometry.topEdgeY
```

Hosted frame placement now uses this value:

- `frames.collapsed.maxY == hostTopY`
- `frames.expanded.maxY == hostTopY`
- `notchRegion` hover detection follows `hostTopY`

No-notch fallback remains unchanged.

## Tests Updated

- `collapsedTopExtendsAboveScreenTopByMenuBarHeightOnNotchedDisplay`
- `expandedTopExtendsAboveScreenTopByMenuBarHeightOnNotchedDisplay`
- `collapsedTopUsesAuxiliaryTopEdgeWhenItExceedsScreenFrame`
- `expandedTopUsesAuxiliaryTopEdgeWhenItExceedsScreenFrame`

The tests now encode the behavior required by the screenshot: hosted panels on notched displays intentionally extend one menu-bar height above the prior top edge.

## Verification

- `swift test`: 97 tests passed.
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`: build succeeded.

## Follow-Up

If the visual gap still remains, the next likely cause is macOS clamping the `NSPanel` frame. The next diagnostic should log before and after `setFrame`:

- requested hosted frame
- actual `win.frame`
- `screen.frame`
- `screen.visibleFrame`
- `screen.safeAreaInsets`
- `screen.auxiliaryTopLeftArea`
- `screen.auxiliaryTopRightArea`

If clamping is confirmed, the next implementation route should move the bridge into a separate menu-bar/status-item backed overlay or use a different window level/collection behavior, instead of further adjusting geometry math.
