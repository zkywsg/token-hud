import CoreGraphics

/// Describes the host panel mode.
enum NotchHostMode: Equatable {
    case collapsed
    case expanded
    case detached
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

/// Local drawing rects inside the transparent hosted panel.
struct NotchFusionLayout: Equatable {
    let topBridge: CGRect
    let leftBridge: CGRect
    let rightBridge: CGRect
    let body: CGRect
    let contentOpacity: CGFloat
}

/// Pure-logic calculator for notch host panel geometry.
enum NotchGeometryCalculator {
    static let collapsedBodyHeight: CGFloat = 22
    static let expandedHeight: CGFloat = 110
    static let expandedBottomCornerRadius: CGFloat = 12
    static let collapsedBridgeWidth: CGFloat = 28
    static let expandedBridgeMaxWidth: CGFloat = 260
    static let collapsedBodyHorizontalPadding: CGFloat = 40
    static let expandedBodyMaxWidth: CGFloat = 560
    static let bridgePhaseEnd: CGFloat = 0.35
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
        let collapsedWidth = min(
            maxBodyWidth,
            max(120, geometry.notchGapWidth + collapsedBodyHorizontalPadding)
        )
        let expandedWidth = min(
            maxBodyWidth,
            max(collapsedWidth, expandedBodyMaxWidth)
        )
        let hostTopY = screenFrame.maxY

        let collapsed = CGRect(
            x: (notchCenterX - collapsedWidth / 2).clamped(
                to: screenFrame.minX...(screenFrame.maxX - collapsedWidth)
            ),
            y: hostTopY - geometry.menuBarHeight - collapsedBodyHeight,
            width: collapsedWidth,
            height: geometry.menuBarHeight + collapsedBodyHeight
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

    static func notchFusionLayout(
        screenFrame: CGRect,
        geometry: NotchGeometry,
        expansionProgress: CGFloat
    ) -> NotchFusionLayout {
        let progress = expansionProgress.clamped(to: 0...1)
        let collapsedBodyWidth = min(
            screenFrame.width,
            max(120, geometry.notchGapWidth + collapsedBodyHorizontalPadding)
        )
        let expandedBodyWidth = min(
            screenFrame.width,
            max(collapsedBodyWidth, expandedBodyMaxWidth)
        )
        let bodyWidth = interpolate(from: collapsedBodyWidth, to: expandedBodyWidth, progress: progress)
        let bodyHeight = interpolate(
            from: collapsedBodyHeight,
            to: expandedHeight,
            progress: progress
        )
        let body = CGRect(
            x: max(0, (screenFrame.width - bodyWidth) / 2),
            y: geometry.menuBarHeight,
            width: min(bodyWidth, screenFrame.width),
            height: bodyHeight
        )
        let topBridge = CGRect(
            x: body.minX,
            y: 0,
            width: body.width,
            height: geometry.menuBarHeight
        )

        return NotchFusionLayout(
            topBridge: topBridge,
            leftBridge: .null,
            rightBridge: .null,
            body: body,
            contentOpacity: contentOpacity(for: progress)
        )
    }

    /// The notch region for mouse hover detection (gap + ears area).
    static func notchRegion(
        screenFrame: CGRect,
        geometry: NotchGeometry
    ) -> CGRect {
        if geometry.hasNotch {
            return CGRect(
                x: screenFrame.minX,
                y: screenFrame.maxY - geometry.menuBarHeight - 20,
                width: screenFrame.width,
                height: geometry.menuBarHeight + 20
            )
        }
        return CGRect(
            x: screenFrame.midX - 100,
            y: screenFrame.maxY - 44,
            width: 200,
            height: 44
        )
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
