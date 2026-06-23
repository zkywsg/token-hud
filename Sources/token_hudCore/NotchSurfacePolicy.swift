enum SkyLightReturnCodePolicy {
    static let successCode: Int32 = 0

    static func isSuccess(_ returnCode: Int32) -> Bool {
        returnCode == successCode
    }

    static func isSpaceReady(
        setAbsoluteLevel: Int32?,
        showSpaces: Int32?
    ) -> Bool {
        guard let setAbsoluteLevel, let showSpaces else { return false }
        return isSuccess(setAbsoluteLevel) && isSuccess(showSpaces)
    }

    static func didDelegateWindow(returnCode: Int32?) -> Bool {
        guard let returnCode else { return false }
        return isSuccess(returnCode)
    }
}

enum NotchSurfaceStrategyKind: Equatable {
    case skyLightSpace
    case publicPanel
}

enum NotchSurfaceWindowLevelKind: Equatable {
    case statusBar
    case mainMenuPlus(Int)
    case screenSaver
}

enum NotchSurfaceLevelPolicy {
    static func levelKind(for strategy: NotchSurfaceStrategyKind) -> NotchSurfaceWindowLevelKind {
        switch strategy {
        case .skyLightSpace:
            .mainMenuPlus(3)
        case .publicPanel:
            .statusBar
        }
    }
}

enum NotchHoverAction: Equatable {
    case expand
    case scheduleCollapse
    case cancelCollapse
    case none
}

enum NotchTransitionPolicy {
    static func hoverAction(
        isMouseInside: Bool,
        mode: NotchHostMode
    ) -> NotchHoverAction {
        switch (isMouseInside, mode) {
        case (true, .collapsed):
            .expand
        case (true, .expanded):
            .cancelCollapse
        case (false, .expanded):
            .scheduleCollapse
        default:
            .none
        }
    }
}

enum NotchHoverRegionPolicy {
    static func isMouseInsideNotchRegion(
        mode: NotchHostMode,
        isInsideCollapsedHoverRegion: Bool,
        isInsideExpandedSurface: Bool
    ) -> Bool {
        switch mode {
        case .collapsed:
            isInsideCollapsedHoverRegion
        case .expanded:
            isInsideCollapsedHoverRegion || isInsideExpandedSurface
        case .detached:
            false
        }
    }
}

enum NotchMouseEventPolicy {
    static func shouldIgnoreWindowMouseEvents(mode: NotchHostMode) -> Bool {
        switch mode {
        case .collapsed, .expanded, .detached:
            false
        }
    }
}

enum NotchWindowMovementPolicy {
    static func isMovableByWindowBackground(mode: NotchHostMode) -> Bool {
        switch mode {
        case .collapsed, .expanded:
            false
        case .detached:
            true
        }
    }
}

enum NotchHostedResizeAction: Equatable {
    case ignore
    case reassertHostedFrame
    case detach
}

enum NotchHostedResizePolicy {
    static func action(
        mode: NotchHostMode,
        isResettingHostedFrame: Bool,
        isDragging: Bool
    ) -> NotchHostedResizeAction {
        guard mode == .collapsed || mode == .expanded else {
            return .ignore
        }
        if isResettingHostedFrame {
            return .ignore
        }
        if mode == .expanded && isDragging {
            return .detach
        }
        return .reassertHostedFrame
    }
}

enum NotchHostedBodyPresentationPolicy {
    static let minimumBodyHeight: Double = 12
    static let minimumContentOpacity: Double = 0.10

    static func shouldRenderExpandedContent(
        bodyHeight: Double,
        contentOpacity: Double
    ) -> Bool {
        bodyHeight >= minimumBodyHeight &&
            contentOpacity >= minimumContentOpacity
    }
}

enum NotchInfoEarPresentationPolicy {
    static let minimumExpandedOpacity: Double = 0.72
    static let textMinimumSlotWidth: Double = 42
    static let progressMinimumWidth: Double = 18
    static let progressMaximumWidth: Double = 54
    static let progressHorizontalInset: Double = 14

    static func opacity(contentOpacity: Double) -> Double {
        let collapsedOpacity = 1 - contentOpacity.clamped(to: 0...1)
        return max(minimumExpandedOpacity, collapsedOpacity)
    }

    static func showsText(slotWidth: Double, text: String) -> Bool {
        slotWidth >= textMinimumSlotWidth && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func progressWidth(slotWidth: Double) -> Double {
        max(
            progressMinimumWidth,
            min(progressMaximumWidth, slotWidth - progressHorizontalInset)
        )
    }
}

struct NotchTransitionGate: Equatable {
    private(set) var generation: Int = 0

    @discardableResult
    mutating func advance() -> Int {
        generation &+= 1
        return generation
    }

    func isCurrent(_ token: Int) -> Bool {
        token == generation
    }
}

enum NotchPanelLifecycleEvent: Equatable {
    case hide
    case teardown
    case switchToDetached
}

struct NotchPanelLifecycleCleanup: Equatable {
    let cancelsCollapseTimer: Bool
    let removesMouseMoveMonitors: Bool
    let removesMouseDownMonitor: Bool
    let removesMouseUpMonitor: Bool
    let resetsDraggingState: Bool
}

enum NotchPanelLifecyclePolicy {
    static func cleanup(for event: NotchPanelLifecycleEvent) -> NotchPanelLifecycleCleanup {
        switch event {
        case .hide, .teardown:
            NotchPanelLifecycleCleanup(
                cancelsCollapseTimer: true,
                removesMouseMoveMonitors: true,
                removesMouseDownMonitor: true,
                removesMouseUpMonitor: true,
                resetsDraggingState: true
            )
        case .switchToDetached:
            NotchPanelLifecycleCleanup(
                cancelsCollapseTimer: true,
                removesMouseMoveMonitors: true,
                removesMouseDownMonitor: true,
                removesMouseUpMonitor: false,
                resetsDraggingState: false
            )
        }
    }
}
