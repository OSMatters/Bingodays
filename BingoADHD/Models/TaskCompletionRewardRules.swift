import Foundation

/// No subscription, persistence, scheduling or UI dependencies.
enum TaskCompletionRewardRules {
    static let allowedPoints = 1...99

    static func normalizedConfiguration(_ value: Int?) -> Int? {
        guard let value, allowedPoints.contains(value), value != 1 else { return nil }
        return value
    }

    static func allows(_ edit: TaskRewardEdit, hasPremiumAccess: Bool) -> Bool {
        switch edit {
        case .unchanged, .useDefault: return true
        case let .custom(points): return allowedPoints.contains(points) && (points == 1 || hasPremiumAccess)
        }
    }

    static func applyingEdit(
        _ edit: TaskRewardEdit, previous: BingoCell, updated: BingoCell,
        legacyReversalCredit: Int? = nil, dateKey: String
    ) -> BingoCell {
        var cell = updated
        guard cell.hasStoredTask else {
            cell.customCompletionPoints = nil
            cell.taskRewardReceipt = nil
            return cell
        }
        switch edit {
        case .unchanged: break
        case .useDefault: cell.customCompletionPoints = nil
        case let .custom(points): cell.customCompletionPoints = normalizedConfiguration(points)
        }
        // An already rewarded legacy occurrence was worth ONE point, regardless
        // of the new configuration. A zero reversal credit is still a receipt.
        if cell.taskRewardReceipt == nil,
           cell.customCompletionPoints != nil,
           previous.isCompleted || legacyReversalCredit != nil {
            cell.taskRewardReceipt = TaskRewardReceipt(
                awardedPoints: 1,
                reversalCredit: legacyReversalCredit.map { .init(dateKey: dateKey, points: $0) }
            )
        }
        return cell
    }

    static func usesCustomSettlement(previous: BingoCell, current: BingoCell) -> Bool {
        previous.customCompletionPoints != nil || current.customCompletionPoints != nil ||
            previous.taskRewardReceipt != nil || current.taskRewardReceipt != nil
    }

    struct Transition {
        var pointsDelta: Int
        var lifetimeDelta: Int
        var receipt: TaskRewardReceipt
    }

    static func transition(
        previous: BingoCell, current: BingoCell, dateKey: String,
        availableToDeduct: Int, legacyReversalCredit: Int?
    ) -> Transition {
        var receipt = previous.taskRewardReceipt ?? current.taskRewardReceipt ?? TaskRewardReceipt(
            awardedPoints: previous.isCompleted || legacyReversalCredit != nil
                ? 1 : (normalizedConfiguration(current.customCompletionPoints) ?? 1)
        )
        // Defensive decoding: a malformed imported receipt must not mint points.
        receipt.awardedPoints = min(max(receipt.awardedPoints, 1), allowedPoints.upperBound)
        if current.isCompleted {
            let restored = receipt.reversalCredit.flatMap { $0.dateKey == dateKey ? $0.points : nil }
                ?? legacyReversalCredit
            let amount = restored.map { min(max($0, 0), receipt.awardedPoints) } ?? receipt.awardedPoints
            receipt.reversalCredit = nil
            return Transition(pointsDelta: amount, lifetimeDelta: amount, receipt: receipt)
        }
        let deducted = min(receipt.awardedPoints, max(availableToDeduct, 0))
        receipt.reversalCredit = .init(dateKey: dateKey, points: deducted)
        return Transition(pointsDelta: -deducted, lifetimeDelta: 0, receipt: receipt)
    }

    static func applyingReceipts(_ receipts: [UUID: TaskRewardReceipt], to cells: [[BingoCell]]) -> [[BingoCell]] {
        guard !receipts.isEmpty else { return cells }
        return cells.map { row in row.map { original in
            var cell = original
            if let receipt = receipts[cell.id] { cell.taskRewardReceipt = receipt }
            return cell
        } }
    }
}
