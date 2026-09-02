import Foundation

/// Persisted per-account state for the blind-box feature. It is deliberately
/// independent of the legacy `StickerStore`: old direct-redemption stickers
/// remain readable while CloudKit migration maps them into this catalog.
struct BlindBoxAccountState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var ticketBalance: Int
    var ownedStickerCounts: [String: Int]
    var candidateBatches: [BlindBoxCandidateBatch]
    var lastTicketGrantDayIdentifier: String?
    var lastPointExchangeDayIdentifier: String?
    var pointExchangesUsedOnLastGrantDay: Int

    init(
        schemaVersion: Int = BlindBoxAccountState.currentSchemaVersion,
        ticketBalance: Int = 0,
        ownedStickerCounts: [String: Int] = [:],
        candidateBatches: [BlindBoxCandidateBatch] = [],
        lastTicketGrantDayIdentifier: String? = nil,
        lastPointExchangeDayIdentifier: String? = nil,
        pointExchangesUsedOnLastGrantDay: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.ticketBalance = min(max(ticketBalance, 0), BlindBoxRuleConfiguration.maximumTicketBalance)
        self.ownedStickerCounts = ownedStickerCounts.reduce(into: [:]) { result, entry in
            guard entry.value > 0 else { return }
            result[entry.key] = entry.value
        }
        self.candidateBatches = candidateBatches
        self.lastTicketGrantDayIdentifier = lastTicketGrantDayIdentifier
        self.lastPointExchangeDayIdentifier = lastPointExchangeDayIdentifier
        self.pointExchangesUsedOnLastGrantDay = max(pointExchangesUsedOnLastGrantDay, 0)
    }

    func ownedCount(for stickerID: BlindBoxStickerID) -> Int {
        ownedStickerCounts[stickerID.rawValue] ?? 0
    }

    func ownedCounts(for theme: BlindBoxThemeDefinition) -> [BlindBoxStickerID: Int] {
        Dictionary(uniqueKeysWithValues: theme.stickers.map { sticker in
            (sticker.id, ownedCount(for: sticker.id))
        })
    }
}

/// A batch's plan is immutable; only visibility of already-planned positions
/// changes. System-opened positions never add to `ownedStickerCounts`.
struct BlindBoxCandidateBatch: Codable, Equatable, Identifiable, Sendable {
    let plan: BlindBoxBatchPlan
    var openedPositionIndices: Set<Int>
    var systemOpenedPositionIndices: Set<Int>
    var firstPresentedAt: Date?
    var nextSystemOpenAt: Date?
    var soldOutAt: Date?

    var id: UUID { plan.id }

    init(
        plan: BlindBoxBatchPlan,
        openedPositionIndices: Set<Int> = [],
        systemOpenedPositionIndices: Set<Int> = [],
        firstPresentedAt: Date? = nil,
        nextSystemOpenAt: Date? = nil,
        soldOutAt: Date? = nil
    ) {
        self.plan = plan
        self.openedPositionIndices = openedPositionIndices
        self.systemOpenedPositionIndices = systemOpenedPositionIndices
        self.firstPresentedAt = firstPresentedAt
        self.nextSystemOpenAt = nextSystemOpenAt
        self.soldOutAt = soldOutAt
    }

    var openedPositionPlans: [BlindBoxPositionPlan] {
        plan.positions.filter { openedPositionIndices.contains($0.index) }
    }

    var unopenedPositionPlans: [BlindBoxPositionPlan] {
        plan.positions.filter { !openedPositionIndices.contains($0.index) }
    }

    var remainingPositionCount: Int {
        unopenedPositionPlans.count
    }

    var isSoldOut: Bool {
        remainingPositionCount == 0
    }

    func position(at index: Int) -> BlindBoxPositionPlan? {
        plan.positions.first(where: { $0.index == index })
    }

    func isOpenedBySystem(at index: Int) -> Bool {
        systemOpenedPositionIndices.contains(index)
    }

    func restockAt() -> Date? {
        soldOutAt.map(BlindBoxTicketPolicy.restockDate)
    }
}

struct BlindBoxOpenedSticker: Codable, Equatable, Sendable {
    let positionIndex: Int
    let stickerID: BlindBoxStickerID
    let resultingOwnedCount: Int

    var isDuplicate: Bool {
        resultingOwnedCount > 1
    }
}

struct BlindBoxOpenResult: Codable, Equatable, Sendable {
    let batchID: UUID
    let openedStickers: [BlindBoxOpenedSticker]
    let ticketCost: Int
    let resultingTicketBalance: Int
    let restockAt: Date?
}

enum BlindBoxOpenError: Error, Equatable {
    case batchNotFound
    case positionNotFound
    case positionAlreadyOpened
    case batchSoldOut
    case insufficientTickets(required: Int, current: Int)
}

/// Pure transitions used by both the local presentation mock and the later
/// CloudKit-backed repository. The server will authoritatively apply the same
/// transitions with idempotency keys before the UI starts an animation.
enum BlindBoxStateMachine {
    static func openSingle(
        state: inout BlindBoxAccountState,
        batchID: UUID,
        positionIndex: Int,
        openedAt: Date
    ) throws -> BlindBoxOpenResult {
        guard let batchIndex = state.candidateBatches.firstIndex(where: { $0.id == batchID }) else {
            throw BlindBoxOpenError.batchNotFound
        }
        let batch = state.candidateBatches[batchIndex]
        guard !batch.isSoldOut else { throw BlindBoxOpenError.batchSoldOut }
        guard let position = batch.position(at: positionIndex) else {
            throw BlindBoxOpenError.positionNotFound
        }
        guard !batch.openedPositionIndices.contains(positionIndex) else {
            throw BlindBoxOpenError.positionAlreadyOpened
        }
        return try open(
            state: &state,
            batchIndex: batchIndex,
            positions: [position],
            openedAt: openedAt
        )
    }

    static func openWholeBox(
        state: inout BlindBoxAccountState,
        batchID: UUID,
        openedAt: Date
    ) throws -> BlindBoxOpenResult {
        guard let batchIndex = state.candidateBatches.firstIndex(where: { $0.id == batchID }) else {
            throw BlindBoxOpenError.batchNotFound
        }
        let batch = state.candidateBatches[batchIndex]
        guard !batch.isSoldOut else { throw BlindBoxOpenError.batchSoldOut }
        return try open(
            state: &state,
            batchIndex: batchIndex,
            positions: batch.unopenedPositionPlans,
            openedAt: openedAt
        )
    }

    private static func open(
        state: inout BlindBoxAccountState,
        batchIndex: Int,
        positions: [BlindBoxPositionPlan],
        openedAt: Date
    ) throws -> BlindBoxOpenResult {
        let ticketCost = positions.count
        guard state.ticketBalance >= ticketCost else {
            throw BlindBoxOpenError.insufficientTickets(required: ticketCost, current: state.ticketBalance)
        }

        var batch = state.candidateBatches[batchIndex]
        var openedStickers: [BlindBoxOpenedSticker] = []
        openedStickers.reserveCapacity(positions.count)

        for position in positions.sorted(by: { $0.index < $1.index }) {
            batch.openedPositionIndices.insert(position.index)
            let newCount = (state.ownedStickerCounts[position.stickerID.rawValue] ?? 0) + 1
            state.ownedStickerCounts[position.stickerID.rawValue] = newCount
            openedStickers.append(
                BlindBoxOpenedSticker(
                    positionIndex: position.index,
                    stickerID: position.stickerID,
                    resultingOwnedCount: newCount
                )
            )
        }

        state.ticketBalance -= ticketCost
        if batch.isSoldOut {
            batch.soldOutAt = openedAt
        }
        state.candidateBatches[batchIndex] = batch

        return BlindBoxOpenResult(
            batchID: batch.id,
            openedStickers: openedStickers,
            ticketCost: ticketCost,
            resultingTicketBalance: state.ticketBalance,
            restockAt: batch.restockAt()
        )
    }
}

enum BlindBoxGrantDay {
    /// 04:00 is the agreed grant-day boundary. The caller supplies the account
    /// calendar; CloudKit will eventually persist its time-zone identifier.
    static func identifier(for date: Date, calendar: Calendar) -> String {
        let adjustedDate = calendar.date(byAdding: .hour, value: -4, to: date) ?? date
        let components = calendar.dateComponents([.year, .month, .day], from: adjustedDate)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

/// Local persistence is only the development/mock implementation. Production
/// opening and currency changes will move to an idempotent CloudKit repository.
enum BlindBoxLocalStateStore {
    static func load(defaults: UserDefaults = .standard) -> BlindBoxAccountState {
        guard let data = defaults.data(forKey: AppSettings.blindBoxLocalStateKey),
              let state = try? JSONDecoder().decode(BlindBoxAccountState.self, from: data) else {
            return BlindBoxAccountState()
        }
        return BlindBoxAccountState(
            schemaVersion: state.schemaVersion,
            ticketBalance: state.ticketBalance,
            ownedStickerCounts: state.ownedStickerCounts,
            candidateBatches: state.candidateBatches,
            lastTicketGrantDayIdentifier: state.lastTicketGrantDayIdentifier,
            lastPointExchangeDayIdentifier: state.lastPointExchangeDayIdentifier,
            pointExchangesUsedOnLastGrantDay: state.pointExchangesUsedOnLastGrantDay
        )
    }

    @discardableResult
    static func save(
        _ state: BlindBoxAccountState,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else { return false }
        guard defaults.data(forKey: AppSettings.blindBoxLocalStateKey) != data else { return true }
        defaults.set(data, forKey: AppSettings.blindBoxLocalStateKey)
        return defaults.data(forKey: AppSettings.blindBoxLocalStateKey) == data
    }
}
