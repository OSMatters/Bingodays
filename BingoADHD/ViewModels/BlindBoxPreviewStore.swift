import SwiftUI

/// Gate A presentation data only. It lets the Figma flow be exercised without
/// touching the user's existing points, legacy stickers, or CloudKit records.
/// The later CloudKit repository will replace this object at the same view-model
/// boundary rather than changing the view hierarchy.
@MainActor
final class BlindBoxPreviewStore: ObservableObject, BlindBoxDrawRepository {
    private struct CompletedDraw {
        let request: BlindBoxDrawRequest
        let result: BlindBoxOpenResult
    }

    @Published private(set) var state: BlindBoxAccountState
    @Published private(set) var lastOpenResult: BlindBoxOpenResult?
    @Published private(set) var previewAvailablePoints: Int

    private var completedDraws: [UUID: CompletedDraw] = [:]

    let themes: [BlindBoxThemeDefinition]

    init(
        themes: [BlindBoxThemeDefinition] = BlindBoxCatalog.builtInThemes,
        previewAvailablePoints: Int = 320,
        referenceDate: Date = .now
    ) {
        self.themes = themes
        self.previewAvailablePoints = max(previewAvailablePoints, 0)
        self.state = Self.makeFixture(themes: themes, referenceDate: referenceDate)
#if DEBUG
        // Explicit preview-only regression fixtures; never applied to the live wallet.
        if AppDebugFlags.blindBoxPreviewEnabled {
            let environment = ProcessInfo.processInfo.environment
            if let value = environment["BLINDBOX_QA_POINTS"].flatMap(Int.init) {
                self.previewAvailablePoints = max(0, value)
            }
            if let value = environment["BLINDBOX_QA_TICKETS"].flatMap(Int.init) {
                self.state.ticketBalance = min(20, max(0, value))
                self.state.lastTicketGrantDayIdentifier = BlindBoxGrantDay.identifier(for: referenceDate, calendar: .current)
                self.state.settledDailyTicketAllowance = 1
                self.state.pendingTicketReceipt = nil
            }
            // Presentation fixtures only; lifecycle transitions are tested against
            // the production state machine and coordinator, not this preview store.
            if let collection = environment["BLINDBOX_QA_COLLECTION"],
               ["normals", "complete"].contains(collection) {
                self.state.ownedStickerCounts = Dictionary(uniqueKeysWithValues:
                    themes.flatMap { collection == "complete" ? $0.stickers : $0.normalStickers }
                        .map { ($0.id.rawValue, 1) })
                self.state.candidateBatches = []
                var generator = SystemBlindBoxRandomNumberGenerator()
                _ = try? BlindBoxCandidateCoordinator.reconcile(
                    state: &self.state, themes: themes, hasPremiumAccess: false,
                    reason: .initialLoad, now: referenceDate, generator: &generator
                )
            }
        }
#endif
    }

    func refreshTickets(hasPremiumAccess: Bool) {
        BlindBoxWalletStateMachine.refreshDailyTickets(
            state: &state, hasPremiumAccess: hasPremiumAccess, now: .now, calendar: .current
        )
    }

    func consumeTicketReceipt() -> BlindBoxTicketReceipt? {
        let receipt = state.pendingTicketReceipt
        state.pendingTicketReceipt = nil
        return receipt
    }

    func theme(for id: BlindBoxThemeID) -> BlindBoxThemeDefinition? {
        themes.first(where: { $0.id == id })
    }

    func candidates(hasPremiumAccess: Bool) -> [BlindBoxCandidateBatch] {
        Array(state.candidateBatches.prefix(BlindBoxTicketPolicy.candidateCount(hasPremiumAccess: hasPremiumAccess)))
    }

    func openSingle(batchID: UUID, positionIndex: Int, openedAt: Date = .now) throws -> BlindBoxOpenResult {
        let result = try BlindBoxStateMachine.openSingle(
            state: &state,
            batchID: batchID,
            positionIndex: positionIndex,
            openedAt: openedAt
        )
        lastOpenResult = result
        return result
    }

    func openWholeBox(batchID: UUID, openedAt: Date = .now) throws -> BlindBoxOpenResult {
        let result = try BlindBoxStateMachine.openWholeBox(
            state: &state,
            batchID: batchID,
            openedAt: openedAt
        )
        lastOpenResult = result
        return result
    }

    func open(_ request: BlindBoxDrawRequest) async throws -> BlindBoxOpenResult {
        if let completedDraw = completedDraws[request.idempotencyKey] {
            guard completedDraw.request == request else {
                throw BlindBoxDrawRepositoryError.idempotencyKeyConflict
            }
            return completedDraw.result
        }

        if let validationError = request.validationError() {
            throw validationError
        }
        if state.pendingReveal != nil {
            throw BlindBoxOpenError.pendingRevealMustBeAcknowledged
        }

        let result: BlindBoxOpenResult
        switch request.mode {
        case .single:
            guard let positionIndex = request.positionIndex else {
                throw BlindBoxDrawRequestValidationError.missingPositionIndex
            }
            result = try openSingle(
                batchID: request.batchID,
                positionIndex: positionIndex
            )
        case .wholeBox:
            result = try openWholeBox(batchID: request.batchID)
        }

        completedDraws[request.idempotencyKey] = CompletedDraw(
            request: request,
            result: result
        )
        state.pendingReveal = BlindBoxPendingReveal(
            drawIdempotencyKey: request.idempotencyKey,
            result: result
        )
        return result
    }

    func acknowledgePendingReveal(_ result: BlindBoxOpenResult) {
        guard state.pendingReveal?.result == result else { return }
        state.pendingReveal = nil
    }

    func count(for stickerID: BlindBoxStickerID) -> Int {
        state.ownedCount(for: stickerID)
    }

    func pointExchangeEligibility(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> BlindBoxPointExchangeEligibility {
        let currentGrantDay = BlindBoxGrantDay.identifier(for: now, calendar: calendar)
        let exchangesUsed = state.lastPointExchangeDayIdentifier == currentGrantDay
            ? state.pointExchangesUsedOnLastGrantDay
            : 0
        return BlindBoxPointExchangePolicy.eligibility(
            availablePoints: previewAvailablePoints,
            ticketBalance: state.ticketBalance,
            exchangesUsedThisGrantDay: exchangesUsed
        )
    }

    @discardableResult
    func exchangePointsForOneTicket(
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> BlindBoxPointExchangeResult {
        let result = try BlindBoxWalletStateMachine.exchangePointsForOneTicket(
            state: &state,
            availablePoints: previewAvailablePoints,
            now: now,
            calendar: calendar
        )
        previewAvailablePoints -= result.deductedPoints
        return result
    }

    private static func makeFixture(
        themes: [BlindBoxThemeDefinition],
        referenceDate: Date
    ) -> BlindBoxAccountState {
        guard let pets = themes.first(where: { $0.id.rawValue == "pets" }),
              let cozy = themes.first(where: { $0.id.rawValue == "cozy_daily" }) else {
            return BlindBoxAccountState(ticketBalance: BlindBoxRuleConfiguration.maximumTicketBalance)
        }

        let petsBatch = fixturePlan(
            id: "A0000000-0000-4000-8000-000000000001",
            theme: pets,
            stickerIDs: ["pets_01", "pets_02", "pets_03", "pets_04", "pets_05", "pets_11", "pets_07", "pets_08", "pets_09"],
            createdAt: referenceDate
        )
        let cozyBatch = fixturePlan(
            id: "A0000000-0000-4000-8000-000000000002",
            theme: cozy,
            stickerIDs: ["cozy_01", "cozy_02", "cozy_03", "cozy_04", "cozy_05", "cozy_06", "cozy_07", "cozy_08", "cozy_01"],
            createdAt: referenceDate
        )
        let petsSecondBatch = fixturePlan(
            id: "A0000000-0000-4000-8000-000000000003",
            theme: pets,
            stickerIDs: ["pets_10", "pets_04", "pets_08", "pets_06", "pets_11", "pets_03", "pets_05", "pets_02", "pets_01"],
            createdAt: referenceDate
        )
        let cozySecondBatch = fixturePlan(
            id: "A0000000-0000-4000-8000-000000000004",
            theme: cozy,
            stickerIDs: ["cozy_08", "cozy_07", "cozy_06", "cozy_05", "cozy_04", "cozy_03", "cozy_02", "cozy_01", "cozy_07"],
            createdAt: referenceDate
        )
        let petsThirdBatch = fixturePlan(
            id: "A0000000-0000-4000-8000-000000000005",
            theme: pets,
            stickerIDs: ["pets_09", "pets_10", "pets_08", "pets_07", "pets_06", "pets_05", "pets_04", "pets_03", "pets_02"],
            createdAt: referenceDate
        )
        let cozyThirdBatch = fixturePlan(
            id: "A0000000-0000-4000-8000-000000000006",
            theme: cozy,
            stickerIDs: ["cozy_02", "cozy_03", "cozy_04", "cozy_05", "cozy_06", "cozy_07", "cozy_08", "cozy_01", "cozy_04"],
            createdAt: referenceDate
        )

        let allIndices = Set(0..<BlindBoxRuleConfiguration.batchPositionCount)
        return BlindBoxAccountState(
            ticketBalance: BlindBoxRuleConfiguration.maximumTicketBalance - 1,
            ownedStickerCounts: [
                "pets_02": 1,
                "pets_03": 1,
                "pets_08": 1,
                "pets_09": 1,
                "pets_11": 1,
                "cozy_01": 1,
                "cozy_04": 1
            ],
            candidateBatches: [
                BlindBoxCandidateBatch(
                    plan: petsBatch,
                    openedPositionIndices: [5],
                    systemOpenedPositionIndices: [5],
                    firstPresentedAt: referenceDate,
                    nextSystemOpenAt: referenceDate.addingTimeInterval(90 * 60)
                ),
                // Preview the replenishment state inside the first four
                // candidate slots so both member and non-member test runs can
                // inspect the sold-out overlay and 24-hour countdown.
                BlindBoxCandidateBatch(
                    plan: cozySecondBatch,
                    openedPositionIndices: allIndices,
                    systemOpenedPositionIndices: allIndices,
                    firstPresentedAt: referenceDate.addingTimeInterval(-2 * 60 * 60),
                    soldOutAt: referenceDate.addingTimeInterval(-2 * 60 * 60)
                ),
                BlindBoxCandidateBatch(plan: themes.first(where: { $0.id.rawValue == "zodiac" }).map {
                    fixturePlan(id: "A0000000-0000-4000-8000-000000000007", theme: $0,
                                stickerIDs: (1...9).map { "zodiac_\(String(format: "%02d", $0))" }, createdAt: referenceDate)
                } ?? petsSecondBatch),
                BlindBoxCandidateBatch(plan: cozyThirdBatch),
                BlindBoxCandidateBatch(
                    plan: cozyBatch,
                    openedPositionIndices: allIndices,
                    systemOpenedPositionIndices: allIndices,
                    firstPresentedAt: referenceDate.addingTimeInterval(-3 * 60 * 60),
                    soldOutAt: referenceDate.addingTimeInterval(-3 * 60 * 60)
                ),
                BlindBoxCandidateBatch(plan: petsThirdBatch)
            ]
        )
    }

    private static func fixturePlan(
        id: String,
        theme: BlindBoxThemeDefinition,
        stickerIDs: [String],
        createdAt: Date
    ) -> BlindBoxBatchPlan {
        BlindBoxBatchPlan(
            id: UUID(uuidString: id)!,
            themeID: theme.id,
            catalogVersion: theme.catalogVersion,
            probabilityMode: .standard,
            createdAt: createdAt,
            positions: stickerIDs.enumerated().map { index, stickerID in
                BlindBoxPositionPlan(
                    index: index,
                    stickerID: BlindBoxStickerID(rawValue: stickerID)
                )
            }
        )
    }
}
