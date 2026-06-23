import Testing
@testable import token_hudCore

@Suite("Notch surface policies")
struct NotchSurfacePolicyTests {

    @Test func skyLightPolicyTreatsZeroReturnCodeAsSuccess() {
        #expect(SkyLightReturnCodePolicy.isSuccess(0))
    }

    @Test func skyLightPolicyTreatsNonZeroReturnCodeAsFailure() {
        #expect(!SkyLightReturnCodePolicy.isSuccess(1))
        #expect(!SkyLightReturnCodePolicy.isSuccess(-1))
    }

    @Test func skyLightPolicyRequiresSpaceSetupCallsToSucceed() {
        #expect(SkyLightReturnCodePolicy.isSpaceReady(setAbsoluteLevel: 0, showSpaces: 0))
        #expect(!SkyLightReturnCodePolicy.isSpaceReady(setAbsoluteLevel: 1, showSpaces: 0))
        #expect(!SkyLightReturnCodePolicy.isSpaceReady(setAbsoluteLevel: 0, showSpaces: 1))
        #expect(!SkyLightReturnCodePolicy.isSpaceReady(setAbsoluteLevel: nil, showSpaces: 0))
    }

    @Test func skyLightPolicyRequiresDelegateCallToSucceed() {
        #expect(SkyLightReturnCodePolicy.didDelegateWindow(returnCode: 0))
        #expect(!SkyLightReturnCodePolicy.didDelegateWindow(returnCode: 7))
        #expect(!SkyLightReturnCodePolicy.didDelegateWindow(returnCode: nil))
    }

    @Test func publicPanelFallbackDoesNotUseScreenSaverLevel() {
        #expect(NotchSurfaceLevelPolicy.levelKind(for: .publicPanel) != .screenSaver)
    }

    @Test func publicPanelFallbackUsesStatusBarCompatibleLevel() {
        #expect(NotchSurfaceLevelPolicy.levelKind(for: .publicPanel) == .statusBar)
    }

    @Test func skyLightPanelUsesMainMenuOffsetLevel() {
        #expect(NotchSurfaceLevelPolicy.levelKind(for: .skyLightSpace) == .mainMenuPlus(3))
    }

    @Test func hoverInsideExpandedCancelsPendingCollapse() {
        #expect(NotchTransitionPolicy.hoverAction(isMouseInside: true, mode: .expanded) == .cancelCollapse)
    }

    @Test func hoverOutsideExpandedSchedulesCollapse() {
        #expect(NotchTransitionPolicy.hoverAction(isMouseInside: false, mode: .expanded) == .scheduleCollapse)
    }

    @Test func hoverInsideCollapsedExpands() {
        #expect(NotchTransitionPolicy.hoverAction(isMouseInside: true, mode: .collapsed) == .expand)
    }

    @Test func expandedTopCapCountsAsInsideNotchRegion() {
        let isInside = NotchHoverRegionPolicy.isMouseInsideNotchRegion(
            mode: .expanded,
            isInsideCollapsedHoverRegion: false,
            isInsideExpandedSurface: true
        )
        #expect(isInside)
        #expect(NotchTransitionPolicy.hoverAction(isMouseInside: isInside, mode: .expanded) == .cancelCollapse)
    }

    @Test func expandedOutsideSurfaceSchedulesCollapse() {
        let isInside = NotchHoverRegionPolicy.isMouseInsideNotchRegion(
            mode: .expanded,
            isInsideCollapsedHoverRegion: false,
            isInsideExpandedSurface: false
        )
        #expect(!isInside)
        #expect(NotchTransitionPolicy.hoverAction(isMouseInside: isInside, mode: .expanded) == .scheduleCollapse)
    }

    @Test func collapsedIgnoresExpandedSurfaceForInitialTrigger() {
        let isInside = NotchHoverRegionPolicy.isMouseInsideNotchRegion(
            mode: .collapsed,
            isInsideCollapsedHoverRegion: false,
            isInsideExpandedSurface: true
        )
        #expect(!isInside)
        #expect(NotchTransitionPolicy.hoverAction(isMouseInside: isInside, mode: .collapsed) == .none)
    }

    @Test func hostedModesKeepWindowMouseEventsEnabledForHitMask() {
        #expect(!NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: .collapsed))
        #expect(!NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: .expanded))
    }

    @Test func detachedModeKeepsWindowMouseEventsEnabledForDragging() {
        #expect(!NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: .detached))
    }

    @Test func hostedModesDisableAppKitBackgroundDragging() {
        #expect(!NotchWindowMovementPolicy.isMovableByWindowBackground(mode: .collapsed))
        #expect(!NotchWindowMovementPolicy.isMovableByWindowBackground(mode: .expanded))
    }

    @Test func detachedModeAllowsAppKitBackgroundDragging() {
        #expect(NotchWindowMovementPolicy.isMovableByWindowBackground(mode: .detached))
    }

    @Test func infoEarsRemainVisibleWhenExpandedContentIsFullyVisible() {
        let opacity = NotchInfoEarPresentationPolicy.opacity(contentOpacity: 1)

        #expect(opacity >= 0.68)
    }

    @Test func infoEarsUseFullVisibilityWhenCollapsed() {
        #expect(NotchInfoEarPresentationPolicy.opacity(contentOpacity: 0) == 1)
    }

    @Test func infoEarsHideTextWhenSlotIsTooNarrow() {
        #expect(!NotchInfoEarPresentationPolicy.showsText(slotWidth: 30, text: "98% 5 hours"))
        #expect(NotchInfoEarPresentationPolicy.showsText(slotWidth: 48, text: "98%"))
    }

    @Test func infoEarProgressWidthKeepsCompactMinimumAndAvoidsOverflow() {
        #expect(NotchInfoEarPresentationPolicy.progressWidth(slotWidth: 28) == 18)
        #expect(NotchInfoEarPresentationPolicy.progressWidth(slotWidth: 80) == 54)
    }

    @Test func transitionGateInvalidatesOlderTokens() {
        var gate = NotchTransitionGate()
        let old = gate.advance()
        let current = gate.advance()

        #expect(!gate.isCurrent(old))
        #expect(gate.isCurrent(current))
    }

    @Test func hideCleanupCancelsPendingWorkAndDragState() {
        let cleanup = NotchPanelLifecyclePolicy.cleanup(for: .hide)

        #expect(cleanup.cancelsCollapseTimer)
        #expect(cleanup.removesMouseMoveMonitors)
        #expect(cleanup.removesMouseDownMonitor)
        #expect(cleanup.removesMouseUpMonitor)
        #expect(cleanup.resetsDraggingState)
    }

    @Test func teardownCleanupRemovesEveryMonitor() {
        let cleanup = NotchPanelLifecyclePolicy.cleanup(for: .teardown)

        #expect(cleanup.cancelsCollapseTimer)
        #expect(cleanup.removesMouseMoveMonitors)
        #expect(cleanup.removesMouseDownMonitor)
        #expect(cleanup.removesMouseUpMonitor)
        #expect(cleanup.resetsDraggingState)
    }

    @Test func switchToDetachedKeepsMouseUpPathForSnapAndPersistence() {
        let cleanup = NotchPanelLifecyclePolicy.cleanup(for: .switchToDetached)

        #expect(cleanup.cancelsCollapseTimer)
        #expect(cleanup.removesMouseMoveMonitors)
        #expect(cleanup.removesMouseDownMonitor)
        #expect(!cleanup.removesMouseUpMonitor)
        #expect(!cleanup.resetsDraggingState)
    }

    @Test func hostedResizeDuringFrameResetIsIgnored() {
        #expect(NotchHostedResizePolicy.action(
            mode: .collapsed,
            isResettingHostedFrame: true,
            isDragging: false
        ) == .ignore)
    }

    @Test func hostedResizeOutsideDragReassertsHostedFrame() {
        #expect(NotchHostedResizePolicy.action(
            mode: .expanded,
            isResettingHostedFrame: false,
            isDragging: false
        ) == .reassertHostedFrame)
    }

    @Test func hostedResizeDuringExpandedDragCanDetach() {
        #expect(NotchHostedResizePolicy.action(
            mode: .expanded,
            isResettingHostedFrame: false,
            isDragging: true
        ) == .detach)
    }

    @Test func collapsedBodyDoesNotRenderExpandedContentFragments() {
        #expect(!NotchHostedBodyPresentationPolicy.shouldRenderExpandedContent(
            bodyHeight: 0,
            contentOpacity: 0
        ))
        #expect(!NotchHostedBodyPresentationPolicy.shouldRenderExpandedContent(
            bodyHeight: 4,
            contentOpacity: 0.04
        ))
        #expect(NotchHostedBodyPresentationPolicy.shouldRenderExpandedContent(
            bodyHeight: 120,
            contentOpacity: 0.72
        ))
    }
}
