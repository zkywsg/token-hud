import CoreGraphics
import Testing
@testable import token_hudCore

@Suite("NotchGeometryCalculator")
struct NotchGeometryCalculatorTests {

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let safeAreaTop: CGFloat = 32
    private let leftAux = CGRect(x: 0, y: 868, width: 645, height: 32)
    private let rightAux = CGRect(x: 795, y: 868, width: 645, height: 32)

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

    @Test func collapsedOverlayFrameIncludesMenuBarBridgeAndBody() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        #expect(NotchGeometryCalculator.collapsedBodyHeight == 22)
        #expect(frames.collapsed.height == safeAreaTop + NotchGeometryCalculator.collapsedBodyHeight)
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

    @Test func collapsedHostFrameCentersBelowNotchWithoutFullWidthBridge() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let frames = NotchGeometryCalculator.notchFrames(screenFrame: screen, geometry: geo)
        let expectedWidth = geo.notchGapWidth + NotchGeometryCalculator.collapsedBodyHorizontalPadding
        #expect(frames.collapsed.width == expectedWidth)
        #expect(abs(frames.collapsed.midX - screen.midX) < 1)
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

    // MARK: - Fusion layout

    @Test func fusionLayoutDrawsTopBridgeAndBodyBelowMenuBar() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let layout = NotchGeometryCalculator.notchFusionLayout(
            screenFrame: screen,
            geometry: geo,
            expansionProgress: 1
        )
        #expect(!layout.topBridge.isEmpty)
        #expect(layout.topBridge.minY == 0)
        #expect(layout.topBridge.height == safeAreaTop)
        #expect(layout.rightBridge.isEmpty)
        #expect(layout.body.minY == safeAreaTop)
    }

    @Test func fusionLayoutExpandsBodyWithoutPanelBridge() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let collapsed = NotchGeometryCalculator.notchFusionLayout(
            screenFrame: screen,
            geometry: geo,
            expansionProgress: 0
        )
        let bridgeOnly = NotchGeometryCalculator.notchFusionLayout(
            screenFrame: screen,
            geometry: geo,
            expansionProgress: 0.35
        )
        let expanded = NotchGeometryCalculator.notchFusionLayout(
            screenFrame: screen,
            geometry: geo,
            expansionProgress: 1
        )
        #expect(!collapsed.topBridge.isEmpty)
        #expect(!bridgeOnly.topBridge.isEmpty)
        #expect(!expanded.topBridge.isEmpty)
        #expect(bridgeOnly.body.height > collapsed.body.height)
        #expect(expanded.body.height > bridgeOnly.body.height)
        #expect(expanded.contentOpacity > bridgeOnly.contentOpacity)
    }

    @Test func fusionLayoutDelaysContentUntilBodyHasRoom() {
        let geo = NotchGeometryCalculator.notchGeometry(
            screenFrame: screen, safeAreaInsetTop: safeAreaTop,
            auxiliaryTopLeftArea: leftAux, auxiliaryTopRightArea: rightAux
        )
        let collapsed = NotchGeometryCalculator.notchFusionLayout(
            screenFrame: screen,
            geometry: geo,
            expansionProgress: 0
        )
        let early = NotchGeometryCalculator.notchFusionLayout(
            screenFrame: screen,
            geometry: geo,
            expansionProgress: 0.35
        )
        let middle = NotchGeometryCalculator.notchFusionLayout(
            screenFrame: screen,
            geometry: geo,
            expansionProgress: 0.7
        )
        let expanded = NotchGeometryCalculator.notchFusionLayout(
            screenFrame: screen,
            geometry: geo,
            expansionProgress: 1
        )
        #expect(collapsed.contentOpacity == 0)
        #expect(early.contentOpacity == 0)
        #expect(middle.contentOpacity > 0)
        #expect(expanded.contentOpacity == 1)
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
