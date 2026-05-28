import SwiftUI

/// Draws left and right black ear rectangles flanking the notch gap.
/// Used inside the full-width body panel to cover the menu bar area.
struct NotchEarView: View {
    @Environment(NotchHostState.self) private var hostState

    var body: some View {
        GeometryReader { geo in
            let gapMinX = hostState.geometry?.notchGapMinX ?? geo.size.width / 2 - 50
            let gapMaxX = hostState.geometry?.notchGapMaxX ?? geo.size.width / 2 + 50
            let menuBarH = hostState.geometry?.menuBarHeight ?? 24

            HStack(spacing: 0) {
                // Left ear
                Rectangle()
                    .fill(Color.black)
                    .frame(width: gapMinX, height: menuBarH)

                // Gap (transparent — camera area)
                Spacer()
                    .frame(width: gapMaxX - gapMinX)

                // Right ear
                Rectangle()
                    .fill(Color.black)
                    .frame(width: geo.size.width - gapMaxX, height: menuBarH)
            }
        }
        .frame(height: menuBarHeight)
    }

    private var menuBarHeight: CGFloat {
        hostState.geometry?.menuBarHeight ?? 24
    }
}
