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

    @Test func hostedModesKeepWindowMouseEventsEnabledForHitMask() {
        #expect(!NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: .collapsed))
        #expect(!NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: .expanded))
    }

    @Test func detachedModeKeepsWindowMouseEventsEnabledForDragging() {
        #expect(!NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: .detached))
    }

    @Test func transitionGateInvalidatesOlderTokens() {
        var gate = NotchTransitionGate()
        let old = gate.advance()
        let current = gate.advance()

        #expect(!gate.isCurrent(old))
        #expect(gate.isCurrent(current))
    }
}
