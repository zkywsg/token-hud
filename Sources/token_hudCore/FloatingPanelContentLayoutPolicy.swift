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
    static let groupedModelCardHeaderHeight: CGFloat = 32
    static let groupedModelCardWidgetRowHeight: CGFloat = 52
    static let groupedModelCardWidgetsPerRow = 3
    static let groupedModelCardSpacing: CGFloat = 8
    static let groupedModelCardVerticalPadding: CGFloat = 20
    /// Real service card grid uses 1 adaptive column.
    static let groupedModelCardEstimatedColumns = 1
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
        serviceCount: Int,
        widgetCount: Int = 0
    ) -> CGFloat {
        let idealHeight: CGFloat
        if overlayMode == "grouped" {
            idealHeight = groupedModelCardIdealHeight(serviceCount: serviceCount, widgetCount: widgetCount)
        } else {
            idealHeight = compactIdealHeight
        }

        return (panelHeight / idealHeight)
            .clamped(to: minimumAdaptiveScale...maximumAdaptiveScale)
    }

    static func groupedModelCardIdealHeight(serviceCount: Int, widgetCount: Int = 0) -> CGFloat {
        let services = max(1, serviceCount)
        let avgWidgets = services > 0 ? Double(max(widgetCount, services)) / Double(services) : 1.0
        let widgetRowsPerCard = max(1, Int(ceil(avgWidgets / Double(groupedModelCardWidgetsPerRow))))
        let singleCardHeight = groupedModelCardHeaderHeight + CGFloat(widgetRowsPerCard) * groupedModelCardWidgetRowHeight
        let totalCardHeight = CGFloat(services) * singleCardHeight
        let totalSpacing = CGFloat(max(0, services - 1)) * groupedModelCardSpacing
        return totalCardHeight + totalSpacing + groupedModelCardVerticalPadding
    }
}
