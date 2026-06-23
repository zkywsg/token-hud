import CoreGraphics

enum FloatingPanelContentAnchor: Equatable {
    case top
    case center
}

struct FloatingPanelContentLayout: Equatable {
    let verticalPlacement: FloatingPanelContentAnchor
    let scaleAnchor: FloatingPanelContentAnchor
}

enum FloatingPanelContentLayoutPolicy {
    static let compactIdealHeight: CGFloat = 60
    static let groupedModelCardRowHeight: CGFloat = 86
    static let groupedModelCardSpacing: CGFloat = 8
    static let groupedModelCardVerticalPadding: CGFloat = 20
    static let groupedModelCardEstimatedColumns = 2
    static let minimumAdaptiveScale: CGFloat = 0.72
    static let maximumAdaptiveScale: CGFloat = 1.35

    static func layout() -> FloatingPanelContentLayout {
        FloatingPanelContentLayout(
            verticalPlacement: .top,
            scaleAnchor: .top
        )
    }

    static func adaptiveScale(
        panelHeight: CGFloat,
        overlayMode: String,
        serviceCount: Int
    ) -> CGFloat {
        let idealHeight: CGFloat
        if overlayMode == "grouped" {
            idealHeight = groupedModelCardIdealHeight(serviceCount: serviceCount)
        } else {
            idealHeight = compactIdealHeight
        }

        return (panelHeight / idealHeight)
            .clamped(to: minimumAdaptiveScale...maximumAdaptiveScale)
    }

    static func groupedModelCardIdealHeight(serviceCount: Int) -> CGFloat {
        let cardCount = max(1, serviceCount)
        let rowCount = Int(ceil(Double(cardCount) / Double(groupedModelCardEstimatedColumns)))
        let rowSpacing = CGFloat(max(0, rowCount - 1)) * groupedModelCardSpacing
        return CGFloat(rowCount) * groupedModelCardRowHeight + rowSpacing + groupedModelCardVerticalPadding
    }
}
