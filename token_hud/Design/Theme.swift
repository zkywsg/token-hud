// token_hud/Design/Theme.swift
import SwiftUI

/// Single source of truth for the app's visual language. Both the Settings
/// surfaces and the floating HUD read from these tokens so they render as one
/// coherent product instead of three ad-hoc material treatments.
enum Theme {

    // MARK: - Palette

    enum Palette {
        /// Deepest background layer (window / page base).
        static let surfaceBase = Color(red: 0.09, green: 0.09, blue: 0.11)
        /// Raised cards / panels sitting on the base.
        static let surfaceRaised = Color(red: 0.15, green: 0.15, blue: 0.17)
        /// Popovers / floating overlays above raised cards.
        static let surfaceOverlay = Color(red: 0.20, green: 0.20, blue: 0.23)

        static let borderSubtle = Color.white.opacity(0.10)
        static let borderStrong = Color.white.opacity(0.16)

        static let textPrimary = Color.white.opacity(0.92)
        static let textSecondary = Color.white.opacity(0.55)
        static let textTertiary = Color.white.opacity(0.40)

        /// Single brand accent for interactive emphasis (selection, focus).
        /// Deliberately periwinkle-indigo so it never collides with the green
        /// "configured/ok" status or any provider identity color.
        static let brandAccent = Color(red: 0.50, green: 0.52, blue: 0.98)

        static let statusOK = Color(red: 0.30, green: 0.80, blue: 0.48)
        static let statusWarn = Color(red: 1.0, green: 0.76, blue: 0.20)
        static let statusError = Color(red: 1.0, green: 0.28, blue: 0.34)
        static let statusIdle = Color(red: 0.60, green: 0.60, blue: 0.63)
    }

    // MARK: - Severity

    /// The one place green/yellow/red usage color is decided. Both the collapsed
    /// notch strip and the expanded usage bars read from here (via
    /// `UsageSeverity` in core), so a given usage fraction always reads as the
    /// same severity and color across the whole HUD.
    static func severityColor(for severity: UsageSeverity) -> Color {
        switch severity {
        case .ok:       return Palette.statusOK
        case .warn:     return Palette.statusWarn
        case .critical: return Palette.statusError
        }
    }

    /// Convenience: fraction (0...1, usage) straight to its severity color.
    static func severityColor(forFraction fraction: Double) -> Color {
        severityColor(for: UsageSeverity.forFraction(fraction))
    }

    // MARK: - Typography

    /// Named type ramp for the HUD so scattered `.system(size:)` literals
    /// converge on a few semantic steps. `scale` folds in the user's widget
    /// size preference; weights/designs stay fixed per role.
    enum Typography {
        /// Promoted hero metric (the big number on the first row).
        static func hero(_ scale: CGFloat) -> Font {
            .system(size: 26 * scale, weight: .semibold, design: .rounded)
        }
        /// Secondary-row metric value.
        static func value(_ scale: CGFloat) -> Font {
            .system(size: 16 * scale, weight: .semibold, design: .rounded)
        }
        /// Service / row name.
        static func title(_ scale: CGFloat) -> Font {
            .system(size: 12 * scale, weight: .semibold)
        }
        /// Muted metric sub-label under a title.
        static func caption(_ scale: CGFloat) -> Font {
            .system(size: 9 * scale, weight: .medium)
        }
        /// Monospaced detail line (rates, timestamps, amounts).
        static func mono(_ scale: CGFloat) -> Font {
            .system(size: 9 * scale, weight: .medium, design: .monospaced)
        }
    }

    // MARK: - Radius

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
    }

    // MARK: - Spacing (8pt grid)

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: - Surface levels

    enum SurfaceLevel {
        case base, raised, overlay

        var topColor: Color {
            switch self {
            case .base:    return Palette.surfaceBase.opacity(1)
            case .raised:  return Color(red: 0.16, green: 0.16, blue: 0.18)
            case .overlay: return Color(red: 0.22, green: 0.22, blue: 0.25)
            }
        }

        var bottomColor: Color {
            switch self {
            case .base:    return Color(red: 0.06, green: 0.06, blue: 0.08)
            case .raised:  return Color(red: 0.10, green: 0.10, blue: 0.12)
            case .overlay: return Color(red: 0.15, green: 0.15, blue: 0.18)
            }
        }

        /// Subtle top-to-bottom gradient that gives the surface a sense of
        /// being a solid physical object rather than a flat fill.
        var gradient: LinearGradient {
            LinearGradient(
                colors: [topColor, bottomColor],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Notch (dark) surface modifier

/// Applies the solid dark card treatment used by the HUD / notch-fused
/// surfaces: gradient fill, hairline border, soft drop shadow.
private struct ThemedCard: ViewModifier {
    var level: Theme.SurfaceLevel
    var cornerRadius: CGFloat
    var padding: CGFloat?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .padding(padding ?? 0)
            .background(shape.fill(level.gradient))
            .overlay(shape.stroke(Theme.Palette.borderSubtle, lineWidth: 0.8))
            .clipShape(shape)
            .shadow(color: Color.black.opacity(0.28), radius: 14, y: 6)
    }
}

extension View {
    /// Wraps the view in the dark notch-family card (HUD surfaces).
    func themedCard(
        level: Theme.SurfaceLevel = .raised,
        cornerRadius: CGFloat = Theme.Radius.md,
        padding: CGFloat? = Theme.Spacing.md
    ) -> some View {
        modifier(ThemedCard(level: level, cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Glass (Settings) surfaces

extension Theme {
    /// Frosted translucent background for the Settings window. Deliberately
    /// distinct from the dark notch HUD surfaces — Settings reads as a
    /// semi-transparent "tech glass" panel.
    struct GlassWindowBackground: View {
        var body: some View {
            ZStack {
                Rectangle().fill(.regularMaterial)
                Rectangle().fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            Color.white.opacity(0.06),
                            Color.black.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        }
    }
}

/// Frosted-glass card for Settings content (semi-transparent material + tint
/// + hairline border), the light counterpart to `themedCard`.
private struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat
    var padding: CGFloat?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .padding(padding ?? 0)
            .background(
                ZStack {
                    shape.fill(.thinMaterial)
                    shape.fill(Color.white.opacity(0.05))
                }
            )
            .overlay(shape.stroke(Theme.Palette.borderSubtle, lineWidth: 0.8))
            .clipShape(shape)
            .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
    }
}

extension View {
    /// Wraps the view in a frosted Settings glass card.
    func glassCard(
        cornerRadius: CGFloat = Theme.Radius.md,
        padding: CGFloat? = Theme.Spacing.md
    ) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, padding: padding))
    }
}
