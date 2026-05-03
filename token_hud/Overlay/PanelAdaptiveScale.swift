import SwiftUI

private struct PanelAdaptiveScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var panelAdaptiveScale: CGFloat {
        get { self[PanelAdaptiveScaleKey.self] }
        set { self[PanelAdaptiveScaleKey.self] = newValue }
    }
}
