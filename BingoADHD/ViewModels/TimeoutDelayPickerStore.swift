enum TimeoutDelayPickerContext {
    case task
    case board
}

enum TimeoutDelayPickerStore {
    static func pickerComponents(from totalMinutes: Int, maxMinutes: Int) -> (hours: Int, minutes: Int) {
        let clampedMinutes = clamped(totalMinutes, maxMinutes: maxMinutes)

        guard clampedMinutes > 60 else {
            return (hours: 0, minutes: clampedMinutes)
        }

        let quotient = clampedMinutes / 60
        let remainder = clampedMinutes % 60
        guard remainder == 0 else {
            return (hours: quotient, minutes: remainder)
        }

        return (hours: max(quotient - 1, 0), minutes: 60)
    }

    static func totalMinutes(hours: Int, minutes: Int, maxMinutes: Int) -> Int {
        clamped((hours * 60) + minutes, maxMinutes: maxMinutes)
    }

    private static func clamped(_ totalMinutes: Int, maxMinutes: Int) -> Int {
        min(max(totalMinutes, 1), maxMinutes)
    }
}
