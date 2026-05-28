import SwiftUI

struct NotchHostRootView: View {
    @Environment(NotchHostState.self) private var hostState

    var body: some View {
        Group {
            switch hostState.mode {
            case .collapsed:
                NotchFusionView()
            case .expanded:
                NotchFusionView()
            case .detached:
                FloatingPanelView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hostState.mode)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: hostState.expansionProgress)
    }
}
