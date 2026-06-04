import SwiftUI

struct NotchHostRootView: View {
    @Environment(NotchHostState.self) private var hostState

    var body: some View {
        ZStack {
            if hostState.isHosted {
                NotchHostedSurfaceView()
                    .transition(.identity)
            } else {
                FloatingPanelView()
                    .transition(.identity)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: hostState.expansionProgress)
    }
}
