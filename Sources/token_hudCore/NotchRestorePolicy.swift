import CoreGraphics

enum NotchRestoreMode: Equatable {
    case hostedCollapsed
    case detached(CGRect)
}

enum NotchRestorePolicy {
    static func restoreMode(
        savedMode: String?,
        savedDetachedFrame: CGRect?,
        screenFrame: CGRect,
        frames: NotchFrames
    ) -> NotchRestoreMode {
        guard savedMode == "detached" else {
            return .hostedCollapsed
        }

        guard let savedDetachedFrame,
              !NotchGeometryCalculator.shouldDiscardSavedDetachedFrame(
                savedDetachedFrame,
                screenFrame: screenFrame,
                frames: frames
              )
        else {
            return .hostedCollapsed
        }

        return .detached(savedDetachedFrame)
    }
}
