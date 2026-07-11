// token_hud/Widgets/ServiceColor+SwiftUI.swift
import SwiftUI

extension Color {
    init(_ accent: ServiceAccentColor) {
        self.init(red: accent.red, green: accent.green, blue: accent.blue)
    }
}

/// SwiftUI-side accessor mirroring `serviceAccentColor(for:)`, for use in widget and Settings views.
func serviceAccentSwiftUIColor(for service: String) -> Color {
    Color(serviceAccentColor(for: service))
}
