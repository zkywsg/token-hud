import AppKit
import CoreGraphics

enum NotchSurfaceStrategy: String {
    case skyLightSpace
    case publicPanel

    var kind: NotchSurfaceStrategyKind {
        switch self {
        case .skyLightSpace:
            .skyLightSpace
        case .publicPanel:
            .publicPanel
        }
    }

    var windowLevel: NSWindow.Level {
        switch NotchSurfaceLevelPolicy.levelKind(for: kind) {
        case .statusBar:
            .statusBar
        case .mainMenuPlus(let offset):
            NSWindow.Level.mainMenu + offset
        case .screenSaver:
            .screenSaver
        }
    }
}

extension NSScreen {
    var tokenHUDDisplayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    var tokenHUDHasNotch: Bool {
        let leftAux = auxiliaryTopLeftArea ?? .null
        let rightAux = auxiliaryTopRightArea ?? .null
        return leftAux != .null && rightAux != .null && safeAreaInsets.top > 0
    }
}
