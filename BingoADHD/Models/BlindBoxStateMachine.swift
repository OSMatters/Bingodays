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

/// The reason candidates were reconciled. The repository records this alongside
/// a CloudKit operation later; keeping it explicit makes refreshes auditable and
/// prevents a UI refresh from silently changing a live batch.
enum BlindBoxCandidateRefreshReason: Equatable, Sendable {
    case initialLoad
    case restockCompleted
    case themeCompleted
    case membershipChanged
    case catalogChanged
}

struct BlindBoxCandidateReconciliationResult: Equatable, Sendable {
    let reason: BlindBoxCandidateRefreshReason
    let candidateCount: Int
    let restockedBatchIDs: [UUID]
    let removedBatchIDs: [UUID]
}

struct BlindBoxAutomaticOpenResult: Equatable, Sendable {
    let batchID: UUID
    let positionIndex: Int
    let soldOutAt: Date?
    let nextSystemOpenAt: Date?
}

enum BlindBoxCandidateCoordinatorError: Error, Equatable {
    case batchGeneration(BlindBoxBatchGenerationError)
}

/// Pure candidate-zone policy. A batch is immutable once created: an operation
/// may replace a completed/restocked candidate, but never changes its planned
/// sticker positions. The CloudKit repository will call these transitions only
/// after its transaction succeeds.
enum BlindBoxCandidateCoordinator {
    static func isThemeComplete(
        _ theme: BlindBoxThemeDefinition,
        ownedStickerCounts: [String: Int]
    ) -> Bool {
        theme.stickers.allSatisfy { sticker in
            (ownedStickerCounts[sticker.id.rawValue] ?? 0) > 0
        }
    }

    /// Applies the agreed refresh policy: restocked candidates get a new batch;
    /// completed or unavailable themes leave the candidate zone; membership then
    /// clamps/fills it to exactly four or six visible theme batches.
    @discardableResult
    static func reconcile<Generator: BlindBoxRandomNumberGenerating>(
        state: inout BlindBoxAccountState,
        themes: [BlindBoxThemeDefinition],
        hasPremiumAccess: Bool,
        reason: BlindBoxCandidateRefreshReason,
        now: Date,
        generator: inout Generator
    ) throws -> BlindBoxCandidateReconciliationResult {
        let availableThemes = themes.filter { theme in
            !isThemeComplete(theme, ownedStickerCounts: state.ownedStickerCounts)
        }
        let themesByID = Dictionary(uniqueKeysWithValues: availableThemes.map { ($0.id, $0) })
        var removedBatchIDs: [UUID] = []

        state.candidateBatches.removeAll { batch in
            let isAvailable = themesByID[batch.plan.themeID] != nil
            if !isAvailable {
                removedBatchIDs.append(batch.id)
            }
            return !isAvailable
        }

        var restockedBatchIDs: [UUID] = []
        for index in state.candidateBatches.indices {
            let batch = state.candidateBatches[index]
            guard batch.isSoldOut,
                  let restockAt = batch.restockAt(),
                  restockAt <= now,
                  let theme = themesByID[batch.plan.themeID] else {
                continue
            }
            let plan = try generatePlan(
                theme: theme,
                ownedStickerCounts: state.ownedStickerCounts,
                createdAt: now,
                generator: &generator
            )
            state.candidateBatches[index] = BlindBoxCandidateBatch(plan: plan)
            restockedBatchIDs.append(batch.id)
        }

        let targetCount = BlindBoxTicketPolicy.candidateCount(hasPremiumAccess: hasPremiumAccess)
        if state.candidateBatches.count > targetCount {
            let overflow = state.candidateBatches.dropFirst(targetCount)
            removedBatchIDs.append(contentsOf: overflow.map(\.id))
            state.candidateBatches = Array(state.candidateBatches.prefix(targetCount))
        }

        while state.candidateBatches.count < targetCount, !availableThemes.isEmpty {
            let themeIndex = try randomIndex(upperBound: availableThemes.count, generator: &generator)
            let theme = availableThemes[themeIndex]
            let plan = try generatePlan(
                theme: theme,
                ownedStickerCounts: state.ownedStickerCounts,
                createdAt: now,
                generator: &generator
            )
            state.candidateBatches.append(BlindBoxCandidateBatch(plan: plan))
        }

        return BlindBoxCandidateReconciliationResult(
            reason: reason,
            candidateCount: state.candidateBatches.count,
            restockedBatchIDs: restockedBatchIDs,
            removedBatchIDs: removedBatchIDs
        )
    }

    /// The first time a batch is actually visible in the candidate zone starts
    /// its private 45–180 minute system-open schedule. Creating a candidate is
    /// not enough: hidden candidates must not progress before the user can see
    /// them.
    static func recordFirstPresentation<Generator: BlindBoxRandomNumberGenerating>(
        state: inout BlindBoxAccountState,
        visibleBatchIDs: Set<UUID>,
        presentedAt: Date,
        generator: inout Generator
    ) {
        for index in state.candidateBatches.indices where visibleBatchIDs.contains(state.candidateBatches[index].id) {
            guard state.candidateBatches[index].firstPresentedAt == nil,
                  let delay = BlindBoxTicketPolicy.automaticOpenDelay(generator: &generator) else {
                continue
            }
            state.candidateBatches[index].firstPresentedAt = presentedAt
            state.candidateBatches[index].nextSystemOpenAt = presentedAt.addingTimeInterval(delay)
        }
    }

    /// Opens at most one already-visible box position. It never grants a
    /// sticker, never consumes a ticket, and will not consume the last open
    /// position across the entire candidate zone—so automated activity always
    /// leaves at least one box position for the user to open.
    static func processOneAutomaticOpen<Generator: BlindBoxRandomNumberGenerating>(
        state: inout BlindBoxAccountState,
        now: Date,
        generator: inout Generator
    ) -> BlindBoxAutomaticOpenResult? {
        let totalRemaining = state.candidateBatches.reduce(0) { $0 + $1.remainingPositionCount }
        guard totalRemaining > 1 else { return nil }

        guard let batchIndex = state.candidateBatches.indices.first(where: { index in
            let batch = state.candidateBatches[index]
            guard !batch.isSoldOut,
                  batch.firstPresentedAt != nil,
                  let nextSystemOpenAt = batch.nextSystemOpenAt else {
                return false
            }
            return nextSystemOpenAt <= now
        }) else {
            return nil
        }

        var batch = state.candidateBatches[batchIndex]
        guard !batch.unopenedPositionPlans.isEmpty,
              let positionIndex = randomIndexIfValid(
                upperBound: batch.unopenedPositionPlans.count,
                generator: &generator
              ) else {
            return nil
        }

        let position = batch.unopenedPositionPlans[positionIndex]
        batch.openedPositionIndices.insert(position.index)
        batch.systemOpenedPositionIndices.insert(position.index)

        if batch.isSoldOut {
            batch.soldOutAt = now
            batch.nextSystemOpenAt = nil
        } else if let delay = BlindBoxTicketPolicy.automaticOpenDelay(generator: &generator) {
            batch.nextSystemOpenAt = now.addingTimeInterval(delay)
        }

        state.candidateBatches[batchIndex] = batch
        return BlindBoxAutomaticOpenResult(
            batchID: batch.id,
            positionIndex: position.index,
            soldOutAt: batch.soldOutAt,
            nextSystemOpenAt: batch.nextSystemOpenAt
        )
    }

    private static func generatePlan<Generator: BlindBoxRandomNumberGenerating>(
        theme: BlindBoxThemeDefinition,
        ownedStickerCounts: [String: Int],
        createdAt: Date,
        generator: inout Generator
    ) throws -> BlindBoxBatchPlan {
        do {
            return try BlindBoxBatchGenerator.generate(
                theme: theme,
                ownedCounts: Dictionary(
                    uniqueKeysWithValues: theme.stickers.map { sticker in
                        (sticker.id, ownedStickerCounts[sticker.id.rawValue] ?? 0)
                    }
                ),
                createdAt: createdAt,
                generator: &generator
            )
        } catch let error as BlindBoxBatchGenerationError {
            throw BlindBoxCandidateCoordinatorError.batchGeneration(error)
        } catch {
            preconditionFailure("BlindBoxBatchGenerator returned an unexpected error: \(error)")
        }
    }

    private static func randomIndex<Generator: BlindBoxRandomNumberGenerating>(
        upperBound: Int,
        generator: inout Generator
    ) throws -> Int {
        guard let index = randomIndexIfValid(upperBound: upperBound, generator: &generator) else {
            throw BlindBoxCandidateCoordinatorError.batchGeneration(.invalidRandomValue)
        }
        return index
    }

    private static func randomIndexIfValid<Generator: BlindBoxRandomNumberGenerating>(
        upperBound: Int,
        generator: inout Generator
    ) -> Int? {
        guard upperBound > 0 else { return nil }
        let value = generator.nextUnitInterval()
        guard value >= 0, value < 1 else { return nil }
        return min(Int(value * Double(upperBound)), upperBound - 1)
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
