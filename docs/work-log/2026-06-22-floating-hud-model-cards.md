# Floating HUD Model Cards

Date: 2026-06-22

## Context

The selected floating HUD visual direction is B: Model Cards. The goal is to keep the pure black HUD surface while replacing dense service rows with compact service/model cards.

## Decisions

- Grouped overlay is the primary card-based layout.
- Sectioned overlay uses the same card shell for the active service.
- Compact overlay remains compact and only aligns spacing.
- Refresh remains service-level and silent from the HUD.
- `OverlayModelCard` accepts a header accessory instead of owning refresh behavior directly, keeping the card helper visual-only.
- No data model, fetcher, Keychain, notch geometry, or drag behavior changes.

## Implementation Notes

- `OverlayModelCardStyle.swift` owns local spacing, padding, card shell, and widget flow helpers.
- `GroupedOverlayView` renders one service card per service, preserving widget order.
- `SectionedOverlayView` keeps service tabs and renders the active service as one card.
- `CompactOverlayContent` keeps its horizontal compact structure.
- The Xcode project was regenerated so the new helper file is part of the app target.

## Verification

Final verification passed after implementation and documentation updates:

- `swift test --filter NotchSurfacePolicy`: passed, 25 tests.
- `swift test`: passed, 169 tests.
- `git diff --check`: passed.
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`: passed.

## Follow-up Fix

After testing the real app, the initial card shell did not match the preview well enough.
The visible problems were card clipping and a sparse black-box appearance.

Root cause:

- `NotchExpandedLayoutPolicy` still estimated adaptive height with the old row model:
  `serviceCount * 32 + padding`.
- Three services only received `116pt` of body height, which was too small for Model Cards.
- Card bodies still rendered the old horizontal `WidgetRenderer`, so the cards did not become
  compact metric grids.

Fix:

- Added `adaptiveModeReservesEnoughHeightForModelCards()` to reproduce the height issue first.
- Updated adaptive expanded height to estimate one compact card per service while keeping the
  existing screen-height cap and scrolling fallback.
- Added `OverlayMetricGrid` and `OverlayMetricTile` for card-only metric presentation.
- Updated grouped and sectioned cards to use the metric grid.
- Kept compact mode on the existing `WidgetRenderer`.

Follow-up verification:

- `swift test --filter NotchExpandedLayoutPolicy`: passed, 5 tests.
- `swift test --filter NotchSurfacePolicy`: passed, 25 tests.
- `swift test`: passed, 170 tests.
- `git diff --check`: passed.
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`: passed.

## Second Layout Follow-up

The next real-app screenshot still showed layout problems:

- Single-widget services were rendered as full-width black rows.
- The first service card looked visually pressed under the notch top cap.
- Detached/grouped scaling still relied on the pre-card row-height estimate.

Root cause:

- `GroupedOverlayView` stacked `OverlayModelCard` views in a full-width `VStack`.
- `OverlayMetricGrid` fixed only widget layout inside a card, not the service-card grid itself.
- `FloatingPanelView.calculateAdaptiveScale` still used `serviceCount * 32 + 16`.
- Hosted body content started too close to the top cap boundary for the new card header.

Fix:

- Added card-row expectations to `NotchExpandedLayoutPolicyTests`.
- Added `FloatingPanelContentLayoutPolicy.adaptiveScale(...)` and covered grouped card scaling.
- Changed grouped overlay to render service cards through `OverlayServiceCardGrid`.
- Added service-card min/max width and tightened metric tile sizing.
- Added a small hosted body top inset.
- Updated detached panel adaptive scale to use the new card-row policy.

Second follow-up verification:

- `swift test --filter NotchExpandedLayoutPolicy --filter FloatingPanelContentLayoutPolicy`: passed, 7 tests.
- `swift test --filter NotchSurfacePolicy`: passed, 25 tests.
- `swift test`: passed, 171 tests.
- `git diff --check`: passed.
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`: passed.
