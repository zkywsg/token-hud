import CoreGraphics

enum NotchExpandedLayoutMode: String, CaseIterable, Equatable {
    case adaptive
    case sectioned

    init(rawStorageValue: String) {
        self = Self(rawValue: rawStorageValue) ?? .adaptive
    }
}

struct NotchExpandedLayoutMetrics: Equatable {
    let bodyHeight: CGFloat
    let contentScale: CGFloat
    let allowsVerticalScrolling: Bool
}

enum NotchExpandedLayoutPolicy {
    static let minimumBodyHeight: CGFloat = 110
    static let rowHeight: CGFloat = 32
    static let verticalPadding: CGFloat = 20
    static let modelCardHeight: CGFloat = 82
    static let modelCardHeaderHeight: CGFloat = 32
    static let modelCardWidgetRowHeight: CGFloat = 52
    static let modelCardWidgetsPerRow = 3
    static let modelCardSpacing: CGFloat = 8
    static let modelCardVerticalPadding: CGFloat = 20
    /// Real service card grid uses 1 adaptive column (min card width ≈ 238pt,
    /// notch content width ≈ 316pt), so cards always stack vertically.
    static let modelCardEstimatedColumns = 1
    static let sectionedBodyHeight: CGFloat = 136
    static let maxScreenHeightFraction: CGFloat = 0.38

    static func layout(
        mode: NotchExpandedLayoutMode,
        widgetCount: Int,
        serviceCount: Int,
        screenHeight: CGFloat,
        menuBarHeight: CGFloat
    ) -> NotchExpandedLayoutMetrics {
        let availableHeight = max(minimumBodyHeight, screenHeight - menuBarHeight)
        let maxBodyHeight = max(
            minimumBodyHeight,
            min(availableHeight, screenHeight * maxScreenHeightFraction)
        )

        switch mode {
        case .adaptive:
            let idealHeight = max(
                minimumBodyHeight,
                groupedContentHeight(serviceCount: serviceCount, widgetCount: widgetCount)
            )
            return NotchExpandedLayoutMetrics(
                bodyHeight: min(idealHeight, maxBodyHeight),
                contentScale: 1,
                allowsVerticalScrolling: idealHeight > maxBodyHeight
            )
        case .sectioned:
            let needsScrolling = max(widgetCount, serviceCount) > 8
            return NotchExpandedLayoutMetrics(
                bodyHeight: min(sectionedBodyHeight, maxBodyHeight),
                contentScale: 1,
                allowsVerticalScrolling: needsScrolling
            )
        }
    }

    private static func modelCardRows(for serviceCount: Int) -> Int {
        let count = max(1, serviceCount)
        return Int(ceil(Double(count) / Double(modelCardEstimatedColumns)))
    }

    /// Estimated total content height for grouped mode.
    /// Each service card gets its own row (1 column layout). Card height depends
    /// on widget count: header + ceil(widgets / widgetsPerRow) * widgetRowHeight.
    private static func groupedContentHeight(serviceCount: Int, widgetCount: Int) -> CGFloat {
        let services = max(1, serviceCount)
        let avgWidgets = services > 0 ? Double(widgetCount) / Double(services) : 1.0
        let widgetRowsPerCard = max(1, Int(ceil(avgWidgets / Double(modelCardWidgetsPerRow))))
        let singleCardHeight = modelCardHeaderHeight + CGFloat(widgetRowsPerCard) * modelCardWidgetRowHeight
        let totalCardHeight = CGFloat(services) * singleCardHeight
        let totalSpacing = CGFloat(max(0, services - 1)) * modelCardSpacing
        return totalCardHeight + totalSpacing + modelCardVerticalPadding
    }
}
