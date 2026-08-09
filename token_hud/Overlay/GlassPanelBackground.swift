// token_hud/Overlay/GlassPanelBackground.swift
import SwiftUI

/// Translucent "frosted glass" surface for the HUD's expanded body and the
/// detached floating panel. The host window is non-opaque (`isOpaque = false`,
/// clear background), so `.ultraThinMaterial` blurs the desktop *behind* the
/// window — giving the panel a real tool-app glass feel instead of a solid card.
///
/// The user's `hudOpacity` preference no longer changes the whole panel's alpha;
/// it drives how dense the dark tint on top of the blur is — low values read as
/// a heavier smoked glass, high values as clearer glass.
///
/// Under "Reduce Transparency" the blur is dropped for a near-solid dark fill so
/// text stays legible.
struct GlassPanelBackground<S: Shape>: View {
    let shape: S
    /// 0 while collapsed, 1 while fully expanded — drives border/shadow strength.
    var prominence: CGFloat = 1
    /// 0.2...1.0 from Settings. Lower = denser smoked glass.
    var opacity: CGFloat = 1

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Denser tint as the user lowers `hudOpacity`.
    private var tintAlpha: CGFloat {
        let clamped = min(1, max(0.2, opacity))
        return 0.14 + (1 - clamped) * 0.55
    }

    var body: some View {
        ZStack {
            if reduceTransparency {
                shape.fill(Theme.SurfaceLevel.raised.gradient)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(tintGradient)
            }
            shape.stroke(Color.white.opacity(0.14 * prominence), lineWidth: 0.5)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.28 * prominence), radius: 16, y: 8)
    }

    /// Subtle top-lit vertical tint so the glass reads as a physical pane.
    private var tintGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.10, blue: 0.13).opacity(tintAlpha * 0.85),
                Color(red: 0.06, green: 0.06, blue: 0.08).opacity(tintAlpha)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
