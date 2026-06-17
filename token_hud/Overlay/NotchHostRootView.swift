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
    }
}
