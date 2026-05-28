# 2026-05-28: Notch Frame Diagnostics

## Background

After multiple geometry adjustments, the notch bridge still rendered below the macOS menu bar. The likely issue is no longer a simple y-offset error. The implementation needs to determine whether macOS is clamping the `NSPanel` frame or whether the app is still requesting the wrong frame.

## Change

Added diagnostic logging in `NotchHostPanelManager`.

Every hosted frame transition now logs `[NotchDiagnostics]` around frame placement:

- restore hosted collapsed
- animate collapsed
- animate expanded
- screen parameter changed collapsed
- detached frame restore/default paths

Each log includes:

- requested frame
- actual `win.frame`
- `screen.frame`
- `screen.visibleFrame`
- `screen.safeAreaInsets`
- `screen.auxiliaryTopLeftArea`
- `screen.auxiliaryTopRightArea`
- `NotchGeometry`
- window level
- collection behavior raw value

## Purpose

The next real-device run should answer the key question:

- If requested frame is above the menu bar but actual frame is lower, macOS/WindowServer is clamping the panel. The main-panel route should stop.
- If requested and actual frame match but visual placement is still wrong, the coordinate model is still wrong.

## Verification

- `swift test`: 97 tests passed.
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`: build succeeded.

## Next Step

Run the app from Xcode, reproduce the notch hover/collapsed state, then search the Xcode console for `[NotchDiagnostics]`. Use those logs to decide whether to implement a separate menu-bar layer or continue fixing geometry.
