/// The pager's rendering window, independent of board selection or business rules.
enum BoardSwipePageWindow {
    static func range(
        boardCount: Int,
        activeIndex: Int?,
        settledIndex: Int?,
        retainedRange: Range<Int> = 0..<0,
        visibleIndex: Int? = nil
    ) -> Range<Int> {
        guard boardCount > 0 else { return 0..<0 }
        let active = min(max(activeIndex ?? 0, 0), boardCount - 1)
        let settled = min(max(settledIndex ?? active, 0), boardCount - 1)
        var lower = max(min(active, settled) - 1, 0)
        var upper = min(max(active, settled) + 2, boardCount)
        // A wide-window drag can expose more than one neighboring page before release.
        if let visibleIndex {
            lower = max(min(lower, visibleIndex), 0)
            upper = min(max(upper, visibleIndex + 2), boardCount)
        }
        guard !retainedRange.isEmpty else { return lower..<upper }
        return max(min(lower, retainedRange.lowerBound), 0)..<min(max(upper, retainedRange.upperBound), boardCount)
    }
}
