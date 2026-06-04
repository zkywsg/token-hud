import CoreGraphics
import Testing
@testable import token_hudCore

@Suite("NotchGeometryCalculator")
struct NotchGeometryCalculatorTests {

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let safeAreaTop: CGFloat = 32
    private let leftAux = CGRect(x: 0, y: 868, width: 645, height: 32)
    private let rightAux = CGRect(x: 795, y: 868, width: 645, height: 32)
    private let compactStatusSlotWidth: CGFloat = 56
    private let collapsedTriggerHitPadding: CGFloat = 14

    // MARK: - Geometry extraction

    @Test func geometryWithAuxAreasExtractsNotch() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen,
            safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux,
            auxiliaryTopRightArea: rightAux
        )
        #expect(geo.hasNotch)
        #expect(geo.menuBarHeight == safeAreaTop)
        #expect(geo.notchGapMinX == leftAux.maxX)
        #expect(geo.notchGapMaxX == rightAux.minX)
        #expect(geo.notchGapWidth == rightAux.minX - leftAux.maxX)
    }

    @Test func geometryUsesAuxiliaryTopEdgeWhenItExceedsScreenFrame() {
        let shiftedLeftAux = CGRect(x: 0, y: 900, width: 645, height: 32)
        let shiftedRightAux = CGRect(x: 795, y: 900, width: 645, height: 32)
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen,
            safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: shiftedLeftAux,
            auxiliaryTopRightArea: shiftedRightAux
        )
        #expect(geo.topEdgeY == shiftedLeftAux.maxY)
    }

    @Test func geometryWithoutAuxAreasUsesFallback() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen,
            safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: .null,
            auxiliaryTopRightArea: .null
        )
        #expect(!geo.hasNotch)
        #expect(geo.menuBarHeight == 24)
        #expect(geo.notchGapWidth == 100)
        #expect(geo.topEdgeY == screen.maxY)
    }

    @Test func geometrySmallSafeAreaUsesActualValue() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen,
            safeAreaInsetTop: 5,
            auxiliaryTopLeftArea: leftAux,
            auxiliaryTopRightArea: rightAux
        )
        #expect(geo.menuBarHeight == 5)
    }

    @Test func geometryLargeSafeAreaUsesActualValue() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen,
            safeAreaInsetTop: 50,
            auxiliaryTopLeftArea: leftAux,
            auxiliaryTopRightArea: rightAux
        )
        #expect(geo.menuBarHeight == 50)
    }

    // MARK: - Collapsed frame

    @Test func collapsedOverlayFrameOnlyCoversMenuBarStatusArea() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        #expect(frames.collapsed.height == safeAreaTop)
        #expect(frames.collapsed.minY == screen.maxY - safeAreaTop)
        #expect(frames.collapsed.maxY == screen.maxY)
    }

    @Test func collapsedOverlayAnchorsToScreenTopOnNotchedDisplay() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        #expect(frames.collapsed.maxY == screen.maxY)
    }

    @Test func collapsedOverlayDoesNotOvershootWhenAuxiliaryTopEdgeExceedsScreenFrame() {
        let shiftedLeftAux = CGRect(x: 0, y: 900, width: 645, height: 32)
        let shiftedRightAux = CGRect(x: 795, y: 900, width: 645, height: 32)
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: shiftedLeftAux, auxiliaryTopRightArea: shiftedRightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        #expect(frames.collapsed.maxY == screen.maxY)
    }

    @Test func collapsedHostFrameCentersOnNotchWithCompactStatusEars() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        let expectedWidth = geo.notchGapWidth + compactStatusSlotWidth * 2
        #expect(frames.collapsed.width == expectedWidth)
        #expect(abs(frames.collapsed.midX - screen.midX) < 1)
    }

    @Test func collapsedHostFrameIsMuchNarrowerThanExpandedFrame() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        #expect(frames.collapsed.width < frames.expanded.width)
        #expect(frames.collapsed.width < screen.width * 0.3)
    }

    @Test func collapsedClampedWithinScreenBounds() {
        let wideLeft = CGRect(x: -100, y: 868, width: 800, height: 32)
        let wideRight = CGRect(x: 800, y: 868, width: 800, height: 32)
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: wideLeft, auxiliaryTopRightArea: wideRight
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        #expect(frames.collapsed.minX >= screen.minX)
    }

    @Test func collapsedCenteredOnNotch() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        let expectedCenter = (leftAux.maxX + rightAux.minX) / 2
        #expect(abs(frames.collapsed.midX - expectedCenter) < 1)
        #expect(frames.collapsed.minX >= screen.minX)
    }

    // MARK: - Expanded frame

    @Test func expandedOverlayAnchorsToScreenTopOnNotchedDisplay() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        #expect(frames.expanded.maxY == screen.maxY)
    }

    @Test func expandedOverlayDoesNotOvershootWhenAuxiliaryTopEdgeExceedsScreenFrame() {
        let shiftedLeftAux = CGRect(x: 0, y: 900, width: 645, height: 32)
        let shiftedRightAux = CGRect(x: 795, y: 900, width: 645, height: 32)
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: shiftedLeftAux, auxiliaryTopRightArea: shiftedRightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        #expect(frames.expanded.maxY == screen.maxY)
    }

    @Test func expandedWidthCanGrowBeyondCollapsedBody() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        #expect(frames.expanded.width > frames.collapsed.width)
    }

    @Test func expandedHostFrameCentersBelowNotchWithoutFullWidthBridge() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        #expect(frames.expanded.width == NotchGeometryCalculator.expandedBodyMaxWidth)
        #expect(abs(frames.expanded.midX - screen.midX) < 1)
    }

    @Test func expandedOverlayFrameIncludesMenuBarBridgeAndContent() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        #expect(frames.expanded.height == safeAreaTop + NotchGeometryCalculator.expandedHeight)
    }

    @Test func expandedMinYIsBelowCollapsed() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        #expect(frames.expanded.minY < frames.collapsed.minY)
    }

    @Test func expandedOnNoNotchDisplayUsesFallback() {
        let geo = NotchGeometryCalculator.noNotchFallback(screenFrame: screen)
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        #expect(frames.expanded.height == geo.menuBarHeight + NotchGeometryCalculator.expandedHeight)
        #expect(frames.expanded.maxY == screen.maxY)
    }

    // MARK: - Snap zone

    @Test func snapZoneEnclosesCollapsed() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        #expect(frames.snapZone.minX <= frames.collapsed.minX)
        #expect(frames.snapZone.maxX >= frames.collapsed.maxX)
        #expect(frames.snapZone.minY <= frames.collapsed.minY)
        #expect(frames.snapZone.maxY >= frames.collapsed.maxY)
    }

    @Test func snapZoneExtendsHorizontally() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        let expanded = frames.expanded
        let snap = frames.snapZone
        #expect(snap.minX == expanded.minX - NotchGeometryCalculator.snapZoneExpandX)
        #expect(snap.maxX == expanded.maxX + NotchGeometryCalculator.snapZoneExpandX)
    }

    @Test func snapZoneExtendsDownward() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        #expect(frames.snapZone.minY == frames.expanded.minY - NotchGeometryCalculator.snapZoneExpandY)
    }

    @Test func panelInsideSnapZoneSnaps() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        let panel = frames.collapsed.offsetBy(dx: 0, dy: -20)
        #expect(NotchGeometryCalculator.shouldSnapToNotch(panelFrame: panel, snapZone: frames.snapZone))
    }

    @Test func panelOutsideSnapZoneDoesNotSnap() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        let panel = CGRect(x: 100, y: 400, width: 300, height: 60)
        #expect(!NotchGeometryCalculator.shouldSnapToNotch(panelFrame: panel, snapZone: frames.snapZone))
    }

    // MARK: - Detach detection

    @Test func downwardDragBeyondThresholdDetaches() {
        let collapsed = CGRect(x: 570, y: 860, width: 300, height: 40)
        let dragged = CGRect(x: 570, y: 740, width: 300, height: 40)
        #expect(NotchGeometryCalculator.shouldDetachFromCollapsed(
            panelFrame: dragged, collapsedFrame: collapsed
        ))
    }

    @Test func smallDownwardDragDoesNotDetach() {
        let collapsed = CGRect(x: 570, y: 860, width: 300, height: 40)
        let dragged = CGRect(x: 570, y: 850, width: 300, height: 40)
        #expect(!NotchGeometryCalculator.shouldDetachFromCollapsed(
            panelFrame: dragged, collapsedFrame: collapsed
        ))
    }

    @Test func horizontalOffsetBeyondThresholdDetaches() {
        let collapsed = CGRect(x: 570, y: 860, width: 300, height: 40)
        let dragged = CGRect(x: 900, y: 860, width: 300, height: 40)
        #expect(NotchGeometryCalculator.shouldDetachFromCollapsed(
            panelFrame: dragged, collapsedFrame: collapsed
        ))
    }

    @Test func upwardDragDoesNotDetach() {
        let collapsed = CGRect(x: 570, y: 860, width: 300, height: 40)
        let dragged = CGRect(x: 570, y: 880, width: 300, height: 40)
        #expect(!NotchGeometryCalculator.shouldDetachFromCollapsed(
            panelFrame: dragged, collapsedFrame: collapsed
        ))
    }

    @Test func hostedSmallDragSettlesBackToCanonicalFrame() {
        let collapsed = CGRect(x: 570, y: 860, width: 300, height: 40)
        let dragged = CGRect(x: 586, y: 842, width: 300, height: 40)
        #expect(NotchGeometryCalculator.hostedDragResolution(
            panelFrame: dragged,
            collapsedFrame: collapsed
        ) == .snapBack)
    }

    @Test func hostedDownwardDragBeyondThresholdDetaches() {
        let collapsed = CGRect(x: 570, y: 860, width: 300, height: 40)
        let dragged = CGRect(x: 570, y: 730, width: 300, height: 40)
        #expect(NotchGeometryCalculator.hostedDragResolution(
            panelFrame: dragged,
            collapsedFrame: collapsed
        ) == .detach)
    }

    @Test func hostedHorizontalDragBeyondThresholdDetaches() {
        let collapsed = CGRect(x: 570, y: 860, width: 300, height: 40)
        let dragged = CGRect(x: 840, y: 850, width: 300, height: 40)
        #expect(NotchGeometryCalculator.hostedDragResolution(
            panelFrame: dragged,
            collapsedFrame: collapsed
        ) == .detach)
    }

    // MARK: - No-notch fallback

    @Test func noNotchFallbackSetsHasNotchFalse() {
        let geo = NotchGeometryCalculator.noNotchFallback(screenFrame: screen)
        #expect(!geo.hasNotch)
    }

    @Test func noNotchFallbackCentersOnScreen() {
        let geo = NotchGeometryCalculator.noNotchFallback(screenFrame: screen)
        #expect(abs(geo.notchGapMinX + geo.notchGapMaxX - screen.midX * 2) < 1)
    }

    @Test func noNotchFallbackUsesMenuBarHeight() {
        let geo = NotchGeometryCalculator.noNotchFallback(screenFrame: screen)
        #expect(geo.menuBarHeight == 24)
    }

    // MARK: - Snap detection (center-point based)

    @Test func snapWithTopCenterInsideZone() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        let panel = CGRect(x: frames.collapsed.minX, y: 800,
                           width: frames.collapsed.width, height: 60)
        #expect(NotchGeometryCalculator.shouldSnapToNotch(panelFrame: panel, snapZone: frames.snapZone))
    }

    // MARK: - Hosted surface layout

    @Test func hostedSurfaceLayoutUsesSingleCollapsedTopCap() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let zero = NotchGeometryCalculator.hostedSurfaceLayout(
            screenFrame: screen, geometry: geo, expansionProgress: 0
        )
        let full = NotchGeometryCalculator.hostedSurfaceLayout(
            screenFrame: screen, geometry: geo, expansionProgress: 1
        )
        #expect(zero.topCap.width == geo.notchGapWidth + compactStatusSlotWidth * 2)
        #expect(zero.topCap.height == safeAreaTop)
        #expect(zero.topCap.maxY == zero.surfaceSize.height)
        #expect(zero.topCap.width < full.topCap.width)
        #expect(zero.body.height == 0)
    }

    @Test func hostedSurfaceLayoutStatusSlotsStayInsideTopCap() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let layout = NotchGeometryCalculator.hostedSurfaceLayout(
            screenFrame: screen, geometry: geo, expansionProgress: 0
        )
        #expect(layout.topCap.contains(layout.leftStatusSlot))
        #expect(layout.topCap.contains(layout.rightStatusSlot))
        #expect(layout.leftStatusSlot.width == compactStatusSlotWidth)
        #expect(layout.rightStatusSlot.width == compactStatusSlotWidth)
        #expect(layout.leftStatusSlot.maxX == layout.notchGap.minX)
        #expect(layout.rightStatusSlot.minX == layout.notchGap.maxX)
    }

    @Test func hostedSurfaceLayoutBodyHeightGrowsMonotonically() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let p0 = NotchGeometryCalculator.hostedSurfaceLayout(screenFrame: screen, geometry: geo, expansionProgress: 0)
        let p35 = NotchGeometryCalculator.hostedSurfaceLayout(screenFrame: screen, geometry: geo, expansionProgress: 0.35)
        let p70 = NotchGeometryCalculator.hostedSurfaceLayout(screenFrame: screen, geometry: geo, expansionProgress: 0.7)
        let p100 = NotchGeometryCalculator.hostedSurfaceLayout(screenFrame: screen, geometry: geo, expansionProgress: 1)
        #expect(p0.body.height == 0)
        #expect(p35.body.height > p0.body.height)
        #expect(p70.body.height > p35.body.height)
        #expect(p100.body.height > p70.body.height)
        #expect(p100.body.height == NotchGeometryCalculator.expandedHeight)
    }

    @Test func hostedSurfaceLayoutBodyOpacityRespectsFadeStart() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let early = NotchGeometryCalculator.hostedSurfaceLayout(
            screenFrame: screen, geometry: geo,
            expansionProgress: NotchGeometryCalculator.contentFadeStartProgress - 0.01
        )
        let later = NotchGeometryCalculator.hostedSurfaceLayout(
            screenFrame: screen, geometry: geo, expansionProgress: 0.85
        )
        let full = NotchGeometryCalculator.hostedSurfaceLayout(
            screenFrame: screen, geometry: geo, expansionProgress: 1
        )
        #expect(early.contentOpacity == 0)
        #expect(later.contentOpacity > 0)
        #expect(full.contentOpacity == 1)
    }

    @Test func hostedSurfaceLayoutSurfaceSizeMatchesExpandedFrame() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        let layout = NotchGeometryCalculator.hostedSurfaceLayout(
            screenFrame: screen, geometry: geo, expansionProgress: 0
        )
        #expect(layout.surfaceSize == frames.expanded.size)
    }

    @Test func hostedSurfaceLayoutTopCapAndGapCoverMenuBarRow() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let layout = NotchGeometryCalculator.hostedSurfaceLayout(
            screenFrame: screen, geometry: geo, expansionProgress: 0
        )
        #expect(layout.topCap.height == safeAreaTop)
        #expect(layout.notchGap.height == safeAreaTop)
        #expect(layout.topCap.contains(layout.notchGap))
        #expect(layout.topCap.maxY == layout.surfaceSize.height)
        #expect(layout.notchGap.maxY == layout.surfaceSize.height)
    }

    @Test func compactNotchHoverRegionsDoNotCoverFullMenuBarWidth() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let regions = NotchGeometryCalculator.notchHoverRegions(screenFrame: screen, geometry: geo)
        #expect(regions.count == 1)
        #expect(regions.allSatisfy { $0.width < screen.width * 0.25 })
        #expect(!regions.contains { $0.contains(CGPoint(x: screen.minX + 50, y: screen.maxY - 8)) })
        #expect(!regions.contains { $0.contains(CGPoint(x: screen.maxX - 50, y: screen.maxY - 8)) })
    }

    @Test func compactNotchHoverRegionCoversCollapsedTopCap() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        let layout = NotchGeometryCalculator.hostedSurfaceLayout(
            screenFrame: screen, geometry: geo, expansionProgress: 0
        )
        let regions = NotchGeometryCalculator.notchHoverRegions(screenFrame: screen, geometry: geo)
        let topCapMin = CGPoint(
            x: frames.expanded.minX + layout.topCap.minX + 1,
            y: frames.expanded.minY + layout.topCap.midY
        )
        let topCapMax = CGPoint(
            x: frames.expanded.minX + layout.topCap.maxX - 1,
            y: frames.expanded.minY + layout.topCap.midY
        )
        #expect(regions.contains { $0.contains(topCapMin) })
        #expect(regions.contains { $0.contains(topCapMax) })
    }

    @Test func compactNotchHoverRegionIsWiderThanVisibleTopCap() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let layout = NotchGeometryCalculator.hostedSurfaceLayout(
            screenFrame: screen, geometry: geo, expansionProgress: 0
        )
        let regions = NotchGeometryCalculator.notchHoverRegions(screenFrame: screen, geometry: geo)
        let expectedWidth = layout.topCap.width + collapsedTriggerHitPadding * 2
        #expect(regions.count == 1)
        #expect(regions[0].width == expectedWidth)
        #expect(regions[0].width < screen.width * 0.25)
    }

    @Test func snapWithTopCenterOutsideZoneDoesNotSnap() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        let panel = CGRect(x: frames.collapsed.midX - 50, y: 300,
                           width: 100, height: 60)
        #expect(!NotchGeometryCalculator.shouldSnapToNotch(panelFrame: panel, snapZone: frames.snapZone))
    }
}
