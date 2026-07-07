import Foundation

public enum ProviderAvailabilityStatus: String, Equatable, Sendable {
    case operational
    case degraded
    case down
    case unknown
}

public enum ProviderStatusPolicy {
    public static func statusPageStatus(indicator: String) -> ProviderAvailabilityStatus {
        switch indicator {
        case "none":
            return .operational
        case "minor":
            return .degraded
        case "major", "critical":
            return .down
        default:
            return .unknown
        }
    }

    public static func endpointStatus(forHTTPStatusCode statusCode: Int) -> ProviderAvailabilityStatus {
        switch statusCode {
        case 200..<300:
            return .operational
        case 401, 403, 405:
            return .unknown
        case 429:
            return .degraded
        case 500...:
            return .down
        default:
            return .unknown
        }
    }
}
