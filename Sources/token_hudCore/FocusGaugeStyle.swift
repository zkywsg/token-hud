// Sources/token_hudCore/FocusGaugeStyle.swift

/// Visual treatment for the focus card's main usage gauge. All styles share the
/// same "flowing light" language as the card's edge glow — none of them use hard
/// segmented bars.
public enum FocusGaugeStyle: String, CaseIterable, Sendable {
    /// Continuous glowing bar with a highlight sweeping along it.
    case glowBar
    /// Continuous sine wave with a soft glow pool underneath.
    case wave
    /// Edgeless drifting light haze.
    case aurora
    /// Rounded glowing columns with a bright pulse travelling through them.
    case softDots
    /// Capsule holding a sloshing liquid surface.
    case liquid
    /// Glowing particles streaming along a track.
    case particles
    /// Sweeping arc, like a horizon, with a light travelling along it.
    case arc
    /// Several thin light strands flowing and crossing in parallel.
    case fiber

    public static let `default` = FocusGaugeStyle.wave

    /// Tolerant parse for the stored preference; unknown values fall back.
    public static func from(_ raw: String) -> FocusGaugeStyle {
        FocusGaugeStyle(rawValue: raw) ?? .default
    }

    public var displayName: String {
        switch self {
        case .glowBar:   return "流光条"
        case .wave:      return "流动波浪"
        case .aurora:    return "极光"
        case .softDots:  return "柔光点"
        case .liquid:    return "液态"
        case .particles: return "粒子流"
        case .arc:       return "光弧"
        case .fiber:     return "光纤束"
        }
    }
}
