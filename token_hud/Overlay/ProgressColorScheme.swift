import SwiftUI

/// Shared progress color thresholds and RGB values used across
/// overlay tiles, widgets, hosted surface, and settings previews.
///
/// All progress indicators should use this instead of inline color definitions
/// to keep the red/yellow/green language consistent throughout the app.
enum ProgressColorScheme {
    // MARK: - Thresholds

    /// Usage at or above this fraction is considered "high" (red).
    static let highThreshold: Double = 0.85

    /// Usage at or above this fraction is considered "medium" (yellow).
    /// Below this is "low" (green).
    static let mediumThreshold: Double = 0.65

    // MARK: - Colors

    static let highColor = Color(red: 1.0, green: 0.28, blue: 0.34)
    static let mediumColor = Color(red: 1.0, green: 0.78, blue: 0.22)
    static let lowColor = Color(red: 0.28, green: 0.84, blue: 0.52)

    // MARK: - Lookup

    /// Returns the appropriate color for the given usage fraction (0...1).
    /// - `usage >= 0.85` → red
    /// - `usage >= 0.65` → yellow
    /// - otherwise → green
    static func color(for usage: Double) -> Color {
        let u = min(1, max(0, usage))
        if u >= highThreshold { return highColor }
        if u >= mediumThreshold { return mediumColor }
        return lowColor
    }
}
