// token_hud/Overlay/SolidPanelBackground.swift
import SwiftUI

/// Shared "solid dark gradient card" surface used by the detached floating
/// panel and the hosted expanded body. Deliberately near-opaque (no frosted
/// blur) so the card reads as a solid object over any desktop background,
/// matching the reference product's texture.
struct SolidPanelBackground<S: Shape>: View {
    let shape: S
    /// 0 while collapsed, 1 while fully expanded — drives border/shadow strength.
    var prominence: CGFloat = 1

    var body: some View {
        ZStack {
            shape
                .fill(Theme.SurfaceLevel.raised.gradient)
            shape
                .stroke(Theme.Palette.borderSubtle.opacity(1.2 * prominence), lineWidth: 0.8)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.35 * prominence), radius: 16, y: 8)
    }
}
