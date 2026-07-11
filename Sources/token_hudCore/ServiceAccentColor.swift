// Sources/token_hudCore/ServiceAccentColor.swift

/// A platform-agnostic RGB color used to give each AI service a stable, recognizable
/// accent independent of any usage/quota status color.
public struct ServiceAccentColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Stable per-service accent color, used for identification (icon tint, accent bars),
/// never for usage/quota warnings. Unknown services fall back to a neutral gray.
public func serviceAccentColor(for service: String) -> ServiceAccentColor {
    switch service.lowercased() {
    case "claude":    return ServiceAccentColor(red: 0.85, green: 0.47, blue: 0.34) // terracotta
    case "openai":    return ServiceAccentColor(red: 0.06, green: 0.64, blue: 0.50) // emerald
    case "codex":     return ServiceAccentColor(red: 0.31, green: 0.66, blue: 0.87) // sky blue
    case "gemini":    return ServiceAccentColor(red: 0.49, green: 0.44, blue: 0.94) // indigo
    case "deepseek":  return ServiceAccentColor(red: 0.18, green: 0.71, blue: 0.69) // teal
    case "anthropic": return ServiceAccentColor(red: 0.79, green: 0.48, blue: 0.24) // amber
    case "minimax":   return ServiceAccentColor(red: 0.88, green: 0.38, blue: 0.62) // magenta
    case "mimo":      return ServiceAccentColor(red: 0.95, green: 0.65, blue: 0.35) // marigold
    default:          return ServiceAccentColor(red: 0.60, green: 0.60, blue: 0.63) // neutral gray
    }
}
