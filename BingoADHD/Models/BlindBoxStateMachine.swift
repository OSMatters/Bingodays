import Foundation

/// A point-to-ticket exchange that CloudKit has accepted but has not yet
/// finished granting. Reserving the slot first prevents a daily ticket grant
/// or another device from consuming the final ticket capacity while the
/// primary iCloud point ledger is being written.
struct BlindBoxPendingPointExchange: Codable, Equatable, Sendable {
    let idempotencyKey: UUID
    let grantDayIdentifier: String
    let reservedAt: Date
}

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
    var pendingPointExchange: BlindBoxPendingPointExchange?

    init(
        schemaVersion: Int = BlindBoxAccountState.currentSchemaVersion,
        ticketBalance: Int = 0,
        ownedStickerCounts: [String: Int] = [:],
        candidateBatches: [BlindBoxCandidateBatch] = [],
        lastTicketGrantDayIdentifier: String? = nil,
        lastPointExchangeDayIdentifier: String? = nil,
        pointExchangesUsedOnLastGrantDay: Int = 0,
        pendingPointExchange: BlindBoxPendingPointExchange? = nil
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
        self.pendingPointExchange = pendingPointExchange
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

enum BlindBoxDrawMode: String, Codable, Equatable, Sendable {
    case single
    case wholeBox
}

/// A user-visible draw intent. The UUID is created before the network request
/// and must be reused after a timeout or app relaunch, so the authoritative
/// repository can return the original result instead of charging twice.
struct BlindBoxDrawRequest: Codable, Equatable, Sendable, Identifiable {
    let idempotencyKey: UUID
    let batchID: UUID
    let mode: BlindBoxDrawMode
    let positionIndex: Int?

    var id: UUID { idempotencyKey }

    static func single(
        idempotencyKey: UUID = UUID(),
        batchID: UUID,
        positionIndex: Int
    ) -> BlindBoxDrawRequest {
        BlindBoxDrawRequest(
            idempotencyKey: idempotencyKey,
            batchID: batchID,
            mode: .single,
            positionIndex: positionIndex
        )
    }

    static func wholeBox(
        idempotencyKey: UUID = UUID(),
        batchID: UUID
    ) -> BlindBoxDrawRequest {
        BlindBoxDrawRequest(
            idempotencyKey: idempotencyKey,
            batchID: batchID,
            mode: .wholeBox,
            positionIndex: nil
        )
    }

    func validationError() -> BlindBoxDrawRequestValidationError? {
        switch mode {
        case .single:
            guard let positionIndex else { return .missingPositionIndex }
            guard positionIndex >= 0 else { return .invalidPositionIndex }
        case .wholeBox:
            guard positionIndex == nil else { return .unexpectedPositionIndex }
        }
        return nil
    }
}

enum BlindBoxDrawRequestValidationError: Error, Equatable {
    case missingPositionIndex
    case invalidPositionIndex
    case unexpectedPositionIndex
}

enum BlindBoxDrawRepositoryError: Error, Equatable {
    case idempotencyKeyConflict
}

/// The CloudKit implementation will perform the command as one atomic record
/// zone operation. The preview implementation conforms too, allowing the UI to
/// use the exact same request and retry contract before real assets are wired.
@MainActor
protocol BlindBoxDrawRepository: AnyObject {
    func open(_ request: BlindBoxDrawRequest) async throws -> BlindBoxOpenResult
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

struct BlindBoxDailyTicketRefreshResult: Equatable, Sendable {
    /// The number of 04:00 grant days processed by this refresh. An account's
    /// first refresh processes one day; it never receives an unbounded backlog.
    let processedGrantDays: Int
    let grantedTicketCount: Int
    let resultingTicketBalance: Int
}

struct BlindBoxPointExchangeResult: Codable, Equatable, Sendable {
    let deductedPoints: Int
    let grantedTickets: Int
    let resultingTicketBalance: Int
}

struct BlindBoxPointExchangeReservationResult: Codable, Equatable, Sendable {
    let idempotencyKey: UUID
    let deductedPoints: Int
    let grantDayIdentifier: String
}

enum BlindBoxPointExchangeRepositoryError: Error, Equatable {
    case anotherExchangeIsPending
    case noPendingExchange
    case pendingExchangeMismatch
    case reservedTicketCapacityLost
}

enum BlindBoxWalletError: Error, Equatable {
    case pointExchange(BlindBoxPointExchangeEligibility)
}

/// Currency transitions are intentionally pure and do not own the app's point
/// wallet. Point redemption evidence remains in the existing primary iCloud
/// ledger, while the private Blind Box zone reserves and later grants a ticket
/// through an idempotent, recoverable exchange saga.
enum BlindBoxWalletStateMachine {
    @discardableResult
    static func refreshDailyTickets(
        state: inout BlindBoxAccountState,
        hasPremiumAccess: Bool,
        now: Date,
        calendar: Calendar
    ) -> BlindBoxDailyTicketRefreshResult {
        let currentGrantDay = BlindBoxGrantDay.identifier(for: now, calendar: calendar)
        let processedGrantDays: Int
        if let lastGrantDay = state.lastTicketGrantDayIdentifier,
           let elapsedDays = elapsedGrantDays(
               from: lastGrantDay,
               to: currentGrantDay,
               calendar: calendar
           ) {
            processedGrantDays = max(elapsedDays, 0)
        } else {
            // A newly created account starts with today's allowance only.
            processedGrantDays = 1
        }

        guard processedGrantDays > 0 else {
            return BlindBoxDailyTicketRefreshResult(
                processedGrantDays: 0,
                grantedTicketCount: 0,
                resultingTicketBalance: state.ticketBalance
            )
        }

        let allowance = BlindBoxTicketPolicy.dailyAllowance(hasPremiumAccess: hasPremiumAccess)
        // A point exchange is accepted before its primary iCloud ledger entry
        // and ticket grant can both be observed locally. Hold one capacity slot
        // so a subsequent daily grant cannot strand that accepted exchange at
        // the twenty-ticket cap.
        let pendingExchangeCapacity = state.pendingPointExchange == nil ? 0 : 1
        let availableCapacity = BlindBoxRuleConfiguration.maximumTicketBalance -
            state.ticketBalance - pendingExchangeCapacity
        let requestedTickets = allowance.multipliedReportingOverflow(by: processedGrantDays)
        let grantedTickets = min(
            max(availableCapacity, 0),
            requestedTickets.overflow ? BlindBoxRuleConfiguration.maximumTicketBalance : requestedTickets.partialValue
        )

        state.ticketBalance += grantedTickets
        // Update this even when capped: skipped tickets are intentionally not
        // banked to be granted retroactively after a later box opening.
        state.lastTicketGrantDayIdentifier = currentGrantDay

        return BlindBoxDailyTicketRefreshResult(
            processedGrantDays: processedGrantDays,
            grantedTicketCount: grantedTickets,
            resultingTicketBalance: state.ticketBalance
        )
    }

    @discardableResult
    static func exchangePointsForOneTicket(
        state: inout BlindBoxAccountState,
        availablePoints: Int,
        now: Date,
        calendar: Calendar
    ) throws -> BlindBoxPointExchangeResult {
        let currentGrantDay = BlindBoxGrantDay.identifier(for: now, calendar: calendar)
        let exchangesUsedToday = state.lastPointExchangeDayIdentifier == currentGrantDay
            ? state.pointExchangesUsedOnLastGrantDay
            : 0
        let eligibility = BlindBoxPointExchangePolicy.eligibility(
            availablePoints: availablePoints,
            ticketBalance: state.ticketBalance,
            exchangesUsedThisGrantDay: exchangesUsedToday
        )
        guard eligibility == .eligible else {
            throw BlindBoxWalletError.pointExchange(eligibility)
        }

        state.ticketBalance += 1
        state.lastPointExchangeDayIdentifier = currentGrantDay
        state.pointExchangesUsedOnLastGrantDay = exchangesUsedToday + 1
        return BlindBoxPointExchangeResult(
            deductedPoints: BlindBoxRuleConfiguration.pointExchangePrice,
            grantedTickets: 1,
            resultingTicketBalance: state.ticketBalance
        )
    }

    /// Starts the server-owned half of a point exchange. The caller writes the
    /// matching primary iCloud ledger record next, then calls
    /// `completeReservedPointExchange`. This split is deliberate: the current
    /// app keeps points and Blind Box state in separate CloudKit domains, so a
    /// durable, resumable saga is safer than pretending they are one atomic
    /// database transaction.
    @discardableResult
    static func reservePointsForOneTicketExchange(
        state: inout BlindBoxAccountState,
        idempotencyKey: UUID,
        availablePoints: Int,
        now: Date,
        calendar: Calendar
    ) throws -> BlindBoxPointExchangeReservationResult {
        if let pending = state.pendingPointExchange {
            guard pending.idempotencyKey == idempotencyKey else {
                throw BlindBoxPointExchangeRepositoryError.anotherExchangeIsPending
            }
            return BlindBoxPointExchangeReservationResult(
                idempotencyKey: pending.idempotencyKey,
                deductedPoints: BlindBoxRuleConfiguration.pointExchangePrice,
                grantDayIdentifier: pending.grantDayIdentifier
            )
        }

        let currentGrantDay = BlindBoxGrantDay.identifier(for: now, calendar: calendar)
        let exchangesUsedToday = state.lastPointExchangeDayIdentifier == currentGrantDay
            ? state.pointExchangesUsedOnLastGrantDay
            : 0
        let eligibility = BlindBoxPointExchangePolicy.eligibility(
            availablePoints: availablePoints,
            ticketBalance: state.ticketBalance,
            exchangesUsedThisGrantDay: exchangesUsedToday
        )
        guard eligibility == .eligible else {
            throw BlindBoxWalletError.pointExchange(eligibility)
        }

        state.lastPointExchangeDayIdentifier = currentGrantDay
        state.pointExchangesUsedOnLastGrantDay = exchangesUsedToday + 1
        state.pendingPointExchange = BlindBoxPendingPointExchange(
            idempotencyKey: idempotencyKey,
            grantDayIdentifier: currentGrantDay,
            reservedAt: now
        )
        return BlindBoxPointExchangeReservationResult(
            idempotencyKey: idempotencyKey,
            deductedPoints: BlindBoxRuleConfiguration.pointExchangePrice,
            grantDayIdentifier: currentGrantDay
        )
    }

    @discardableResult
    static func completeReservedPointExchange(
        state: inout BlindBoxAccountState,
        idempotencyKey: UUID
    ) throws -> BlindBoxPointExchangeResult {
        guard let pending = state.pendingPointExchange else {
            throw BlindBoxPointExchangeRepositoryError.noPendingExchange
        }
        guard pending.idempotencyKey == idempotencyKey else {
            throw BlindBoxPointExchangeRepositoryError.pendingExchangeMismatch
        }
        guard state.ticketBalance < BlindBoxRuleConfiguration.maximumTicketBalance else {
            throw BlindBoxPointExchangeRepositoryError.reservedTicketCapacityLost
        }

        state.ticketBalance += 1
        state.pendingPointExchange = nil
        return BlindBoxPointExchangeResult(
            deductedPoints: BlindBoxRuleConfiguration.pointExchangePrice,
            grantedTickets: 1,
            resultingTicketBalance: state.ticketBalance
        )
    }

    private static func elapsedGrantDays(
        from startIdentifier: String,
        to endIdentifier: String,
        calendar: Calendar
    ) -> Int? {
        guard let startDate = date(forGrantDayIdentifier: startIdentifier, calendar: calendar),
              let endDate = date(forGrantDayIdentifier: endIdentifier, calendar: calendar) else {
            return nil
        }
        return calendar.dateComponents([.day], from: startDate, to: endDate).day
    }

    private static func date(
        forGrantDayIdentifier identifier: String,
        calendar: Calendar
    ) -> Date? {
        let pieces = identifier.split(separator: "-")
        guard pieces.count == 3,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2]) else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
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

/// One safe, repeatable maintenance pass over a Blind Box account. It is run
/// when the feature becomes available online, not by a timer while the app is
/// terminated. A due automatic opening is therefore processed at the next
/// eligible maintenance pass, one position at a time.
struct BlindBoxAccountMaintenanceResult: Equatable, Sendable {
    let dailyTicketRefresh: BlindBoxDailyTicketRefreshResult
    let candidateReconciliation: BlindBoxCandidateReconciliationResult
    let automaticOpen: BlindBoxAutomaticOpenResult?
}

enum BlindBoxAccountMaintenance {
    /// Applies every time-based transition that does not require another
    /// user-owned currency. `candidateZoneWasPresented` must only be true once
    /// the candidate rows are actually visible; this prevents unseen batches
    /// from beginning their automatic-open schedules.
    static func apply<Generator: BlindBoxRandomNumberGenerating>(
        state: inout BlindBoxAccountState,
        themes: [BlindBoxThemeDefinition],
        hasPremiumAccess: Bool,
        candidateZoneWasPresented: Bool,
        now: Date,
        calendar: Calendar,
        reason: BlindBoxCandidateRefreshReason = .initialLoad,
        generator: inout Generator
    ) throws -> BlindBoxAccountMaintenanceResult {
        let dailyTicketRefresh = BlindBoxWalletStateMachine.refreshDailyTickets(
            state: &state,
            hasPremiumAccess: hasPremiumAccess,
            now: now,
            calendar: calendar
        )
        let candidateReconciliation = try BlindBoxCandidateCoordinator.reconcile(
            state: &state,
            themes: themes,
            hasPremiumAccess: hasPremiumAccess,
            reason: reason,
            now: now,
            generator: &generator
        )
        let automaticOpen = BlindBoxCandidateCoordinator.processOneAutomaticOpen(
            state: &state,
            now: now,
            generator: &generator
        )

        if candidateZoneWasPresented {
            BlindBoxCandidateCoordinator.recordFirstPresentation(
                state: &state,
                visibleBatchIDs: Set(state.candidateBatches.map(\.id)),
                presentedAt: now,
                generator: &generator
            )
        }

        return BlindBoxAccountMaintenanceResult(
            dailyTicketRefresh: dailyTicketRefresh,
            candidateReconciliation: candidateReconciliation,
            automaticOpen: automaticOpen
        )
    }
}

/// Chooses the next foreground moment at which a safe, server-authoritative
/// maintenance pass may be useful. The app still performs no state transition
/// while offline: this value merely avoids polling every few minutes while a
/// user keeps the Blind Box screen open.
enum BlindBoxForegroundMaintenanceSchedule {
    static func nextMaintenanceDate(
        for state: BlindBoxAccountState,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let automaticOpenDates = state.candidateBatches.compactMap(\.nextSystemOpenAt)
        let restockDates = state.candidateBatches.compactMap { $0.restockAt() }
        let nextTicketGrant = nextTicketGrantDate(after: now, calendar: calendar)

        return (automaticOpenDates + restockDates + [nextTicketGrant])
            .min() ?? nextTicketGrant
    }

    private static func nextTicketGrantDate(
        after date: Date,
        calendar: Calendar
    ) -> Date {
        let todayAtFour = calendar.date(
            bySettingHour: 4,
            minute: 0,
            second: 0,
            of: date
        ) ?? date
        guard todayAtFour > date else {
            return calendar.date(byAdding: .day, value: 1, to: todayAtFour) ?? todayAtFour
        }
        return todayAtFour
    }
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

enum BlindBoxLocalMigrationPersistenceResult: Equatable, Sendable {
    case applied(BlindBoxLegacyInventoryMigrationPreview)
    case alreadyApplied
    case requiresManualReview(unmappedLegacyStickerIDs: [String])
    case persistenceFailed
}

/// Local persistence is only the development/mock implementation. Production
/// opening and currency changes will move to an idempotent CloudKit repository.
/// The envelope still records one-time migration versions atomically with its
/// local state, so a pre-launch migration cannot be applied twice after an app
/// interruption between separate UserDefaults writes.
enum BlindBoxLocalStateStore {
    private struct PersistedEnvelope: Codable {
        var accountState: BlindBoxAccountState
        var completedLegacyMigrationVersions: Set<Int>

        init(
            accountState: BlindBoxAccountState,
            completedLegacyMigrationVersions: Set<Int> = []
        ) {
            self.accountState = accountState
            self.completedLegacyMigrationVersions = completedLegacyMigrationVersions
        }
    }

    static func load(defaults: UserDefaults = .standard) -> BlindBoxAccountState {
        normalizedState(loadEnvelope(defaults: defaults).accountState)
    }

    /// Copies legacy ownership into the separate Blind Box state. It never
    /// writes the old StickerStore keys or alters home-screen placements.
    @discardableResult
    static func migrateLegacyInventoryIfNeeded(
        defaults: UserDefaults = .standard
    ) -> BlindBoxLocalMigrationPersistenceResult {
        var envelope = loadEnvelope(defaults: defaults)
        let result = BlindBoxLegacyStickerMigration.apply(
            legacyInventoryCounts: BlindBoxLegacyInventoryReader.loadInventoryCounts(defaults: defaults),
            to: &envelope.accountState,
            completedMigrationVersions: &envelope.completedLegacyMigrationVersions
        )

        switch result {
        case let .applied(preview):
            guard saveEnvelope(envelope, defaults: defaults) else {
                return .persistenceFailed
            }
            return .applied(preview)
        case .alreadyApplied:
            return .alreadyApplied
        case let .requiresManualReview(unmappedLegacyStickerIDs):
            return .requiresManualReview(unmappedLegacyStickerIDs: unmappedLegacyStickerIDs)
        }
    }

    private static func loadEnvelope(defaults: UserDefaults) -> PersistedEnvelope {
        guard let data = defaults.data(forKey: AppSettings.blindBoxLocalStateKey) else {
            return PersistedEnvelope(accountState: BlindBoxAccountState())
        }

        if let envelope = try? JSONDecoder().decode(PersistedEnvelope.self, from: data) {
            return PersistedEnvelope(
                accountState: normalizedState(envelope.accountState),
                completedLegacyMigrationVersions: envelope.completedLegacyMigrationVersions
            )
        }

        // Preserve local development state written before migration tracking
        // was introduced; it will be wrapped on the next successful save.
        if let legacyState = try? JSONDecoder().decode(BlindBoxAccountState.self, from: data) {
            return PersistedEnvelope(accountState: normalizedState(legacyState))
        }

        return PersistedEnvelope(accountState: BlindBoxAccountState())
    }

    private static func normalizedState(_ state: BlindBoxAccountState) -> BlindBoxAccountState {
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
        var envelope = loadEnvelope(defaults: defaults)
        envelope.accountState = normalizedState(state)
        return saveEnvelope(envelope, defaults: defaults)
    }

    private static func saveEnvelope(
        _ envelope: PersistedEnvelope,
        defaults: UserDefaults
    ) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(envelope) else { return false }
        guard defaults.data(forKey: AppSettings.blindBoxLocalStateKey) != data else { return true }
        defaults.set(data, forKey: AppSettings.blindBoxLocalStateKey)
        return defaults.data(forKey: AppSettings.blindBoxLocalStateKey) == data
    }
}
