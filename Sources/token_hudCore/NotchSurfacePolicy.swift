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

enum NotchMouseEventPolicy {
    static func shouldIgnoreWindowMouseEvents(mode: NotchHostMode) -> Bool {
        switch mode {
        case .collapsed, .expanded, .detached:
            false
        }
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
