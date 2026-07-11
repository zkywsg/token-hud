public enum SummaryEntranceAnimation {
    public static let contentStart = 0.58
    public static let staggerStep = 0.025
    public static let maximumStaggeredIndex = 6

    public static func progress(
        expansion: Double,
        rowIndex: Int,
        reduceMotion: Bool
    ) -> Double {
        let expansion = min(max(expansion, 0), 1)
        let staggeredIndex = reduceMotion ? 0 : min(max(rowIndex, 0), maximumStaggeredIndex)
        let rowStart = contentStart + Double(staggeredIndex) * staggerStep
        let progress = (expansion - rowStart) / (1 - rowStart)

        return min(max(progress, 0), 1)
    }
}
