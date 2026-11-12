import Foundation

/// Only the current task occurrence. Kept in the board so undo does not depend
/// on the device-local daily reward cache or the task's subsequently edited price.
struct TaskRewardReceipt: Codable, Equatable {
    struct ReversalCredit: Codable, Equatable {
        var dateKey: String
        var points: Int
    }

    var instanceID: UUID
    var awardedPoints: Int
    var reversalCredit: ReversalCredit?

    init(instanceID: UUID = UUID(), awardedPoints: Int, reversalCredit: ReversalCredit? = nil) {
        self.instanceID = instanceID
        self.awardedPoints = awardedPoints
        self.reversalCredit = reversalCredit
    }
}
