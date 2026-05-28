import AppKit
import CoreGraphics

enum NotchSurfaceStrategy: String {
    case skyLightSpace
    case publicPanel

    var windowLevel: NSWindow.Level {
        switch self {
        case .skyLightSpace:
            NSWindow.Level.mainMenu + 3
        case .publicPanel:
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

