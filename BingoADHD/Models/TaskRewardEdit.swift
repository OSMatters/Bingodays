import Foundation

/// Omission must preserve the saved setting, including for existing edit callers.
enum TaskRewardEdit: Equatable {
    case unchanged
    case useDefault
    case custom(Int)
}
