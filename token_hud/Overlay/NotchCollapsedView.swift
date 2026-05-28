import SwiftUI

/// Collapsed view: single full-width panel with ears at top (menu bar area)
/// and thin body strip below notch. Panel top is at screen.maxY.
struct NotchCollapsedView: View {
    @Environment(NotchHostState.self) private var hostState

    var body: some View {
        VStack(spacing: 0) {
            // Body: thin strip below notch
            Rectangle()
                .fill(Color.black)
                .frame(height: NotchGeometryCalculator.collapsedBodyHeight)

            // Ears: cover menu bar on each side of notch
            NotchEarView()
        }
    }
}
