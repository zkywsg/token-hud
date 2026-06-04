import CoreGraphics

/// Describes the host panel mode.
enum NotchHostMode: Equatable {
    case collapsed
    case expanded
    case detached
}

enum NotchHostedDragResolution: Equatable {
    case snapBack
    case detach
}

/// Extracted notch geometry from screen information.
struct NotchGeometry: Equatable {
    let notchGapMinX: CGFloat
    let notchGapMaxX: CGFloat
    let notchGapWidth: CGFloat
    let menuBarHeight: CGFloat
    let topEdgeY: CGFloat
    let hasNotch: Bool
    let leftContentArea: CGRect
    let rightContentArea: CGRect
}

/// Computed frame rects for body panels.
struct NotchFrames: Equatable {
    /// Full-width panel when collapsed (ears at top, thin strip below notch).
    let collapsed: CGRect
    /// Full-width panel when expanded (ears at top, content area below notch).
    let expanded: CGRect
    let snapZone: CGRect
}

/// Local drawing rects inside the unified hosted surface window
/// (collapsed compact slots + optional body that grows with `expansionProgress`).
///
/// Coordinates are in the hosted surface's local space, where (0, 0) is
/// the bottom-left of the overlay window. `surfaceHeight` matches the
/// overlay window's full height (menu bar + expanded body slot).
struct NotchHostedSurfaceLayout: Equatable {
    let topCap: CGRect
    let notchGap: CGRect
    let leftStatusSlot: CGRect
    let rightStatusSlot: CGRect
    let body: CGRect
    let contentOpacity: CGFloat
    let surfaceSize: CGSize
}

/// Pure-logic calculator for notch host panel geometry.
enum NotchGeometryCalculator {
    static let compactStatusSlotWidth: CGFloat = 56
    static let compactStatusSafeSideMargin: CGFloat = 24
    static let collapsedTriggerHitPadding: CGFloat = 14
    static let collapsedHoverPadding: CGFloat = collapsedTriggerHitPadding
    static let expandedHeight: CGFloat = 110
    static let expandedBodyMaxWidth: CGFloat = 560
    static let contentFadeStartProgress: CGFloat = 0.55
    static let snapZoneExpandX: CGFloat = 80
    static let snapZoneExpandY: CGFloat = 50
    static let detachThreshold: CGFloat = 60

    // MARK: - Geometry extraction

    static func notchGeometry(
        screenFrame: CGRect,
        safeAreaInsetTop: CGFloat,
        auxiliaryTopLeftArea: CGRect,
        auxiliaryTopRightArea: CGRect
    ) -> NotchGeometry {
        if auxiliaryTopLeftArea != .null && auxiliaryTopRightArea != .null {
            let gapMinX = auxiliaryTopLeftArea.maxX
            let gapMaxX = auxiliaryTopRightArea.minX
            let topEdgeY = max(
                screenFrame.maxY,
                auxiliaryTopLeftArea.maxY,
                auxiliaryTopRightArea.maxY
            )
            return NotchGeometry(
                notchGapMinX: gapMinX,
                notchGapMaxX: gapMaxX,
                notchGapWidth: gapMaxX - gapMinX,
                menuBarHeight: safeAreaInsetTop,
                topEdgeY: topEdgeY,
                hasNotch: true,
                leftContentArea: auxiliaryTopLeftArea,
                rightContentArea: auxiliaryTopRightArea
            )
        }
        return noNotchFallback(screenFrame: screenFrame)
    }

    static func noNotchFallback(screenFrame: CGRect) -> NotchGeometry {
        NotchGeometry(
            notchGapMinX: screenFrame.midX - 50,
            notchGapMaxX: screenFrame.midX + 50,
            notchGapWidth: 100,
            menuBarHeight: 24,
            topEdgeY: screenFrame.maxY,
            hasNotch: false,
            leftContentArea: .null,
            rightContentArea: .null
        )
    }

    // MARK: - Frame computation

    static func notchFrames(
        screenFrame: CGRect,
        geometry: NotchGeometry
    ) -> NotchFrames {
        let notchCenterX = geometry.hasNotch
            ? (geometry.notchGapMinX + geometry.notchGapMaxX) / 2
            : screenFrame.midX
        let maxBodyWidth = max(120, screenFrame.width - 80)
        let collapsedWidth = min(maxBodyWidth, geometry.notchGapWidth + compactStatusSlotWidth * 2)
        let expandedWidth = min(
            maxBodyWidth,
            max(collapsedWidth, expandedBodyMaxWidth)
        )
        let hostTopY = screenFrame.maxY

        let collapsed = CGRect(
            x: (notchCenterX - collapsedWidth / 2).clamped(
                to: screenFrame.minX...(screenFrame.maxX - collapsedWidth)
            ),
            y: hostTopY - geometry.menuBarHeight,
            width: collapsedWidth,
            height: geometry.menuBarHeight
        )

        let expanded = CGRect(
            x: (notchCenterX - expandedWidth / 2).clamped(
                to: screenFrame.minX...(screenFrame.maxX - expandedWidth)
            ),
            y: hostTopY - geometry.menuBarHeight - expandedHeight,
            width: expandedWidth,
            height: geometry.menuBarHeight + expandedHeight
        )

        let snapZone = CGRect(
            x: expanded.minX - snapZoneExpandX,
            y: expanded.minY - snapZoneExpandY,
            width: expanded.width + snapZoneExpandX * 2,
            height: expanded.height + snapZoneExpandY
        )

        return NotchFrames(
            collapsed: collapsed,
            expanded: expanded,
            snapZone: snapZone
        )
    }

    /// The notch region for mouse hover detection (gap + ears area).
    static func notchRegion(
        screenFrame: CGRect,
        geometry: NotchGeometry
    ) -> CGRect {
        let regions = notchHoverRegions(screenFrame: screenFrame, geometry: geometry)
        guard var union = regions.first else {
            return .null
        }
        for region in regions.dropFirst() {
            union = union.union(region)
        }
        return union
    }

    static func notchHoverRegions(
        screenFrame: CGRect,
        geometry: NotchGeometry
    ) -> [CGRect] {
        if geometry.hasNotch {
            let frames = notchFrames(screenFrame: screenFrame, geometry: geometry)
            let layout = hostedSurfaceLayout(
                screenFrame: screenFrame,
                geometry: geometry,
                expansionProgress: 0
            )
            let topCap = CGRect(
                x: frames.expanded.minX + layout.topCap.minX,
                y: frames.expanded.minY + layout.topCap.minY,
                width: layout.topCap.width,
                height: layout.topCap.height
            )
            return [
                clampedRegion(topCap.insetBy(dx: -collapsedHoverPadding, dy: -collapsedHoverPadding), to: screenFrame)
            ]
        }
        return [
            CGRect(
            x: screenFrame.midX - 100,
            y: screenFrame.maxY - 44,
            width: 200,
            height: 44
            )
        ]
    }

    // MARK: - Snap / Detach

    static func shouldSnapToNotch(
        panelFrame: CGRect,
        snapZone: CGRect
    ) -> Bool {
        let topCenter = CGPoint(x: panelFrame.midX, y: panelFrame.maxY)
        return snapZone.contains(topCenter)
    }

    static func shouldDetachFromCollapsed(
        panelFrame: CGRect,
        collapsedFrame: CGRect
    ) -> Bool {
        let dy = collapsedFrame.midY - panelFrame.midY
        let dx = abs(panelFrame.midX - collapsedFrame.midX)
        return dy > detachThreshold || dx > 150
    }

    static func hostedDragResolution(
        panelFrame: CGRect,
        collapsedFrame: CGRect
    ) -> NotchHostedDragResolution {
        let downwardDrop = collapsedFrame.maxY - panelFrame.maxY
        let horizontalOffset = abs(panelFrame.midX - collapsedFrame.midX)
        if downwardDrop > detachThreshold || horizontalOffset > 150 {
            return .detach
        }
        return .snapBack
    }

    // MARK: - Hosted surface layout

    /// Layout inside the unified hosted surface window. The surface window
    /// always uses the expanded frame's size; visual collapse/expand is
    /// driven entirely by `expansionProgress` so the window itself never
    /// resizes — eliminating SwiftUI/window animation cross-talk.
    static func hostedSurfaceLayout(
        screenFrame: CGRect,
        geometry: NotchGeometry,
        expansionProgress: CGFloat
    ) -> NotchHostedSurfaceLayout {
        let progress = expansionProgress.clamped(to: 0...1)
        let frames = notchFrames(screenFrame: screenFrame, geometry: geometry)
        let surfaceSize = frames.expanded.size
        let menuBarHeight = geometry.menuBarHeight

        let gapWidth = max(0, min(geometry.notchGapWidth, surfaceSize.width))
        let gapMinX = (geometry.notchGapMinX - frames.expanded.minX).clamped(to: 0...surfaceSize.width)
        let gapMaxX = (geometry.notchGapMaxX - frames.expanded.minX).clamped(to: gapMinX...surfaceSize.width)
        let gapCenterX = (gapMinX + gapMaxX) / 2
        let maxSideExpansion = max(0, min(gapMinX, surfaceSize.width - gapMaxX))
        let screenLeftRoom = max(0, geometry.notchGapMinX - screenFrame.minX - compactStatusSafeSideMargin)
        let screenRightRoom = max(0, screenFrame.maxX - geometry.notchGapMaxX - compactStatusSafeSideMargin)
        let collapsedStatusWidth = min(
            compactStatusSlotWidth,
            maxSideExpansion,
            screenLeftRoom,
            screenRightRoom
        )
        let collapsedTopCapWidth = min(surfaceSize.width, gapWidth + collapsedStatusWidth * 2)

        let bodyHeight = expandedHeight * progress
        let bodyMaxWidth = min(surfaceSize.width, expandedBodyMaxWidth)
        let bodyMinWidth = min(bodyMaxWidth, max(collapsedTopCapWidth, 120))
        let bodyWidth = interpolate(from: bodyMinWidth, to: bodyMaxWidth, progress: progress)
        let topCapWidth = bodyWidth
        let topCapX = (gapCenterX - topCapWidth / 2).clamped(to: 0...(surfaceSize.width - topCapWidth))

        // Surface uses bottom-left origin; the top cap lives in the menu bar row.
        let capY = surfaceSize.height - menuBarHeight
        let topCap = CGRect(
            x: topCapX,
            y: capY,
            width: topCapWidth,
            height: menuBarHeight
        )
        let notchGap = CGRect(
            x: gapMinX,
            y: capY,
            width: gapWidth,
            height: menuBarHeight
        )
        let statusWidth = min(collapsedStatusWidth, max(0, (topCap.width - gapWidth) / 2))
        let leftStatusSlot = CGRect(
            x: topCap.minX,
            y: capY,
            width: statusWidth,
            height: menuBarHeight
        )
        let rightStatusSlot = CGRect(
            x: topCap.maxX - statusWidth,
            y: capY,
            width: statusWidth,
            height: menuBarHeight
        )
        let body = CGRect(
            x: max(0, min(surfaceSize.width - bodyWidth, gapCenterX - bodyWidth / 2)),
            y: capY - bodyHeight,
            width: bodyWidth,
            height: bodyHeight
        )

        return NotchHostedSurfaceLayout(
            topCap: topCap,
            notchGap: notchGap,
            leftStatusSlot: leftStatusSlot,
            rightStatusSlot: rightStatusSlot,
            body: body,
            contentOpacity: contentOpacity(for: progress),
            surfaceSize: surfaceSize
        )
    }
}

private func clampedRegion(_ rect: CGRect, to bounds: CGRect) -> CGRect {
    let minX = max(bounds.minX, rect.minX)
    let minY = max(bounds.minY, rect.minY)
    let maxX = min(bounds.maxX, rect.maxX)
    let maxY = min(bounds.maxY, rect.maxY)
    return CGRect(
        x: minX,
        y: minY,
        width: max(0, maxX - minX),
        height: max(0, maxY - minY)
    )
}

private func contentOpacity(for progress: CGFloat) -> CGFloat {
    guard progress > NotchGeometryCalculator.contentFadeStartProgress else { return 0 }
    let fadeRange = 1 - NotchGeometryCalculator.contentFadeStartProgress
    return ((progress - NotchGeometryCalculator.contentFadeStartProgress) / fadeRange)
        .clamped(to: 0...1)
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private func interpolate(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
    start + (end - start) * progress.clamped(to: 0...1)
}
