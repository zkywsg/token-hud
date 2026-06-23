# Overlay Service Refresh Buttons

Date: 2026-06-20

## Context

The floating overlay previously only displayed data already loaded by `StateWatcher`.
Manual refresh lived mainly in Settings, so users had no lightweight way to refresh the
service currently being viewed in the HUD.

The requested behavior is service-level refresh from the floating HUD, without making
the HUD trigger repeated Keychain authorization dialogs.

## Decision

Add small icon-only refresh buttons only where the overlay has a stable service row or
service title:

- `GroupedOverlayView`: service name area.
- `SectionedOverlayView`: current service title.
- `CompactOverlayContent`: no button for now because compact mode has no stable service
  row and the space is too constrained.

Supported service ids:

- `codex`
- `deepseek`
- `minimax`
- `mimo`

Unsupported or intentionally hidden for now:

- `claude`
- `openai`
- `anthropic`
- `gemini`

The button uses silent refresh:

- Codex calls `CodexFetcher.fetch(allowUserInteraction: false)`.
- API platforms call `APIPlatformFetcher.fetchSingle(platform:allowUserInteraction: false)`.
- After completion, the overlay calls `StateWatcher.readNow()` to reload `state.json`.

This keeps the HUD responsive and avoids using the floating overlay as a place that can
spawn Keychain authorization prompts. If a platform needs credential authorization, the
user should still handle that from Settings.

## Implementation Notes

- `NotchHostPanelManager` now receives `CodexFetcher` and `APIPlatformFetcher` from
  `AppDelegate` and injects them into `NotchHostRootView` via SwiftUI environment.
- `OverlayServiceRefreshButton` is defined next to grouped overlay code because grouped
  and sectioned overlay views both need the same small HUD control.
- The button guards against concurrent clicks with local `isRefreshing` state and shows
  a compact `ProgressView` while refresh is in flight.

## Verification

- `swift test --filter KeychainAccessPolicy`
- `swift test --filter NotchSurfacePolicy`
- `swift test`
- `git diff --check`
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`

All automatic checks passed on 2026-06-20. Manual HUD interaction is still needed to
confirm real credential/network refresh behavior on the user's machine.
