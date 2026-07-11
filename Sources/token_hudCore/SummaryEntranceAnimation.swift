public enum SummaryEntranceAnimation {
    public static let itemDuration = 0.10
    public static let staggerDelay = 0.025
    public static let maximumStaggeredIndex = 6

    public static func delay(
        rowIndex: Int,
        reduceMotion: Bool
    ) -> Double {
        guard !reduceMotion else { return 0 }
        let staggeredIndex = min(max(rowIndex, 0), maximumStaggeredIndex)
        return Double(staggeredIndex) * staggerDelay
    }

    public static func shouldAnimate(previous: Bool?, current: Bool?) -> Bool {
        previous == false && current == true
    }
}
