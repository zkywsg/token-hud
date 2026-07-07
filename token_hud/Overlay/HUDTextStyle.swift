import SwiftUI

/// Shared text opacity tokens for the HUD's white-on-black design system.
/// Used by overlay tiles, widgets, and settings previews.
enum HUDTextStyle {
    /// Primary text (metric values, key numbers). Highest contrast.
    static let primary = Color.white.opacity(0.94)

    /// Secondary text (service labels, group titles).
    static let secondary = Color.white.opacity(0.72)

    /// Tertiary text (sublabels, descriptions).
    static let tertiary = Color.white.opacity(0.56)

    /// Placeholder / hint text (empty states, hints).
    static let placeholder = Color.white.opacity(0.45)

    /// Subtle text (counts, minor annotations).
    static let subtle = Color.white.opacity(0.42)
}
