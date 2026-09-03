import SwiftUI

/// The Figma-backed, development-only blind-box flow. It intentionally uses a
/// separate preview store until the CloudKit transaction repository is ready.
struct BlindBoxFlowView: View {
    private enum Route {
        case lobby
        case detail(UUID)
        case reveal(BlindBoxOpenResult)
        case myBox
    }

    @StateObject private var store: BlindBoxPreviewStore
    @StateObject private var connectivity: BlindBoxConnectivityMonitor
    @State private var route: Route = .lobby
    @State private var toastMessage: String?
    @State private var toastDismissalTask: Task<Void, Never>?
    @State private var pendingOpenRequest: BlindBoxOpenRequest?
    @State private var isShowingTicketExchange = false
    @State private var isConfirmingTicketExchange = false
    @State private var isShowingRules = false
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// The existing reward flow is kept separate while the sticker flow is
    /// replaced. Wiring this closure into the old Custom Rewards tab happens in
    /// the integration pass so it cannot affect a release before this feature is
    /// enabled.
    var onSelectCustomRewards: (() -> Void)?

    init(
        previewAvailablePoints: Int = 320,
        onSelectCustomRewards: (() -> Void)? = nil
    ) {
        _store = StateObject(
            wrappedValue: BlindBoxPreviewStore(previewAvailablePoints: previewAvailablePoints)
        )
        _connectivity = StateObject(
            wrappedValue: BlindBoxConnectivityMonitor(
                forceOffline: AppDebugFlags.blindBoxPreviewForcesOffline
            )
        )
        self.onSelectCustomRewards = onSelectCustomRewards
    }

    var body: some View {
        ZStack {
            switch route {
            case .lobby:
                BlindBoxLobbyView(
                    ticketBalance: store.state.ticketBalance,
                    candidates: store.candidates(hasPremiumAccess: subscriptionManager.hasPremiumAccess),
                    themes: store.themes,
                    isPremium: subscriptionManager.hasPremiumAccess,
                    hasCollectedEveryActiveTheme: store.themes.allSatisfy {
                        BlindBoxCandidateCoordinator.isThemeComplete(
                            $0,
                            ownedStickerCounts: store.state.ownedStickerCounts
                        )
                    },
                    onSelectCustomRewards: onSelectCustomRewards,
                    onShowRules: {
                        isShowingRules = true
                    },
                    onSelectTicketBalance: {
                        isShowingTicketExchange = true
                    },
                    onSelectBatch: { batchID in
                        route = .detail(batchID)
                    },
                    onShowMyBox: {
                        route = .myBox
                    },
                    onDismiss: {
                        dismiss()
                    }
                )

            case .detail(let batchID):
                if let batch = store.state.candidateBatches.first(where: { $0.id == batchID }),
                   let theme = store.theme(for: batch.plan.themeID) {
                    BlindBoxDetailView(
                        batch: batch,
                        theme: theme,
                        ticketBalance: store.state.ticketBalance,
                        dailyTicketAllowance: BlindBoxTicketPolicy.dailyAllowance(
                            hasPremiumAccess: subscriptionManager.hasPremiumAccess
                        ),
                        onBack: {
                            route = .lobby
                        },
                        onOpenPosition: { position in
                            pendingOpenRequest = .position(batchID: batchID, positionIndex: position)
                        },
                        onOpenRandom: {
                            pendingOpenRequest = .random(batchID: batchID)
                        },
                        onOpenWholeBox: {
                            pendingOpenRequest = .wholeBox(
                                batchID: batchID,
                                ticketCost: batch.remainingPositionCount
                            )
                        }
                    )
                } else {
                    BlindBoxEmptyState(onBack: { route = .lobby })
                }

            case .reveal(let result):
                BlindBoxRevealView(
                    result: result,
                    themes: store.themes,
                    onContinue: {
                        store.acknowledgePendingReveal(result)
                        route = .detail(result.batchID)
                    }
                )

            case .myBox:
                BlindBoxCollectionView(
                    themes: store.themes,
                    ownedStickerCounts: store.state.ownedStickerCounts,
                    onBack: {
                        route = .lobby
                    }
                )
            }

            if let toastMessage {
                BlindBoxToast(message: toastMessage)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
            }

            if let pendingOpenRequest {
                let pendingBatch = store.state.candidateBatches.first {
                    $0.id == pendingOpenRequest.batchID
                }
                BlindBoxOpenConfirmation(
                    ticketCost: pendingOpenRequest.ticketCost,
                    isWholeBox: pendingOpenRequest.isWholeBox,
                    theme: pendingBatch.flatMap { store.theme(for: $0.plan.themeID) },
                    probabilityMode: pendingBatch?.plan.probabilityMode,
                    onCancel: {
                        self.pendingOpenRequest = nil
                    },
                    onConfirm: {
                        confirm(pendingOpenRequest)
                    }
                )
                .zIndex(10)
            }

            if isShowingRules {
                BlindBoxRulesSheet(onClose: {
                    isShowingRules = false
                })
                .zIndex(10)
            }

            if isShowingTicketExchange {
                BlindBoxTicketExchangeSheet(
                    availablePoints: store.previewAvailablePoints,
                    ticketBalance: store.state.ticketBalance,
                    dailyTicketAllowance: BlindBoxTicketPolicy.dailyAllowance(
                        hasPremiumAccess: subscriptionManager.hasPremiumAccess
                    ),
                    eligibility: store.pointExchangeEligibility(),
                    onClose: {
                        isShowingTicketExchange = false
                    },
                    onRequestExchange: { _ in
                        isConfirmingTicketExchange = true
                    }
                )
                .zIndex(10)
            }

            if isConfirmingTicketExchange {
                BlindBoxTicketExchangeConfirmation(
                    onCancel: {
                        isConfirmingTicketExchange = false
                    },
                    onConfirm: {
                        confirmTicketExchange()
                    }
                )
                .zIndex(11)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: routeDescription)
        .onDisappear {
            toastDismissalTask?.cancel()
        }
    }

    private var routeDescription: String {
        switch route {
        case .lobby: return "lobby"
        case .detail(let id): return "detail-\(id.uuidString)"
        case .reveal(let result): return "reveal-\(result.batchID.uuidString)"
        case .myBox: return "my-box"
        }
    }

    private func openSingle(batchID: UUID, positionIndex: Int) {
        open(
            .single(
                batchID: batchID,
                positionIndex: positionIndex
            )
        )
    }

    private func openWholeBox(batchID: UUID) {
        open(.wholeBox(batchID: batchID))
    }

    private func open(_ request: BlindBoxDrawRequest) {
        guard connectivity.status.canMakeNetworkRequests else {
            presentToast(connectivity.status.unavailableMessage)
            return
        }
        Task {
            do {
                let result = try await store.open(request)
                route = .reveal(result)
            } catch {
                presentFailure(error)
            }
        }
    }

    private func confirm(_ request: BlindBoxOpenRequest) {
        pendingOpenRequest = nil
        switch request {
        case .position(let batchID, let positionIndex):
            openSingle(batchID: batchID, positionIndex: positionIndex)
        case .random(let batchID):
            guard let batch = store.state.candidateBatches.first(where: { $0.id == batchID }),
                  let position = batch.unopenedPositionPlans.randomElement() else {
                presentFailure(BlindBoxOpenError.batchSoldOut)
                return
            }
            openSingle(batchID: batchID, positionIndex: position.index)
        case .wholeBox(let batchID, _):
            openWholeBox(batchID: batchID)
        }
    }

    private func confirmTicketExchange() {
        isConfirmingTicketExchange = false
        guard connectivity.status.canMakeNetworkRequests else {
            presentToast(connectivity.status.unavailableMessage)
            return
        }
        do {
            _ = try store.exchangePointsForOneTicket()
            isShowingTicketExchange = false
            presentToast("1 Blind Box ticket added.")
        } catch {
            presentFailure(error)
        }
    }

    private func presentFailure(_ error: Error) {
        if let walletError = error as? BlindBoxWalletError {
            switch walletError {
            case let .pointExchange(eligibility):
                presentToast(ticketExchangeFailureMessage(for: eligibility))
            }
            return
        }

        let message: String
        switch error as? BlindBoxOpenError {
        case .insufficientTickets:
            message = "Not enough Blind Box tickets."
        case .batchSoldOut:
            message = "This box is restocking."
        case .positionAlreadyOpened:
            message = "This box has already been opened."
        default:
            message = "Unable to open this box. Please try again."
        }
        presentToast(message)
    }

    private func ticketExchangeFailureMessage(
        for eligibility: BlindBoxPointExchangeEligibility
    ) -> String {
        switch eligibility {
        case .disabled:
            return "Ticket exchange is temporarily unavailable."
        case let .insufficientPoints(required, current):
            return "You need \(max(required - current, 0)) more points."
        case .ticketBalanceAtCapacity:
            return "Your Blind Box ticket balance is full."
        case .grantDayLimitReached:
            return "You already exchanged a ticket today."
        case .eligible:
            return "Unable to exchange points. Please try again."
        }
    }

    private func presentToast(_ message: String) {
        toastDismissalTask?.cancel()
        withAnimation { toastMessage = message }

        toastDismissalTask = Task {
            do {
                try await Task.sleep(for: .seconds(2.2))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation {
                toastMessage = nil
            }
        }
    }
}

/// The production-data counterpart to `BlindBoxFlowView`. It deliberately
/// shares the already-reviewed Figma presentation components below, but the
/// account, tickets, inventory, and draw results come from the private
/// CloudKit-backed feature store. This view is enabled only through the debug
/// launch flag until the final release gate is opened.
struct BlindBoxLiveFlowView: View {
    private enum Route {
        case lobby
        case detail(UUID)
        case reveal(BlindBoxOpenResult)
        case myBox
    }

    @ObservedObject var pointsFeatureStore: PointsFeatureStore
    let totalPoints: Int
    var onSelectCustomRewards: (() -> Void)?

    @StateObject private var store = BlindBoxFeatureStore()
    @StateObject private var connectivity = BlindBoxConnectivityMonitor()
    @State private var route: Route = .lobby
    @State private var toastMessage: String?
    @State private var toastDismissalTask: Task<Void, Never>?
    @State private var pendingOpenRequest: BlindBoxOpenRequest?
    @State private var isShowingTicketExchange = false
    @State private var isConfirmingTicketExchange = false
    @State private var ticketExchangeConfiguration: BlindBoxEconomyConfiguration?
    @State private var isShowingRules = false
    @State private var isAcknowledgingReveal = false
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var iCloudSyncCoordinator: NativeICloudSyncCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch store.availability {
            case .ready:
                liveFlow
            case .requiresMigrationReview:
                BlindBoxLiveStatusView(
                    title: "Blind Box needs an update",
                    message: "Your previous sticker collection needs review before Blind Box can start.",
                    onBack: { dismiss() }
                )
            case .failed(let message):
                BlindBoxLiveStatusView(
                    title: "Blind Box is unavailable",
                    message: message,
                    onBack: { dismiss() }
                )
            case .idle, .loading, .waitingForICloudInitialImport:
                BlindBoxLiveStatusView(
                    title: nativeICloudInitialImportComplete ? "Preparing Blind Box" : "Syncing your collection",
                    message: nativeICloudInitialImportComplete
                        ? "Your tickets and collection are being prepared."
                        : "Turn on iCloud Sync and wait for the first sync before opening Blind Box.",
                    showsProgress: true,
                    onBack: { dismiss() }
                )
            }
        }
        .task(id: refreshIdentifier) {
            await store.refresh(
                hasPremiumAccess: subscriptionManager.hasPremiumAccess,
                candidateZoneWasPresented: store.availability == .ready && isDisplayingLobby,
                nativeICloudInitialImportComplete: nativeICloudInitialImportComplete
            )
        }
        .task(id: foregroundMaintenanceScheduleIdentifier) {
            await runForegroundMaintenanceWhenDue()
        }
        .onChange(of: store.accountState.pendingReveal) { _, pendingReveal in
            guard let pendingReveal else { return }
            route = .reveal(pendingReveal.result)
        }
        .animation(.easeInOut(duration: 0.22), value: routeDescription)
        .onDisappear {
            toastDismissalTask?.cancel()
        }
    }

    private var nativeICloudInitialImportComplete: Bool {
        if case .ready = iCloudSyncCoordinator.state {
            return true
        }
        return false
    }

    private var refreshIdentifier: String {
        "\(subscriptionManager.hasPremiumAccess)-\(nativeICloudInitialImportComplete)"
    }

    private var foregroundMaintenanceScheduleIdentifier: String {
        guard case .ready = store.availability,
              nativeICloudInitialImportComplete,
              connectivity.status.canMakeNetworkRequests,
              scenePhase == .active else {
            return "inactive-\(store.availability)-\(connectivity.status)-\(scenePhase)"
        }
        let nextDate = BlindBoxForegroundMaintenanceSchedule.nextMaintenanceDate(
            for: store.accountState
        )
        return String(format: "active-%.3f", nextDate.timeIntervalSinceReferenceDate)
    }

    private var isDisplayingLobby: Bool {
        if case .lobby = route {
            return true
        }
        return false
    }

    /// Keeps the simulated public openings, the 24-hour restock and the 04:00
    /// ticket grant moving while this screen is foregrounded. A single sleep is
    /// cancelled automatically when the scene becomes inactive, connectivity
    /// changes or the authoritative account state changes; the next task then
    /// recalculates the earliest relevant date rather than polling CloudKit.
    private func runForegroundMaintenanceWhenDue() async {
        guard case .ready = store.availability,
              nativeICloudInitialImportComplete,
              connectivity.status.canMakeNetworkRequests,
              scenePhase == .active else {
            return
        }

        let nextDate = BlindBoxForegroundMaintenanceSchedule.nextMaintenanceDate(
            for: store.accountState
        )
        let secondsUntilMaintenance = max(nextDate.timeIntervalSinceNow, 1)
        do {
            try await Task.sleep(for: .seconds(secondsUntilMaintenance))
        } catch {
            return
        }

        guard !Task.isCancelled,
              nativeICloudInitialImportComplete,
              connectivity.status.canMakeNetworkRequests,
              scenePhase == .active else {
            return
        }
        await store.refresh(
            hasPremiumAccess: subscriptionManager.hasPremiumAccess,
            candidateZoneWasPresented: isDisplayingLobby,
            nativeICloudInitialImportComplete: nativeICloudInitialImportComplete
        )
    }

    private var liveFlow: some View {
        ZStack {
            switch route {
        case .lobby:
            BlindBoxLobbyView(
                ticketBalance: store.accountState.ticketBalance,
                candidates: store.candidates(hasPremiumAccess: subscriptionManager.hasPremiumAccess),
                themes: store.themes,
                isPremium: subscriptionManager.hasPremiumAccess,
                hasCollectedEveryActiveTheme: store.hasCollectedEveryActiveTheme,
                onSelectCustomRewards: onSelectCustomRewards,
                onShowRules: {
                    AnalyticsService.logBlindBoxRulesViewed()
                    isShowingRules = true
                },
                onSelectTicketBalance: {
                    isShowingTicketExchange = true
                },
                onSelectBatch: { batchID in
                    if let batch = store.accountState.candidateBatches.first(where: { $0.id == batchID }) {
                        AnalyticsService.logBlindBoxBatchViewed(batch)
                    }
                    route = .detail(batchID)
                },
                onShowMyBox: {
                    AnalyticsService.logBlindBoxCollectionViewed(
                        themeCount: store.themes.count,
                        ownedStickerTypeCount: store.accountState.ownedStickerCounts.count
                    )
                    route = .myBox
                },
                onDismiss: {
                    dismiss()
                }
            )
            .onAppear {
                AnalyticsService.logBlindBoxLobbyViewed(
                    ticketBalance: store.accountState.ticketBalance,
                    candidateCount: store.candidates(
                        hasPremiumAccess: subscriptionManager.hasPremiumAccess
                    ).count,
                    hasPremiumAccess: subscriptionManager.hasPremiumAccess
                )
                Task {
                    await store.refresh(
                        hasPremiumAccess: subscriptionManager.hasPremiumAccess,
                        candidateZoneWasPresented: true,
                        nativeICloudInitialImportComplete: nativeICloudInitialImportComplete
                    )
                }
            }

        case .detail(let batchID):
            if let batch = store.accountState.candidateBatches.first(where: { $0.id == batchID }),
               let theme = store.theme(for: batch.plan.themeID) {
                BlindBoxDetailView(
                    batch: batch,
                    theme: theme,
                    ticketBalance: store.accountState.ticketBalance,
                    dailyTicketAllowance: BlindBoxTicketPolicy.dailyAllowance(
                        hasPremiumAccess: subscriptionManager.hasPremiumAccess
                    ),
                    onBack: {
                        route = .lobby
                    },
                    onOpenPosition: { position in
                        pendingOpenRequest = .position(batchID: batchID, positionIndex: position)
                    },
                    onOpenRandom: {
                        pendingOpenRequest = .random(batchID: batchID)
                    },
                    onOpenWholeBox: {
                        pendingOpenRequest = .wholeBox(
                            batchID: batchID,
                            ticketCost: batch.remainingPositionCount
                        )
                    }
                )
            } else {
                BlindBoxEmptyState(onBack: { route = .lobby })
            }

        case .reveal(let result):
            BlindBoxRevealView(
                result: result,
                themes: store.themes,
                isContinuing: isAcknowledgingReveal,
                onContinue: {
                    acknowledgeReveal(result)
                }
            )

        case .myBox:
            BlindBoxCollectionView(
                themes: store.themes,
                ownedStickerCounts: store.accountState.ownedStickerCounts,
                onBack: {
                    route = .lobby
                }
            )
            }

            if let toastMessage {
                BlindBoxToast(message: toastMessage)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
            }

            if let pendingOpenRequest {
                let pendingBatch = store.accountState.candidateBatches.first {
                    $0.id == pendingOpenRequest.batchID
                }
                BlindBoxOpenConfirmation(
                    ticketCost: pendingOpenRequest.ticketCost,
                    isWholeBox: pendingOpenRequest.isWholeBox,
                    theme: pendingBatch.flatMap { store.theme(for: $0.plan.themeID) },
                    probabilityMode: pendingBatch?.plan.probabilityMode,
                    onCancel: {
                        self.pendingOpenRequest = nil
                    },
                    onConfirm: {
                        confirm(pendingOpenRequest)
                    }
                )
                .zIndex(10)
            }

            if isShowingRules {
                BlindBoxRulesSheet(onClose: {
                    isShowingRules = false
                })
                .zIndex(10)
            }

            if isShowingTicketExchange {
                BlindBoxTicketExchangeSheet(
                    availablePoints: pointsFeatureStore.availablePoints(totalPoints: totalPoints),
                    ticketBalance: store.accountState.ticketBalance,
                    dailyTicketAllowance: BlindBoxTicketPolicy.dailyAllowance(
                        hasPremiumAccess: subscriptionManager.hasPremiumAccess
                    ),
                    eligibility: pointExchangeEligibility,
                    economyConfiguration: store.economyConfiguration,
                    onClose: {
                        isShowingTicketExchange = false
                    },
                    onRequestExchange: { configuration in
                        ticketExchangeConfiguration = configuration
                        isConfirmingTicketExchange = true
                    }
                )
                .zIndex(10)
            }

            if isConfirmingTicketExchange, let ticketExchangeConfiguration {
                BlindBoxTicketExchangeConfirmation(
                    pointExchangePrice: ticketExchangeConfiguration.pointExchangePrice,
                    onCancel: {
                        isConfirmingTicketExchange = false
                    },
                    onConfirm: {
                        confirmTicketExchange(ticketExchangeConfiguration)
                    }
                )
                .zIndex(11)
            }
        }
    }

    private var routeDescription: String {
        switch route {
        case .lobby: return "lobby"
        case .detail(let id): return "detail-\(id.uuidString)"
        case .reveal(let result): return "reveal-\(result.batchID.uuidString)"
        case .myBox: return "my-box"
        }
    }

    private var pointExchangeEligibility: BlindBoxPointExchangeEligibility {
        let currentGrantDay = BlindBoxGrantDay.identifier(for: .now, calendar: .current)
        let exchangesToday = store.accountState.lastPointExchangeDayIdentifier == currentGrantDay
            ? store.accountState.pointExchangesUsedOnLastGrantDay
            : 0
        return BlindBoxPointExchangePolicy.eligibility(
            availablePoints: pointsFeatureStore.availablePoints(totalPoints: totalPoints),
            ticketBalance: store.accountState.ticketBalance,
            exchangesUsedThisGrantDay: exchangesToday,
            economyConfiguration: store.economyConfiguration
        )
    }

    private func open(_ request: BlindBoxDrawRequest) {
        guard connectivity.status.canMakeNetworkRequests else {
            AnalyticsService.logBlindBoxActionFailed(
                action: .open,
                reason: connectivityFailureReason
            )
            presentToast(connectivity.status.unavailableMessage)
            return
        }
        let openedBatch = store.accountState.candidateBatches.first { $0.id == request.batchID }
        let openedTheme = openedBatch.flatMap { store.theme(for: $0.plan.themeID) }
        Task {
            do {
                let result = try await store.open(
                    request,
                    hasPremiumAccess: subscriptionManager.hasPremiumAccess
                )
                if let openedBatch, let openedTheme {
                    AnalyticsService.logBlindBoxOpened(
                        request: request,
                        result: result,
                        theme: openedTheme,
                        probabilityMode: openedBatch.plan.probabilityMode,
                        didCompleteTheme: BlindBoxCandidateCoordinator.isThemeComplete(
                            openedTheme,
                            ownedStickerCounts: store.accountState.ownedStickerCounts
                        )
                    )
                }
                route = .reveal(result)
            } catch {
                presentFailure(error, action: .open)
            }
        }
    }

    private func confirm(_ request: BlindBoxOpenRequest) {
        pendingOpenRequest = nil
        switch request {
        case let .position(batchID, positionIndex):
            open(.single(batchID: batchID, positionIndex: positionIndex))
        case .random(let batchID):
            guard let batch = store.accountState.candidateBatches.first(where: { $0.id == batchID }),
                  let position = batch.unopenedPositionPlans.randomElement() else {
                presentFailure(BlindBoxOpenError.batchSoldOut)
                return
            }
            open(.single(batchID: batchID, positionIndex: position.index))
        case .wholeBox(let batchID, _):
            open(.wholeBox(batchID: batchID))
        }
    }

    private func acknowledgeReveal(_ result: BlindBoxOpenResult) {
        guard !isAcknowledgingReveal else { return }
        guard connectivity.status.canMakeNetworkRequests else {
            presentToast(connectivity.status.unavailableMessage)
            return
        }
        guard let pendingReveal = store.accountState.pendingReveal else {
            route = routeAfterReveal(result)
            return
        }
        guard pendingReveal.result == result else {
            route = .reveal(pendingReveal.result)
            return
        }

        isAcknowledgingReveal = true
        Task {
            do {
                try await store.acknowledgePendingReveal(pendingReveal)
                isAcknowledgingReveal = false
                route = routeAfterReveal(result)
            } catch {
                isAcknowledgingReveal = false
                AnalyticsService.logBlindBoxActionFailed(
                    action: .open,
                    reason: .requestFailed
                )
                presentToast("Unable to finish this reveal. Please try again.")
            }
        }
    }

    private func routeAfterReveal(_ result: BlindBoxOpenResult) -> Route {
        store.accountState.candidateBatches.contains(where: {
            $0.id == result.batchID
        }) ? .detail(result.batchID) : .lobby
    }

    private func confirmTicketExchange(_ configuration: BlindBoxEconomyConfiguration) {
        isConfirmingTicketExchange = false
        guard connectivity.status.canMakeNetworkRequests else {
            AnalyticsService.logBlindBoxActionFailed(
                action: .pointExchange,
                reason: connectivityFailureReason
            )
            presentToast(connectivity.status.unavailableMessage)
            return
        }
        Task {
            do {
                let result = try await store.exchangePointsForOneTicket(
                    availablePoints: pointsFeatureStore.availablePoints(totalPoints: totalPoints),
                    expectedEconomyConfigurationVersion: configuration.version
                )
                AnalyticsService.logBlindBoxPointTicketExchanged(result: result)
                pointsFeatureStore.reloadAfterExternalDataChange()
                isShowingTicketExchange = false
                presentToast("1 Blind Box ticket added.")
            } catch {
                presentFailure(error, action: .pointExchange)
            }
        }
    }

    private var connectivityFailureReason: BlindBoxAnalyticsFailureReason {
        switch connectivity.status {
        case .offline:
            return .offline
        case .checking:
            return .connectionChecking
        case .online:
            return .requestFailed
        }
    }

    private func presentFailure(_ error: Error, action: BlindBoxAnalyticsAction = .open) {
        AnalyticsService.logBlindBoxActionFailed(
            action: action,
            reason: analyticsFailureReason(for: error)
        )
        if let walletError = error as? BlindBoxWalletError {
            switch walletError {
            case let .pointExchange(eligibility):
                presentToast(ticketExchangeFailureMessage(for: eligibility))
            }
            return
        }

        if let featureStoreError = error as? BlindBoxFeatureStoreError {
            switch featureStoreError {
            case .remoteCatalogUnavailable:
                presentToast("Unable to verify the latest Blind Box rules. Please try again.")
            case .openingPaused:
                presentToast("Opening is temporarily paused.")
            case .pointExchangeDisabled:
                presentToast("Ticket exchange is temporarily unavailable.")
            case .pointExchangeConfigurationChanged:
                presentToast("Ticket exchange changed. Please review the updated price.")
            case .accountUnavailable, .pendingRevealChanged, .pointLedgerWriteFailed:
                presentToast("Unable to sync Blind Box right now. Please try again.")
            }
            return
        }

        let message: String
        switch error as? BlindBoxOpenError {
        case .insufficientTickets:
            message = "Not enough Blind Box tickets."
        case .batchSoldOut:
            message = "This box is restocking."
        case .positionAlreadyOpened:
            message = "This box has already been opened."
        case .pendingRevealMustBeAcknowledged:
            message = "Finish viewing your previous opening first."
        default:
            message = "Unable to open this box. Please try again."
        }
        presentToast(message)
    }

    private func analyticsFailureReason(for error: Error) -> BlindBoxAnalyticsFailureReason {
        if let walletError = error as? BlindBoxWalletError {
            switch walletError {
            case let .pointExchange(eligibility):
                switch eligibility {
                case .eligible:
                    return .requestFailed
                case .disabled:
                    return .pointExchangeDisabled
                case .insufficientPoints:
                    return .pointBalance
                case .ticketBalanceAtCapacity:
                    return .ticketCap
                case .grantDayLimitReached:
                    return .grantDayLimit
                }
            }
        }

        switch error as? BlindBoxOpenError {
        case .insufficientTickets:
            return .insufficientTickets
        case .batchSoldOut:
            return .soldOut
        case .positionAlreadyOpened:
            return .positionAlreadyOpened
        case .pendingRevealMustBeAcknowledged:
            return .pendingReveal
        default:
            break
        }

        switch error as? BlindBoxFeatureStoreError {
        case .accountUnavailable:
            return .accountUnavailable
        case .remoteCatalogUnavailable:
            return .remoteCatalogUnavailable
        case .openingPaused:
            return .openingPaused
        case .pointExchangeDisabled:
            return .pointExchangeDisabled
        case .pointExchangeConfigurationChanged:
            return .pointExchangeConfigurationChanged
        default:
            break
        }

        switch error as? BlindBoxCloudKitRepositoryError {
        case .contentionRetryLimitReached:
            return .accountContention
        default:
            return .requestFailed
        }
    }

    private func ticketExchangeFailureMessage(
        for eligibility: BlindBoxPointExchangeEligibility
    ) -> String {
        switch eligibility {
        case .disabled:
            return "Ticket exchange is temporarily unavailable."
        case let .insufficientPoints(required, current):
            return "You need \(max(required - current, 0)) more points."
        case .ticketBalanceAtCapacity:
            return "Your Blind Box ticket balance is full."
        case .grantDayLimitReached:
            return "You already exchanged a ticket today."
        case .eligible:
            return "Unable to exchange points. Please try again."
        }
    }

    private func presentToast(_ message: String) {
        toastDismissalTask?.cancel()
        withAnimation { toastMessage = message }

        toastDismissalTask = Task {
            do {
                try await Task.sleep(for: .seconds(2.2))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation {
                toastMessage = nil
            }
        }
    }
}

private enum BlindBoxOpenRequest: Identifiable {
    case position(batchID: UUID, positionIndex: Int)
    case random(batchID: UUID)
    case wholeBox(batchID: UUID, ticketCost: Int)

    var id: String {
        switch self {
        case .position(let batchID, let positionIndex):
            return "position-\(batchID.uuidString)-\(positionIndex)"
        case .random(let batchID):
            return "random-\(batchID.uuidString)"
        case .wholeBox(let batchID, _):
            return "whole-\(batchID.uuidString)"
        }
    }

    var ticketCost: Int {
        switch self {
        case .wholeBox(_, let ticketCost): return ticketCost
        case .position, .random: return 1
        }
    }

    var batchID: UUID {
        switch self {
        case let .position(batchID, _), let .random(batchID), let .wholeBox(batchID, _):
            batchID
        }
    }

    var isWholeBox: Bool {
        if case .wholeBox = self { return true }
        return false
    }
}

private struct BlindBoxLobbyView: View {
    let ticketBalance: Int
    let candidates: [BlindBoxCandidateBatch]
    let themes: [BlindBoxThemeDefinition]
    let isPremium: Bool
    let hasCollectedEveryActiveTheme: Bool
    let onSelectCustomRewards: (() -> Void)?
    let onShowRules: () -> Void
    let onSelectTicketBalance: () -> Void
    let onSelectBatch: (UUID) -> Void
    let onShowMyBox: () -> Void
    let onDismiss: () -> Void

    private let referenceWidth: CGFloat = 393

    var body: some View {
        BlindBoxCanvas {
            ZStack {
                BlindBoxImage("BlindBoxLobbyBackground")
                    .frame(width: 393, height: 852)

                lobbyTabs
                    .position(x: 196.5, y: 73)

                ticketBadge
                    .position(x: 62, y: 224)

                Button(action: onShowMyBox) {
                    BlindBoxMyBoxIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("My Box")
                .position(x: 360, y: 223)

                Button(action: onShowRules) {
                    BlindBoxRulesIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Blind Box rules")
                .position(x: 130, y: 223)

                BlindBoxShelf()
                    .frame(width: 360, height: 530)
                    .position(x: 196, y: 516)

                lobbyCandidates

                if hasCollectedEveryActiveTheme, candidates.isEmpty {
                    BlindBoxCollectionCompleteNotice(onShowMyBox: onShowMyBox)
                        .position(x: 196, y: 495)
                }

                if !isPremium {
                    premiumPlaceholders
                }

                BlindBoxTabBar()
                    .frame(width: 292, height: 56)
                    .position(x: 196, y: 792)
                    .allowsHitTesting(false)

                Button(action: onDismiss) {
                    Color.clear.frame(width: 62, height: 56)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Home")
                .position(x: 113, y: 792)
            }
        }
    }

    private var lobbyTabs: some View {
        HStack(spacing: 0) {
            Button {
                onSelectCustomRewards?()
            } label: {
                Text("Custom Rewards")
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 145, height: 36)
                    .background(Color(hex: "7A6757").opacity(0.83), in: Capsule())
            }
            .buttonStyle(.plain)

            Text("Blind box stickers")
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 160, height: 36)
                .background(Color(hex: "E2AD78"), in: Capsule())
                .offset(x: -14)
        }
        .frame(width: 291, height: 36)
    }

    private var ticketBadge: some View {
        Button(action: onSelectTicketBalance) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(hex: "E3A65E"))
                    .frame(width: 78, height: 28)
                    .offset(x: 14)
                Text("\(ticketBalance)")
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 44)
                    .offset(x: 42)
                BlindBoxTicketIcon()
                    .frame(width: 42, height: 42)
            }
            .frame(width: 92, height: 43)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Blind Box tickets: \(ticketBalance). Get more tickets")
    }

    @ViewBuilder
    private var lobbyCandidates: some View {
        let slots: [(CGFloat, CGFloat)] = [
            (116, 332), (262, 332), (116, 495), (262, 495), (116, 654), (262, 654)
        ]
        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, batch in
            if index < slots.count, let theme = themes.first(where: { $0.id == batch.plan.themeID }) {
                BlindBoxLobbyCard(
                    batch: batch,
                    theme: theme,
                    onTap: { onSelectBatch(batch.id) }
                )
                .position(x: slots[index].0, y: slots[index].1)
            }
        }
    }

    private var premiumPlaceholders: some View {
        Group {
            BlindBoxPremiumPlaceholder()
                .position(x: 116, y: 654)
            BlindBoxPremiumPlaceholder()
                .position(x: 262, y: 654)
        }
    }
}

/// This is the agreed post-completion destination until content operations add
/// another active theme. It intentionally keeps My Box available so duplicate
/// counts and every completed theme remain reviewable.
private struct BlindBoxCollectionCompleteNotice: View {
    let onShowMyBox: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            Text("All themes complete!")
                .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "6A4B33"))
            Text("New sticker themes will arrive here soon.")
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: "8A6E59"))
                .multilineTextAlignment(.center)
            Button(action: onShowMyBox) {
                Text("View My Box")
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 122, height: 32)
                    .background(Color(hex: "DCAF7A"), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 16)
        .frame(width: 248)
        .background(Color(hex: "FFF8EC").opacity(0.96), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color(hex: "E7B880"), lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("All current Blind Box themes are complete. New themes will arrive soon.")
    }
}

private struct BlindBoxLobbyCard: View {
    let batch: BlindBoxCandidateBatch
    let theme: BlindBoxThemeDefinition
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                BlindBoxThemeMiniBox(theme: theme)
                    .frame(width: 122, height: 136)

                if batch.isSoldOut {
                    BlindBoxImage("BlindBoxRestockingIcon")
                        .frame(width: 72, height: 72)
                        .offset(y: -17)
                }

                Capsule()
                    .fill(.white)
                    .frame(width: batch.isSoldOut ? 100 : 83, height: 22)
                    .overlay {
                        if batch.isSoldOut {
                            BlindBoxRestockCountdownLabel(
                                restockAt: batch.restockAt(),
                                prefix: "Refresh in",
                                font: .appSystem(size: 10, weight: .medium, design: .rounded),
                                foregroundColor: Color(hex: "594A3D")
                            )
                        } else {
                            Text(statusText)
                                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(hex: "594A3D"))
                        }
                    }
                    .offset(y: 11)
            }
            .frame(width: 128, height: 148)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.id.rawValue), \(statusText)")
    }

    private var statusText: String {
        return "Left: \(batch.remainingPositionCount)/9"
    }
}

private struct BlindBoxDetailView: View {
    let batch: BlindBoxCandidateBatch
    let theme: BlindBoxThemeDefinition
    let ticketBalance: Int
    let dailyTicketAllowance: Int
    let onBack: () -> Void
    let onOpenPosition: (Int) -> Void
    let onOpenRandom: () -> Void
    let onOpenWholeBox: () -> Void
    @State private var isShowingOdds = false

    var body: some View {
        BlindBoxCanvas {
            ZStack {
                BlindBoxImage("BlindBoxDrawBackground")
                    .frame(width: 393, height: 852)

                Button(action: onBack) {
                    LiquidGlassIconBadge(
                        systemName: "chevron.left",
                        size: 42,
                        iconSize: 17,
                        foregroundColor: Color(hex: "5A412C")
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .position(x: 41, y: 74)

                detailTicketBadge
                    .position(x: 197, y: 74)

                BlindBoxThemeHeader(theme: theme)
                    .frame(width: 272, height: 149)
                    .position(x: 196.5, y: 191.1)

                BlindBoxImage(boardAssetName)
                    .frame(width: 362, height: 391)
                    .position(x: 197, y: 473.5)

                positionGrid

                if batch.isSoldOut {
                    BlindBoxRestockCountdownLabel(
                        restockAt: batch.restockAt(),
                        prefix: "Restocks in",
                        font: .appSystem(size: 14, weight: .bold, design: .rounded),
                        foregroundColor: Color(hex: "88644C")
                    )
                    .position(x: 196, y: 714.5)
                } else {
                    actionButtons
                        .position(x: 196, y: 714.5)

                    Text(nextTicketText)
                        .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(hex: "88644C"))
                        .position(x: 196, y: 757)
                        .accessibilityLabel(nextTicketText)

                    Button {
                        isShowingOdds = true
                    } label: {
                        Text("Odds · Hidden \(hiddenStickerPercent)%")
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "A46A45"))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.9), in: Capsule())
                            .overlay {
                                Capsule().stroke(Color(hex: "F1C079"), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View this box's odds. Hidden sticker chance is \(hiddenStickerPercent) percent.")
                    .position(x: 196, y: 784)
                }

                if isShowingOdds {
                    BlindBoxBatchOddsSheet(
                        theme: theme,
                        probabilityMode: batch.plan.probabilityMode,
                        onClose: { isShowingOdds = false }
                    )
                    .zIndex(10)
                }
            }
        }
    }

    private var detailTicketBadge: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(hex: "E3A65E"))
                .frame(width: 77, height: 28)
                .offset(x: 14)
            Text("\(ticketBalance)")
                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 44)
                .offset(x: 42)
            BlindBoxTicketIcon()
                .frame(width: 42, height: 42)
        }
        .frame(width: 92, height: 43)
    }

    @ViewBuilder
    private var positionGrid: some View {
        let xPositions: [CGFloat] = [87, 197, 307]
        let yPositions: [CGFloat] = [370, 480, 590]
        ForEach(batch.plan.positions) { position in
            let row = position.index / 3
            let column = position.index % 3
            BlindBoxPositionCell(
                position: position,
                isOpened: batch.openedPositionIndices.contains(position.index),
                isSystemOpened: batch.isOpenedBySystem(at: position.index),
                theme: theme,
                onTap: { onOpenPosition(position.index) }
            )
            .position(x: xPositions[column], y: yPositions[row])
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 20) {
            BlindBoxActionButton(title: "Random box", ticketCost: 1, action: onOpenRandom)
                .disabled(batch.isSoldOut || batch.remainingPositionCount == 0)
            BlindBoxActionButton(
                title: "Whole box",
                ticketCost: batch.remainingPositionCount,
                action: onOpenWholeBox
            )
            .disabled(batch.isSoldOut || batch.remainingPositionCount == 0)
        }
    }

    private var boardAssetName: String {
        theme.artwork?.detailBoardAssetName ??
            (theme.id.rawValue == "pets" ? "BlindBoxPetsBoard" : "BlindBoxCozyBoard")
    }

    private var nextTicketText: String {
        let noun = dailyTicketAllowance == 1 ? "ticket" : "tickets"
        return "Next 4 AM: +\(dailyTicketAllowance) \(noun)"
    }

    private var hiddenStickerPercent: Int {
        Int((batch.plan.probabilityMode.hiddenStickerProbability * 100).rounded())
    }

}

private struct BlindBoxRestockCountdownLabel: View {
    let restockAt: Date?
    let prefix: String
    let font: Font
    let foregroundColor: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("\(prefix) \(BlindBoxRestockCountdown.text(restockAt: restockAt, now: context.date))")
                .font(font)
                .foregroundStyle(foregroundColor)
        }
        .accessibilityLabel("\(prefix) \(BlindBoxRestockCountdown.text(restockAt: restockAt))")
    }
}

private struct BlindBoxPositionCell: View {
    let position: BlindBoxPositionPlan
    let isOpened: Bool
    let isSystemOpened: Bool
    let theme: BlindBoxThemeDefinition
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                BlindBoxImage("BlindBoxDefaultSlot")
                    .frame(width: 98, height: 98)
                if isOpened, let sticker = theme.stickers.first(where: { $0.id == position.stickerID }) {
                    BlindBoxImage(sticker.assetName)
                        .frame(width: 76, height: 76)
                        .scaledToFit()
                    if isSystemOpened {
                        Text("Opened")
                            .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "A67754"))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.84), in: Capsule())
                            .offset(y: 41)
                    }
                }
            }
            .frame(width: 98, height: 98)
        }
        .buttonStyle(.plain)
        .disabled(isOpened)
        .accessibilityLabel(isOpened ? "Opened box" : "Unopened box")
    }
}

private struct BlindBoxActionButton: View {
    let title: String
    let ticketCost: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                ZStack(alignment: .topTrailing) {
                    BlindBoxTicketIcon()
                        .frame(width: 26, height: 26)
                    Text("\(ticketCost)")
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "A46A45"))
                        .offset(x: 5, y: -5)
                }
            }
            .foregroundStyle(Color(hex: "D5A06F"))
            .frame(width: 156, height: 50)
            .background(.white, in: Capsule())
            .overlay {
                Capsule().stroke(Color(hex: "FFC56B"), lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct BlindBoxRevealView: View {
    let result: BlindBoxOpenResult
    let themes: [BlindBoxThemeDefinition]
    var isContinuing = false
    let onContinue: () -> Void

    private var openedSticker: BlindBoxOpenedSticker? {
        result.openedStickers.first
    }

    private var stickerDefinition: BlindBoxStickerDefinition? {
        guard let openedSticker else { return nil }
        return themes
            .first(where: { $0.stickers.contains(where: { $0.id == openedSticker.stickerID }) })?
            .stickers
            .first(where: { $0.id == openedSticker.stickerID })
    }

    var body: some View {
        BlindBoxCanvas {
            ZStack {
                BlindBoxImage("BlindBoxDrawBackground")
                    .frame(width: 393, height: 852)
                Color.black.opacity(0.58)

                if result.openedStickers.count == 1, let openedSticker, let stickerDefinition {
                    singleReveal(openedSticker: openedSticker, stickerDefinition: stickerDefinition)
                } else {
                    wholeBoxReveal
                }
            }
        }
    }

    private func singleReveal(
        openedSticker: BlindBoxOpenedSticker,
        stickerDefinition: BlindBoxStickerDefinition
    ) -> some View {
        ZStack {
            Text(openedSticker.isDuplicate ? "You got a duplicate sticker!" : "Congratulations on\nreceiving the sticker!")
                .multilineTextAlignment(.center)
                .font(.appSystem(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .position(x: 196.5, y: 170)

            ZStack {
                BlindBoxImage("BlindBoxRevealLight")
                    .frame(width: 369, height: 369)
                BlindBoxImage(stickerDefinition.assetName)
                    .frame(width: 231, height: 231)
                    .scaledToFit()
            }
            .position(x: 196.5, y: 377.5)

            if openedSticker.isDuplicate {
                Text("Owned ×\(openedSticker.resultingOwnedCount)")
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .position(x: 196.5, y: 525)
            }

            Button(action: onContinue) {
                Text(isContinuing ? "Saving…" : "Great!")
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 157.5, height: 42)
                    .background(Color(hex: "DCAF7A"), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isContinuing)
            .position(x: 196.75, y: 623)
        }
        .frame(width: 393, height: 852)
    }

    private var wholeBoxReveal: some View {
        ZStack {
            Text("Congratulations on\nreceiving the stickers!")
                .multilineTextAlignment(.center)
                .font(.appSystem(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .position(x: 196.5, y: 170)

            BlindBoxImage("BlindBoxRevealLight")
                .frame(width: 195.6, height: 195.6)
                .position(x: 293.8, y: 289.8)

            let positions: [(CGFloat, CGFloat)] = [
                (99.2, 290.4), (195.2, 290.4), (294.2, 290.4),
                (101.4, 396.2), (195.2, 396.2), (294.2, 396.2),
                (99.2, 499.9), (195.2, 503.5), (294.2, 504)
            ]
            ForEach(Array(result.openedStickers.prefix(positions.count).enumerated()), id: \.element.positionIndex) { index, sticker in
                if let definition = themes
                    .flatMap(\.stickers)
                    .first(where: { $0.id == sticker.stickerID }) {
                    BlindBoxImage(definition.assetName)
                        .frame(width: 86.4, height: 86.4)
                        .scaledToFit()
                        .position(x: positions[index].0, y: positions[index].1)
                }
            }

            Button(action: onContinue) {
                Text(isContinuing ? "Saving…" : "Great!")
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 157.5, height: 42)
                    .background(Color(hex: "DCAF7A"), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isContinuing)
            .position(x: 196.75, y: 623)
        }
        .frame(width: 393, height: 852)
    }
}

private struct BlindBoxCollectionView: View {
    let themes: [BlindBoxThemeDefinition]
    let ownedStickerCounts: [String: Int]
    let onBack: () -> Void
    @State private var selectedThemeID = BlindBoxThemeID(rawValue: "pets")
    @State private var selectedPageIndex = 0

    private var selectedTheme: BlindBoxThemeDefinition? {
        themes.first(where: { $0.id == selectedThemeID }) ?? themes.first
    }

    private var themePages: [[BlindBoxThemeDefinition]] {
        guard !themes.isEmpty else { return [] }
        return stride(from: 0, to: themes.count, by: 3).map { startIndex in
            Array(themes[startIndex..<min(startIndex + 3, themes.count)])
        }
    }

    private var visibleThemes: [BlindBoxThemeDefinition] {
        guard themePages.indices.contains(selectedPageIndex) else { return [] }
        return themePages[selectedPageIndex]
    }

    var body: some View {
        BlindBoxCanvas {
            ZStack {
                BlindBoxImage("BlindBoxDrawBackground")
                    .frame(width: 393, height: 852)

                Button(action: onBack) {
                    LiquidGlassIconBadge(
                        systemName: "chevron.left",
                        size: 42,
                        iconSize: 18,
                        foregroundColor: Color(hex: "5A412C")
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .position(x: 41, y: 74)

                Text("My Box")
                    .font(.appSystem(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "57361F"))
                    .position(x: 196, y: 74.5)

                collectionThemePicker

                BlindBoxImage("BlindBoxCollectionBook")
                    .frame(width: 345, height: 508)
                    .position(x: 194.5, y: 522)

                if let selectedTheme {
                    collectionStickers(for: selectedTheme)
                }

                Button(action: showPreviousThemePage) {
                    Image(systemName: "chevron.left")
                        .font(.appSystem(size: 30, weight: .bold))
                        .foregroundStyle(Color(hex: "CD9863"))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous sticker themes")
                .disabled(selectedPageIndex == 0)
                .position(x: 98, y: 742)

                Button(action: showNextThemePage) {
                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 30, weight: .bold))
                        .foregroundStyle(Color(hex: "CD9863"))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next sticker themes")
                .disabled(selectedPageIndex >= max(themePages.count - 1, 0))
                .position(x: 344, y: 742)
            }
        }
        .onAppear(perform: synchronizeThemeSelection)
        .onChange(of: themes.map(\.id)) { _, _ in
            synchronizeThemeSelection()
        }
    }

    private var collectionThemePicker: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.86), lineWidth: 1)
                }
                .frame(width: 353, height: 109)
                .position(x: 196.5, y: 177.5)

            let pickerPositions: [CGFloat] = [69.5, 152.6, 236.6]
            ForEach(Array(visibleThemes.enumerated()), id: \.element.id) { index, theme in
                Button {
                    selectedThemeID = theme.id
                } label: {
                    BlindBoxMyBoxThemePackage(theme: theme)
                        .frame(width: 59.21, height: 75)
                        .background {
                            if selectedThemeID == theme.id {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white.opacity(0.86))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(hex: "A6E0FF"), lineWidth: 2)
                                    }
                                    .frame(width: 75, height: 91)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select \(theme.id.rawValue) theme")
                .position(x: pickerPositions[index], y: 179.5)
            }

            if visibleThemes.count < 3 {
                BlindBoxComingSoonTile()
                    .frame(width: 59.21, height: 75)
                    .position(x: pickerPositions[visibleThemes.count], y: 179.5)
            }
        }
        .frame(width: 393, height: 852)
    }

    @ViewBuilder
    private func collectionStickers(for theme: BlindBoxThemeDefinition) -> some View {
        ForEach(collectionLayout(for: theme), id: \.stickerID) { item in
            if let sticker = theme.stickers.first(where: { $0.id == item.stickerID }) {
                BlindBoxCollectionSticker(
                    sticker: sticker,
                    ownedCount: ownedStickerCounts[sticker.id.rawValue] ?? 0,
                    displaySize: CGFloat(item.displaySize),
                    isSpecialSlot: item.isSpecialSlot
                )
                .position(x: item.centerX, y: item.centerY)
            }
        }
    }

    private func collectionLayout(for theme: BlindBoxThemeDefinition) -> [BlindBoxCollectionPlacement] {
        if let configuredLayout = theme.presentation?.collectionPlacements {
            return configuredLayout
        }

        // Development fallback only. A remotely published theme must carry a
        // complete, validated presentation layout from the content pipeline.
        let positions: [(CGFloat, CGFloat)] = [
            (178, 380), (303, 378), (219, 494), (126, 488), (119, 597), (189, 570),
            (292, 669), (210, 680), (293, 472), (119, 689), (164, 440), (279, 566)
        ]
        return theme.stickers.enumerated().map { index, sticker in
            let position = positions[index % positions.count]
            return BlindBoxCollectionPlacement(
                stickerID: sticker.id,
                centerX: position.0,
                centerY: position.1,
                displaySize: sticker.isHidden ? 102 : 72,
                isSpecialSlot: sticker.isHidden
            )
        }
    }

    private func synchronizeThemeSelection() {
        guard let firstTheme = themes.first else {
            selectedPageIndex = 0
            return
        }
        guard let selectedThemeIndex = themes.firstIndex(where: { $0.id == selectedThemeID }) else {
            selectedThemeID = firstTheme.id
            selectedPageIndex = 0
            return
        }
        selectedPageIndex = selectedThemeIndex / 3
    }

    private func showPreviousThemePage() {
        guard selectedPageIndex > 0 else { return }
        selectedPageIndex -= 1
        if let firstTheme = visibleThemes.first {
            selectedThemeID = firstTheme.id
        }
    }

    private func showNextThemePage() {
        guard selectedPageIndex < themePages.count - 1 else { return }
        selectedPageIndex += 1
        if let firstTheme = visibleThemes.first {
            selectedThemeID = firstTheme.id
        }
    }
}

private struct BlindBoxCollectionSticker: View {
    let sticker: BlindBoxStickerDefinition
    let ownedCount: Int
    let displaySize: CGFloat
    let isSpecialSlot: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            BlindBoxImage(sticker.assetName)
                .frame(width: displaySize, height: displaySize)
                .scaledToFit()
                .saturation(ownedCount > 0 ? 1 : 0)
                .brightness(ownedCount > 0 ? 0 : -0.66)
                .opacity(ownedCount > 0 ? 1 : 0.96)
            if ownedCount == 0 {
                Text("?")
                    .font(.appSystem(size: isSpecialSlot ? 38 : 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            } else if ownedCount > 1 {
                Text("×\(ownedCount)")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color(hex: "D19A63"), in: Capsule())
            }
        }
        .frame(width: displaySize, height: displaySize)
    }
}

private struct BlindBoxEmptyState: View {
    let onBack: () -> Void

    var body: some View {
        BlindBoxCanvas {
            ZStack {
                BlindBoxImage("BlindBoxLobbyBackground")
                    .frame(width: 393, height: 852)
                VStack(spacing: 18) {
                    Text("This Blind Box is no longer available.")
                        .font(.appSystem(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "5A412C"))
                    Button("Back", action: onBack)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

/// iCloud account and first-import states have no equivalent in the supplied
/// Figma frames. Keep them compact and reversible so the reviewed lobby is
/// shown only once its data is safe to render.
private struct BlindBoxLiveStatusView: View {
    let title: String
    let message: String
    var showsProgress = false
    let onBack: () -> Void

    var body: some View {
        BlindBoxCanvas {
            ZStack {
                BlindBoxImage("BlindBoxLobbyBackground")
                    .frame(width: 393, height: 852)

                VStack(spacing: 16) {
                    if showsProgress {
                        ProgressView()
                            .tint(Color(hex: "D19A63"))
                    }
                    Text(title)
                        .font(.appSystem(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "5A412C"))
                    Text(message)
                        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "8A6E59"))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 270)
                    Button("Back", action: onBack)
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "D19A63"))
                }
                .padding(24)
                .background(Color(hex: "FFF8EC").opacity(0.94), in: RoundedRectangle(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color(hex: "E7B880"), lineWidth: 2)
                }
            }
        }
    }
}

/// Each batch records the mode that generated it. The sheet deliberately
/// discloses that mode and its published odds without inspecting or revealing
/// any unopened position in the already-locked batch.
private struct BlindBoxBatchOddsSheet: View {
    let theme: BlindBoxThemeDefinition
    let probabilityMode: BlindBoxProbabilityMode
    let onClose: () -> Void

    private var hiddenPerPositionPercent: String {
        percent(probabilityMode.hiddenStickerProbability)
    }

    private var hiddenPerBoxPercent: String {
        percent(probabilityMode.hiddenInclusionProbability)
    }

    private var normalPerPositionPercent: String {
        let probability = (1 - probabilityMode.hiddenStickerProbability) /
            Double(max(theme.normalStickers.count, 1))
        return percent(probability)
    }

    private var modeName: String {
        switch probabilityMode {
        case .standard:
            return "Standard mode"
        case .hiddenHunt:
            return "Hidden hunt mode"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("This box's odds")
                        .font(.appSystem(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "5A412C"))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.appSystem(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: "8A6E59"))
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(0.78), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close this box's odds")
                }

                Text(modeName)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "A46A45"))

                BlindBoxRuleRow(
                    title: "Hidden sticker",
                    detail: "\(hiddenPerPositionPercent) per position equivalent. This 9-position box has a \(hiddenPerBoxPercent) chance to include exactly one Hidden sticker."
                )
                BlindBoxRuleRow(
                    title: "Normal stickers",
                    detail: "Each of this theme's \(theme.normalStickers.count) normal stickers starts at \(normalPerPositionPercent) per position. Repeats can still happen."
                )
                BlindBoxRuleRow(
                    title: "Locked before opening",
                    detail: "The 9 results were generated when this box appeared. Choosing a position does not reroll its reward. Opened positions may help you decide which remaining position to choose."
                )

                Button(action: onClose) {
                    Text("Got it")
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color(hex: "DCAF7A"), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(20)
            .frame(width: 330)
            .background(Color(hex: "FFF8EC"), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(hex: "E7B880"), lineWidth: 2)
            }
        }
    }

    private func percent(_ value: Double) -> String {
        "\((value * 100).formatted(.number.precision(.fractionLength(2))))%"
    }
}

/// The main Figma screens include a rules affordance but no corresponding
/// panel. This compact sheet makes the agreed odds and wallet constraints
/// inspectable before a ticket is spent.
private struct BlindBoxRulesSheet: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Text("Blind Box Rules")
                            .font(.appSystem(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "5A412C"))
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.appSystem(size: 13, weight: .bold))
                                .foregroundStyle(Color(hex: "8A6E59"))
                                .frame(width: 30, height: 30)
                                .background(.white.opacity(0.78), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close Blind Box rules")
                    }

                    BlindBoxRuleRow(
                        title: "Daily tickets",
                        detail: "At 4:00 AM, Free receives 1 ticket and Premium receives 3. Missed days top up only until the 20-ticket limit."
                    )
                    BlindBoxRuleRow(
                        title: "Opening a box",
                        detail: "Each themed box has 9 positions. A chosen or random position costs 1 ticket; Whole box costs every remaining position."
                    )
                    BlindBoxRuleRow(
                        title: "Hidden sticker odds",
                        detail: "A 9-position box has a 9% chance to contain one Hidden sticker (1% per slot equivalent). After all normal stickers are owned but Hidden is missing, this becomes 45% (5% per slot equivalent). A box holds at most one Hidden sticker."
                    )
                    BlindBoxRuleRow(
                        title: "Duplicates",
                        detail: "Duplicates remain in My Box as ×N. They do not convert to fragments, points, or a replacement draw."
                    )
                    BlindBoxRuleRow(
                        title: "Availability",
                        detail: "After a box is first shown, positions can become opened over time. Sold-out boxes stay in their slot and restock after exactly 24 hours."
                    )
                    BlindBoxRuleRow(
                        title: "Tickets for points",
                        detail: "100 points exchanges for 1 ticket, once per grant day. The exchange cannot be undone."
                    )
                    BlindBoxRuleRow(
                        title: "Connection",
                        detail: "Opening requires internet. If you are offline, the opening fails and no ticket is used."
                    )

                    Button(action: onClose) {
                        Text("Got it")
                            .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color(hex: "DCAF7A"), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .frame(width: 330, height: 650)
            .background(Color(hex: "FFF8EC"), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(hex: "E7B880"), lineWidth: 2)
            }
            .padding(.vertical, 32)
        }
    }
}

private struct BlindBoxRuleRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "6A4B33"))
            Text(detail)
                .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: "8A6E59"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Small states were intentionally not prescribed by the main Figma frames.
/// This confirmation protects the eventual CloudKit transaction from accidental
/// taps while retaining the existing warm, rounded Blind Box visual language.
private struct BlindBoxOpenConfirmation: View {
    let ticketCost: Int
    let isWholeBox: Bool
    let theme: BlindBoxThemeDefinition?
    let probabilityMode: BlindBoxProbabilityMode?
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @State private var isShowingOdds = false

    private var oddsSummary: String? {
        guard let theme, let probabilityMode else { return nil }
        let hiddenPerPosition = percent(probabilityMode.hiddenStickerProbability)
        let hiddenPerBox = percent(probabilityMode.hiddenInclusionProbability)
        let normalPerPosition = percent(
            (1 - probabilityMode.hiddenStickerProbability) /
                Double(max(theme.normalStickers.count, 1))
        )
        return "Hidden: \(hiddenPerPosition) per position; \(hiddenPerBox) for one Hidden in this 9-position box. Each of the \(theme.normalStickers.count) normal stickers starts at \(normalPerPosition) per position."
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(isWholeBox ? "Open the whole box?" : "Open this blind box?")
                    .font(.appSystem(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "5A412C"))

                Text("Use \(ticketCost) Blind Box ticket\(ticketCost == 1 ? "" : "s")")
                    .font(.appSystem(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: "8A6E59"))

                if let oddsSummary {
                    Text(oddsSummary)
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "8A6E59"))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if theme != nil, probabilityMode != nil {
                        Button("View full odds") {
                            isShowingOdds = true
                        }
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "A46A45"))
                        .buttonStyle(.plain)
                        .accessibilityHint("Reviews the published odds before spending tickets")
                    }
                }

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "A46D4C"))
                        .frame(width: 118, height: 44)
                        .background(.white, in: Capsule())

                    Button("Open", action: onConfirm)
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 118, height: 44)
                        .background(Color(hex: "DCAF7A"), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .frame(width: 300)
            .background(Color(hex: "FFF8EC"), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(hex: "E7B880"), lineWidth: 2)
            }

            if isShowingOdds, let theme, let probabilityMode {
                BlindBoxBatchOddsSheet(
                    theme: theme,
                    probabilityMode: probabilityMode,
                    onClose: { isShowingOdds = false }
                )
                .zIndex(1)
            }
        }
    }

    private func percent(_ value: Double) -> String {
        "\((value * 100).formatted(.number.precision(.fractionLength(2))))%"
    }
}

/// The Figma board does not prescribe this small state. It is intentionally a
/// compact continuation of the ticket badge rather than a new primary screen.
private struct BlindBoxTicketExchangeSheet: View {
    let availablePoints: Int
    let ticketBalance: Int
    let dailyTicketAllowance: Int
    let eligibility: BlindBoxPointExchangeEligibility
    var economyConfiguration: BlindBoxEconomyConfiguration = .defaultValue
    let onClose: () -> Void
    let onRequestExchange: (BlindBoxEconomyConfiguration) -> Void

    private var canExchange: Bool {
        eligibility == .eligible
    }

    private var statusMessage: String {
        switch eligibility {
        case .eligible:
            let exchangeLimit = economyConfiguration.maximumPointExchangesPerGrantDay
            return exchangeLimit == 1
                ? "Available once each day. Resets at 4:00 AM."
                : "Available \(exchangeLimit) times each day. Resets at 4:00 AM."
        case .disabled:
            return "Ticket exchange is temporarily unavailable."
        case let .insufficientPoints(required, current):
            return "Need \(max(required - current, 0)) more points."
        case .ticketBalanceAtCapacity:
            return "Your ticket balance is full."
        case .grantDayLimitReached:
            return "You already exchanged a ticket today."
        }
    }

    var body: some View {
        ZStack {
            Button(action: onClose) {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close ticket exchange")

            VStack(spacing: 14) {
                HStack {
                    Text("Get tickets")
                        .font(.appSystem(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "5A412C"))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: "8A6E59"))
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.75), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                VStack(spacing: 8) {
                    Text("\(economyConfiguration.pointExchangePrice) points  →  1 ticket")
                        .font(.appSystem(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "A46D4C"))
                    Text("You have \(availablePoints) points · \(ticketBalance)/20 tickets")
                        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "8A6E59"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))

                Text("Daily grant: \(dailyTicketAllowance) ticket\(dailyTicketAllowance == 1 ? "" : "s") at 4:00 AM, up to 20 tickets.")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: "8A6E59"))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(statusMessage)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(canExchange ? Color(hex: "8A6E59") : Color(hex: "B56D56"))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Exchange \(economyConfiguration.pointExchangePrice) points") {
                    onRequestExchange(economyConfiguration)
                }
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        canExchange ? Color(hex: "DCAF7A") : Color(hex: "C9B9A8"),
                        in: Capsule()
                    )
                    .buttonStyle(.plain)
                    .disabled(!canExchange)
                    .accessibilityHint("Exchanges \(economyConfiguration.pointExchangePrice) points for one Blind Box ticket")
            }
            .padding(22)
            .frame(width: 330)
            .background(Color(hex: "FFF8EC"), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(hex: "E7B880"), lineWidth: 2)
            }
        }
    }
}

private struct BlindBoxTicketExchangeConfirmation: View {
    var pointExchangePrice = BlindBoxEconomyConfiguration.defaultValue.pointExchangePrice
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Exchange \(pointExchangePrice) points?")
                    .font(.appSystem(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "5A412C"))
                Text("You will receive 1 Blind Box ticket. This exchange can’t be undone.")
                    .font(.appSystem(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: "8A6E59"))
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "A46D4C"))
                        .frame(width: 118, height: 44)
                        .background(.white, in: Capsule())

                    Button("Exchange", action: onConfirm)
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 118, height: 44)
                        .background(Color(hex: "DCAF7A"), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .frame(width: 300)
            .background(Color(hex: "FFF8EC"), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(hex: "E7B880"), lineWidth: 2)
            }
        }
    }
}

private struct BlindBoxToast: View {
    let message: String

    var body: some View {
        VStack {
            Spacer()
            Text(message)
                .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.72), in: Capsule())
                .padding(.bottom, 52)
        }
        .ignoresSafeArea()
    }
}

private struct BlindBoxTicketIcon: View {
    var body: some View {
        BlindBoxImage("BlindBoxTicketIcon")
            .accessibilityHidden(true)
    }
}

private struct BlindBoxRulesIcon: View {
    var body: some View {
        BlindBoxImage("BlindBoxRulesIcon")
            .accessibilityHidden(true)
    }
}

private struct BlindBoxMyBoxIcon: View {
    var body: some View {
        BlindBoxImage("BlindBoxMyBoxIcon")
            .accessibilityHidden(true)
    }
}

private struct BlindBoxTabBar: View {
    var body: some View {
        HStack(spacing: 35) {
            Image(systemName: "house")
            Image(systemName: "star.fill")
                .foregroundStyle(Color(hex: "A87B58"))
                .padding(10)
                .background(Color(hex: "F0E9E1"), in: Circle())
            Image(systemName: "clock")
        }
        .font(.system(size: 21, weight: .semibold))
        .foregroundStyle(Color(hex: "594A3D"))
        .frame(width: 292, height: 56)
        .background(.white.opacity(0.93), in: Capsule())
        .overlay {
            Capsule().stroke(Color.white.opacity(0.9), lineWidth: 1)
        }
    }
}

private struct BlindBoxShelf: View {
    var body: some View {
        VStack(spacing: 0) {
            Image("BlindBoxShelfTop")
                .resizable()
                .scaledToFill()
                .frame(width: 360, height: 25)

            ForEach(0..<3, id: \.self) { _ in
                Image("BlindBoxShelfMiddle")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 360, height: 156)
                    .clipped()
            }

            Image("BlindBoxShelfBottom")
                .resizable()
                .scaledToFill()
                .frame(width: 360, height: 36)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct BlindBoxThemeMiniBox: View {
    let theme: BlindBoxThemeDefinition

    var body: some View {
        BlindBoxImage(theme.id.rawValue == "pets" ? "BlindBoxLobbyPets" : "BlindBoxLobbyCozy")
            .accessibilityLabel("\(theme.id.rawValue == "pets" ? "Pets" : "Cozy Daily") blind box")
    }
}

private struct BlindBoxThemeHeader: View {
    let theme: BlindBoxThemeDefinition

    var body: some View {
        BlindBoxImage(theme.id.rawValue == "pets" ? "BlindBoxPetsHeader" : "BlindBoxCozyHeader")
            .accessibilityLabel("\(theme.id.rawValue == "pets" ? "Pets" : "Cozy Daily") blind box")
    }
}

private struct BlindBoxComingSoonTile: View {
    var body: some View {
        BlindBoxImage("BlindBoxComingSoon")
    }
}

private struct BlindBoxMyBoxThemePackage: View {
    let theme: BlindBoxThemeDefinition

    var body: some View {
        BlindBoxImage(theme.id.rawValue == "pets" ? "BlindBoxPetsPackage" : "BlindBoxCozyPackage")
            .accessibilityLabel("\(theme.id.rawValue == "pets" ? "Pets" : "Cozy Daily") sticker pack")
    }
}

private struct BlindBoxPremiumPlaceholder: View {
    var body: some View {
        ZStack {
            BlindBoxImage("BlindBoxPremiumPlaceholder")
                .frame(width: 128, height: 133)
            BlindBoxImage("BlindBoxPremiumIcon")
                .frame(width: 72, height: 72)
        }
        .frame(width: 128, height: 133)
    }
}

private struct BlindBoxCanvas<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 393, proxy.size.height / 852)
            ZStack {
                content()
                    .frame(width: 393, height: 852)
                    .scaleEffect(scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }
}

private struct BlindBoxImage: View {
    let name: String

    init(_ name: String) {
        self.name = name
    }

    var body: some View {
        if let remoteImage = BlindBoxCatalogArtworkStore.shared.image(named: name) {
            Image(uiImage: remoteImage)
                .resizable()
                .scaledToFit()
        } else {
            Image(name)
                .resizable()
                .scaledToFit()
        }
    }
}
