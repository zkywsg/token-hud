import CoreGraphics

enum PanelResizeCalculator {
    static let minimumSize = CGSize(width: 120, height: 40)

    static func bottomRightFrame(
        from initialFrame: CGRect,
        dragDelta: CGSize,
        minSize: CGSize = minimumSize
    ) -> CGRect {
        let width = max(minSize.width, initialFrame.width + dragDelta.width)
        let height = max(minSize.height, initialFrame.height - dragDelta.height)

        return CGRect(
            x: initialFrame.minX,
            y: initialFrame.maxY - height,
            width: width,
            height: height
        )
    }
}
