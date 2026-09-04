import SwiftUI
import UIKit

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
                        onBack: {
                            route = .lobby
                        },
                        onOpenPosition: { position in
                            open(.position(batchID: batchID, positionIndex: position))
                        },
                        onOpenRandom: {
                            open(.random(batchID: batchID))
                        },
                        onOpenWholeBox: {
                            open(.wholeBox(
                                batchID: batchID,
                                ticketCost: batch.remainingPositionCount
                            ))
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
        .animation(.easeOut(duration: 0.24), value: isShowingRules)
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

    private func open(_ request: BlindBoxOpenRequest) {
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
            message = BlindBoxL10n.noTickets
        case .batchSoldOut:
            message = BlindBoxL10n.boxRestocking
        case .positionAlreadyOpened:
            message = BlindBoxL10n.boxAlreadyOpened
        default:
            message = BlindBoxL10n.openingFailed
        }
        presentToast(message)
    }

    private func ticketExchangeFailureMessage(
        for eligibility: BlindBoxPointExchangeEligibility
    ) -> String {
        switch eligibility {
        case .disabled:
            return BlindBoxL10n.ticketExchangeUnavailable
        case let .insufficientPoints(required, current):
            return BlindBoxL10n.needMorePoints(max(required - current, 0))
        case .ticketBalanceAtCapacity:
            return BlindBoxL10n.ticketBalanceFull
        case .grantDayLimitReached:
            return BlindBoxL10n.exchangedToday
        case .eligible:
            return BlindBoxL10n.ticketExchangeFailed
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
                    title: BlindBoxL10n.blindBoxNeedsUpdate,
                    message: BlindBoxL10n.collectionNeedsReview,
                    onBack: { dismiss() }
                )
            case .failed(let message):
                BlindBoxLiveStatusView(
                    title: BlindBoxL10n.blindBoxUnavailable,
                    message: message,
                    onBack: { dismiss() }
                )
            case .idle, .loading, .waitingForICloudInitialImport:
                BlindBoxLiveStatusView(
                    title: nativeICloudInitialImportComplete ? BlindBoxL10n.preparingBlindBox : BlindBoxL10n.syncingCollection,
                    message: nativeICloudInitialImportComplete
                        ? BlindBoxL10n.preparingBlindBoxDetail
                        : BlindBoxL10n.syncingCollectionDetail,
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
        .animation(.easeOut(duration: 0.24), value: isShowingRules)
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
                    onBack: {
                        route = .lobby
                    },
                    onOpenPosition: { position in
                        open(.position(batchID: batchID, positionIndex: position))
                    },
                    onOpenRandom: {
                        open(.random(batchID: batchID))
                    },
                    onOpenWholeBox: {
                        open(.wholeBox(
                            batchID: batchID,
                            ticketCost: batch.remainingPositionCount
                        ))
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

    private func open(_ request: BlindBoxOpenRequest) {
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
            message = BlindBoxL10n.noTickets
        case .batchSoldOut:
            message = BlindBoxL10n.boxRestocking
        case .positionAlreadyOpened:
            message = BlindBoxL10n.boxAlreadyOpened
        case .pendingRevealMustBeAcknowledged:
            message = BlindBoxL10n.finishPreviousOpening
        default:
            message = BlindBoxL10n.openingFailed
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
            return BlindBoxL10n.ticketExchangeUnavailable
        case let .insufficientPoints(required, current):
            return BlindBoxL10n.needMorePoints(max(required - current, 0))
        case .ticketBalanceAtCapacity:
            return BlindBoxL10n.ticketBalanceFull
        case .grantDayLimitReached:
            return BlindBoxL10n.exchangedToday
        case .eligible:
            return BlindBoxL10n.ticketExchangeFailed
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
        BlindBoxCanvas(backgroundAssetName: "BlindBoxLobbyBackground") {
            ZStack {
                lobbyTabs
                    .position(x: 196.5, y: 73)

                ticketBadge
                    .position(x: 62, y: 224)

                Button(action: onShowMyBox) {
                    BlindBoxMyBoxIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BlindBoxL10n.myBox)
                .position(x: 350, y: 223)

                Button(action: onShowRules) {
                    BlindBoxRulesIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BlindBoxL10n.rulesTitle)
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
                .accessibilityLabel(BlindBoxL10n.home)
                .position(x: 113, y: 792)
            }
        }
    }

    private var lobbyTabs: some View {
        HStack(spacing: 0) {
            Button {
                onSelectCustomRewards?()
            } label: {
            Text(BlindBoxL10n.customRewards)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 145, height: 36)
                    .background(Color(hex: "7A6757").opacity(0.83), in: Capsule())
            }
            .buttonStyle(.plain)

            Text(BlindBoxL10n.blindBoxStickers)
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
                    .frame(width: 70, height: 26)
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.9), lineWidth: 1.5)
                    }
                    .offset(x: 14)
                Text("\(ticketBalance)")
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 44)
                    .offset(x: 39)
                BlindBoxTicketIcon()
                    .frame(width: 46, height: 46)
            }
            .frame(width: 92, height: 43)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BlindBoxL10n.ticketsBalance(ticketBalance))
    }

    @ViewBuilder
    private var lobbyCandidates: some View {
        let slots: [(CGFloat, CGFloat)] = [
            (116, 362), (262, 362), (116, 518), (262, 518), (116, 674), (262, 674)
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

    @ViewBuilder
    private var premiumPlaceholders: some View {
        if let firstTheme = themes.first {
            let secondTheme = themes.dropFirst().first ?? firstTheme
            BlindBoxPremiumPlaceholder(theme: firstTheme)
                .position(x: 116, y: 670)
            BlindBoxPremiumPlaceholder(theme: secondTheme)
                .position(x: 262, y: 670)
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
            Text(BlindBoxL10n.allThemesComplete)
                .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "6A4B33"))
            Text(BlindBoxL10n.newThemesSoon)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: "8A6E59"))
                .multilineTextAlignment(.center)
            Button(action: onShowMyBox) {
                Text(BlindBoxL10n.viewMyBox)
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
        .accessibilityLabel(BlindBoxL10n.allThemesCompleteHint)
    }
}

private struct BlindBoxLobbyCard: View {
    let batch: BlindBoxCandidateBatch
    let theme: BlindBoxThemeDefinition
    let onTap: () -> Void

    var body: some View {
        Button {
            guard !batch.isSoldOut else { return }
            onTap()
        } label: {
            ZStack(alignment: .bottom) {
                BlindBoxThemeMiniBox(theme: theme)
                    .frame(width: 131, height: 149)
                    .opacity(batch.isSoldOut ? 0.5 : 1)
                    .offset(y: -8)

                if batch.isSoldOut {
                    BlindBoxShelfStatusOverlay(title: BlindBoxL10n.restocking, fontSize: 14)
                        .frame(width: 131, height: 149)
                        .offset(y: -8)

                    Capsule()
                        .fill(.white.opacity(0.88))
                        .frame(width: 100, height: 22)
                        .overlay {
                            BlindBoxRestockCountdownLabel(
                                restockAt: batch.restockAt(),
                                prefix: "Refresh in",
                                font: .appSystem(size: 10, weight: .medium, design: .rounded),
                                foregroundColor: Color(hex: "594A3D")
                            )
                        }
                        .offset(y: 3)
                } else {
                    Capsule()
                        .fill(.white)
                        .frame(width: 83, height: 22)
                        .overlay {
                            Text(statusText)
                                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(hex: "594A3D"))
                        }
                        .offset(y: 3)
                }
            }
            .frame(width: 146, height: 176)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.id.rawValue), \(statusText)")
        .accessibilityHint(batch.isSoldOut ? "This box is restocking and cannot be opened yet." : "Opens this Blind Box.")
    }

    private var statusText: String {
        BlindBoxL10n.left(batch.remainingPositionCount, total: 9)
    }
}

private struct BlindBoxDetailView: View {
    let batch: BlindBoxCandidateBatch
    let theme: BlindBoxThemeDefinition
    let ticketBalance: Int
    let onBack: () -> Void
    let onOpenPosition: (Int) -> Void
    let onOpenRandom: () -> Void
    let onOpenWholeBox: () -> Void
    @State private var isShowingOdds = false

    var body: some View {
        BlindBoxCanvas(contentHorizontalOffset: 0) {
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
                .accessibilityLabel(BlindBoxL10n.back)
                .position(x: 41, y: 74)

                detailTicketBadge
                    .position(x: 192, y: 74)

                Button {
                    isShowingOdds = true
                } label: {
                    BlindBoxRulesIcon()
                        .frame(width: 22, height: 22)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BlindBoxL10n.viewOdds)
                .position(x: 338, y: 74)

                BlindBoxThemeHeader(theme: theme)
                    .frame(width: 340, height: 190)
                    .position(x: 196.5, y: 195)

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
                }

                if isShowingOdds {
                    BlindBoxBatchOddsSheet(
                        normalStickerCount: theme.normalStickers.count,
                        probabilityMode: batch.plan.probabilityMode,
                        onClose: { isShowingOdds = false }
                    )
                    .zIndex(10)
                }
            }
        }
        .animation(.easeOut(duration: 0.24), value: isShowingOdds)
    }

    private var detailTicketBadge: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(hex: "E3A65E"))
                .frame(width: 70, height: 26)
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.9), lineWidth: 1.5)
                }
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
                theme: theme,
                onTap: { onOpenPosition(position.index) }
            )
            .position(x: xPositions[column], y: yPositions[row])
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 20) {
            BlindBoxActionButton(title: BlindBoxL10n.randomBox, ticketCost: 1, action: onOpenRandom)
                .disabled(batch.isSoldOut || batch.remainingPositionCount == 0)
            BlindBoxActionButton(
                title: BlindBoxL10n.wholeBox,
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

}

private struct BlindBoxRestockCountdownLabel: View {
    let restockAt: Date?
    let prefix: String
    let font: Font
    let foregroundColor: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(restockText(at: context.date))
                .font(font)
                .foregroundStyle(foregroundColor)
        }
        .accessibilityLabel(restockText(at: .now))
    }

    private func restockText(at date: Date) -> String {
        let countdown = BlindBoxRestockCountdown.text(restockAt: restockAt, now: date)
        return prefix == "Refresh in"
            ? BlindBoxL10n.refreshIn(countdown)
            : BlindBoxL10n.restocksIn(countdown)
    }
}

private struct BlindBoxPositionCell: View {
    let position: BlindBoxPositionPlan
    let isOpened: Bool
    let theme: BlindBoxThemeDefinition
    let onTap: () -> Void

    var body: some View {
        Button {
            guard !isOpened else { return }
            onTap()
        } label: {
            ZStack {
                BlindBoxImage(isOpened ? "BlindBoxOpenedSlot" : "BlindBoxDefaultSlot")
                    .frame(width: 98, height: 98)
                if isOpened, let sticker = theme.stickers.first(where: { $0.id == position.stickerID }) {
                    BlindBoxImage(sticker.assetName)
                        .frame(width: 80, height: 80)
                        .scaledToFit()
                        .zIndex(1)
                }
            }
            .frame(width: 98, height: 98)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOpened ? BlindBoxL10n.openedBox : BlindBoxL10n.unopenedBox)
    }
}

private struct BlindBoxActionButton: View {
    let title: String
    let ticketCost: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(.white)
                Capsule()
                    .stroke(Color(hex: "FFC56B"), lineWidth: 2)
                Text(title)
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                ZStack(alignment: .topTrailing) {
                    BlindBoxTicketIcon()
                        .frame(width: 20, height: 20)
                    ZStack {
                        ForEach(-1...1, id: \.self) { horizontalOffset in
                            ForEach(-1...1, id: \.self) { verticalOffset in
                                Text("\(ticketCost)")
                                    .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .offset(
                                        x: CGFloat(horizontalOffset),
                                        y: CGFloat(verticalOffset)
                                    )
                            }
                        }
                        Text("\(ticketCost)")
                            .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(hex: "A46A45"))
                    }
                    .offset(x: 4, y: -4)
                }
                .position(x: 145, y: 0)
                .zIndex(1)
            }
            .foregroundStyle(Color(hex: "D5A06F"))
            .frame(width: 156, height: 50)
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
        BlindBoxCanvas(contentHorizontalOffset: 0) {
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
            Text(singleRevealHeadline(isDuplicate: openedSticker.isDuplicate))
                .multilineTextAlignment(.center)
                .font(.appSystem(
                    size: openedSticker.isDuplicate ? 23 : 29,
                    weight: .bold,
                    design: .rounded
                ))
                .foregroundStyle(.white)
                .frame(width: 353)
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
                Text(BlindBoxL10n.owned(openedSticker.resultingOwnedCount))
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .position(x: 196.5, y: 525)
            }

            Button(action: onContinue) {
                Text(isContinuing ? BlindBoxL10n.saving : (openedSticker.isDuplicate ? BlindBoxL10n.keepGoing : BlindBoxL10n.great))
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

    private func singleRevealHeadline(isDuplicate: Bool) -> String {
        isDuplicate
            ? BlindBoxL10n.duplicateHeadline()
            : BlindBoxL10n.receivedStickerHeadline
    }

    private var wholeBoxReveal: some View {
        ZStack {
            Text(BlindBoxL10n.receivedStickersHeadline)
                .multilineTextAlignment(.center)
                .font(.appSystem(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 353)
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
                Text(isContinuing ? BlindBoxL10n.saving : BlindBoxL10n.great)
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
        BlindBoxCanvas(contentHorizontalOffset: 0) {
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
                .accessibilityLabel(BlindBoxL10n.back)
                .position(x: 41, y: 74)

                Text(BlindBoxL10n.myBox)
                    .font(.appSystem(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "57361F"))
                    .position(x: 196, y: 74.5)

                collectionThemePicker

                BlindBoxImage("BlindBoxCollectionBook")
                    .frame(width: 345, height: 520)
                    .position(x: 194.5, y: 522)

                if let selectedTheme {
                    collectionStickers(for: selectedTheme)
                }

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
                .accessibilityLabel("\(BlindBoxL10n.tr("Select", "选择", "選擇", "選択")) \(BlindBoxL10n.themeName(theme))")
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
                    displaySize: CGFloat(item.displaySize)
                )
                .position(x: item.centerX, y: item.centerY)
            }
        }
    }

    private func collectionLayout(for theme: BlindBoxThemeDefinition) -> [BlindBoxCollectionPlacement] {
        // The latest Book artwork contains a dedicated Secret frame from
        // x:99...214, y:302...417. Keep the hidden sticker exactly at its center;
        // normal stickers use a deliberately scattered, collision-free layout
        // underneath and beside it rather than reading as a rigid grid.
        let normalStickers = theme.stickers.filter { !$0.isHidden }
        let hiddenSticker = theme.stickers.first(where: \.isHidden)
        let specialDisplaySize = theme.id.rawValue == "cozy_daily" ? 85.0 : 70.0

        let specialPlacement = hiddenSticker.map {
            BlindBoxCollectionPlacement(
                stickerID: $0.id,
                centerX: 156.5,
                centerY: 367.5,
                displaySize: specialDisplaySize,
                isSpecialSlot: true
            )
        }

        if theme.id.rawValue == "pets" {
            return (specialPlacement.map { [$0] } ?? []) + petNormalPlacements(for: normalStickers)
        }

        if theme.id.rawValue == "cozy_daily" {
            return (specialPlacement.map { [$0] } ?? []) + cozyDailyNormalPlacements(for: normalStickers)
        }

        let normalPlacements: [BlindBoxCollectionPlacement]
        if normalStickers.count <= scatteredNormalCenters.count {
            normalPlacements = normalStickers.enumerated().map { index, sticker in
                let center = scatteredNormalCenters[index]
                return BlindBoxCollectionPlacement(
                    stickerID: sticker.id,
                    centerX: center.x,
                    centerY: center.y,
                    displaySize: 70,
                    isSpecialSlot: false
                )
            }
        } else {
            // Future themes can contain more stickers. Compact them only when
            // needed, while preserving a minimum 12 pt gap in the Book area.
            let columns: [Double] = [110, 196.5, 284]
            let rowCount = max(Int(ceil(Double(normalStickers.count) / Double(columns.count))), 1)
            let firstRowY = 468.0
            let lastRowY = 718.0
            let rowPitch = rowCount > 1
                ? (lastRowY - firstRowY) / Double(rowCount - 1)
                : 0
            let displaySize = min(70, max(36, rowPitch > 0 ? rowPitch - 12 : 70))
            normalPlacements = normalStickers.enumerated().map { index, sticker in
                BlindBoxCollectionPlacement(
                    stickerID: sticker.id,
                    centerX: columns[index % columns.count],
                    centerY: firstRowY + (Double(index / columns.count) * rowPitch),
                    displaySize: displaySize,
                    isSpecialSlot: false
                )
            }
        }

        return (specialPlacement.map { [$0] } ?? []) + normalPlacements
    }

    /// The Pets book follows the supplied illustration: the Secret space is
    /// reserved for the hidden sticker, while the regular collection is spread
    /// through the remaining safe area instead of being forced into a grid.
    /// Two regular stickers sit to the right of Secret; the remaining rows
    /// begin below the Secret frame so no artwork crosses its border.
    private func petNormalPlacements(
        for stickers: [BlindBoxStickerDefinition]
    ) -> [BlindBoxCollectionPlacement] {
        let referenceCenters: [String: (x: Double, y: Double)] = [
            "pets_01": (281, 354),
            "pets_07": (281, 446),
            "pets_03": (120, 518),
            "pets_02": (196, 533),
            "pets_08": (281, 523),
            "pets_05": (120, 625),
            "pets_11": (196, 610),
            "pets_04": (281, 620),
            "pets_10": (120, 700),
            "pets_06": (196, 715),
            "pets_09": (281, 705)
        ]

        return stickers.enumerated().map { index, sticker in
            let fallback = scatteredNormalCenters[index % scatteredNormalCenters.count]
            let center = referenceCenters[sticker.id.rawValue] ?? fallback
            return BlindBoxCollectionPlacement(
                stickerID: sticker.id,
                centerX: center.x,
                centerY: center.y,
                displaySize: 70,
                isSpecialSlot: false
            )
        }
    }

    /// Mirrors the Cozy Daily reference composition: a hidden sticker in the
    /// Secret frame, then the eight regular poses scattered across the right
    /// and lower parts of the book with clear breathing room between them.
    private func cozyDailyNormalPlacements(
        for stickers: [BlindBoxStickerDefinition]
    ) -> [BlindBoxCollectionPlacement] {
        let referenceCenters: [String: (x: Double, y: Double)] = [
            "cozy_01": (286, 371),
            "cozy_07": (281, 455),
            "cozy_06": (136, 501),
            "cozy_02": (204, 556),
            "cozy_04": (288, 556),
            "cozy_03": (136, 639),
            "cozy_05": (204, 693),
            "cozy_08": (288, 639)
        ]

        return stickers.enumerated().map { index, sticker in
            let fallback = scatteredNormalCenters[index % scatteredNormalCenters.count]
            let center = referenceCenters[sticker.id.rawValue] ?? fallback
            return BlindBoxCollectionPlacement(
                stickerID: sticker.id,
                centerX: center.x,
                centerY: center.y,
                displaySize: 85,
                isSpecialSlot: false
            )
        }
    }

    private var scatteredNormalCenters: [(x: Double, y: Double)] {
        [
            (286, 356),
            (140, 468), (224, 447), (300, 478),
            (136, 550), (222, 548), (300, 574),
            (142, 632), (224, 636), (298, 672),
            (220, 718)
        ]
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

}

private struct BlindBoxCollectionSticker: View {
    let sticker: BlindBoxStickerDefinition
    let ownedCount: Int
    let displaySize: CGFloat

    private var artworkName: String {
        ownedCount > 0 ? sticker.assetName : "\(sticker.assetName)_none"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            BlindBoxImage(artworkName)
                .frame(width: displaySize, height: displaySize)
                .scaledToFit()
            if ownedCount > 1 {
                Text("×\(ownedCount)")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(minWidth: 40, minHeight: 22)
                    .background(Color(hex: "F3E8D9"), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(.white, lineWidth: 2)
                    }
                    .offset(y: displaySize * 0.43 - 5)
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
                    Text(BlindBoxL10n.boxUnavailable)
                        .font(.appSystem(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "5A412C"))
                    Button(BlindBoxL10n.back, action: onBack)
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
                    Button(BlindBoxL10n.back, action: onBack)
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
    let normalStickerCount: Int
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
            Double(max(normalStickerCount, 1))
        return percent(probability)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Button(action: onClose) {
                Color.black.opacity(0.38)
                .ignoresSafeArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BlindBoxL10n.close)

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(hex: "D8B994"))
                    .frame(width: 38, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Text(BlindBoxL10n.oddsTitle)
                        .font(.appSystem(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "5A412C"))

                    VStack(spacing: 8) {
                        BlindBoxOddsSummaryRow(
                            title: BlindBoxL10n.regularSticker,
                            detail: BlindBoxL10n.normalOddsDetail(normalPerPositionPercent)
                        )
                        BlindBoxOddsSummaryRow(
                            title: BlindBoxL10n.hiddenSticker,
                            detail: BlindBoxL10n.hiddenOddsDetail(
                                perDraw: hiddenPerPositionPercent,
                                perBox: hiddenPerBoxPercent
                            )
                        )
                    }

                    Button(action: onClose) {
                        Text(BlindBoxL10n.gotIt)
                            .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color(hex: "DCAF7A"), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 330)
            .background(Color(hex: "FFF8EC"), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(hex: "E7B880"), lineWidth: 2)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func percent(_ value: Double) -> String {
        "\((value * 100).formatted(.number.precision(.fractionLength(2))))%"
    }
}

private struct BlindBoxOddsSummaryRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "6A4B33"))
            Text(detail)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: "8A6E59"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The main Figma screens include a rules affordance but no corresponding
/// panel. This compact sheet makes the agreed odds and wallet constraints
/// inspectable before a ticket is spent.
private struct BlindBoxRulesSheet: View {
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Button(action: onClose) {
                Color.black.opacity(0.38)
                .ignoresSafeArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BlindBoxL10n.closeRules)

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(hex: "D8B994"))
                    .frame(width: 38, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Text(BlindBoxL10n.rulesTitle)
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
                        .accessibilityLabel(BlindBoxL10n.closeRules)
                    }

                    BlindBoxRuleRow(
                        title: BlindBoxL10n.dailyTicketsTitle,
                        detail: BlindBoxL10n.dailyTicketsDetail
                    )
                    BlindBoxRuleRow(
                        title: BlindBoxL10n.openingBoxTitle,
                        detail: BlindBoxL10n.openingBoxDetail
                    )
                    BlindBoxRuleRow(
                        title: BlindBoxL10n.hiddenOddsTitle,
                        detail: BlindBoxL10n.hiddenOddsDetail
                    )
                    BlindBoxRuleRow(
                        title: BlindBoxL10n.revealedSurprisesTitle,
                        detail: BlindBoxL10n.revealedSurprisesDetail
                    )
                    BlindBoxRuleRow(
                        title: BlindBoxL10n.pointsTicketsTitle,
                        detail: BlindBoxL10n.pointsTicketsDetail
                    )

                    Button(action: onClose) {
                        Text(BlindBoxL10n.gotIt)
                            .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color(hex: "DCAF7A"), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 570)
            .background(Color(hex: "FFF8EC"), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(hex: "E7B880"), lineWidth: 2)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
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

private enum BlindBoxL10n {
    static func tr(_ english: String, _ zhHans: String, _ zhHant: String, _ japanese: String) -> String {
        L10n.tr(english, zhHans: zhHans, zhHant: zhHant, ja: japanese)
    }

    static var rulesTitle: String { tr("Blind Box Rules", "盲盒规则", "盲盒規則", "ブラインドボックスのルール") }
    static var closeRules: String { tr("Close Blind Box rules", "关闭盲盒规则", "關閉盲盒規則", "ブラインドボックスのルールを閉じる") }
    static var gotIt: String { tr("Got it", "知道了", "知道了", "わかった") }

    static var dailyTicketsTitle: String { tr("Fresh tickets every day", "每天都有新盲盒券", "每天都有新盲盒券", "毎日チケットが届く") }
    static var dailyTicketsDetail: String {
        tr(
            "Tickets refresh at 4:00 AM. Come back tomorrow for another chance to open a box!",
            "每天凌晨 4 点，盲盒券会刷新。明天再回来，继续试试手气吧！",
            "每天凌晨 4 點，盲盒券會刷新。明天再回來，繼續試試手氣吧！",
            "チケットは毎日午前4時に更新されます。明日も戻って、もう一度運試ししよう！"
        )
    }
    static var openingBoxTitle: String { tr("How to open", "怎么开盲盒", "怎麼開盲盒", "開け方") }
    static var openingBoxDetail: String {
        tr(
            "Pick a spot or try a random draw for 1 ticket. Want them all? Choose Whole box to open every remaining spot.",
            "选择一个位置，或来一次随机抽取，都会消耗 1 张券。想一次开完剩余位置，就选端盒。",
            "選擇一個位置，或來一次隨機抽取，都會消耗 1 張券。想一次開完剩餘位置，就選整盒開啟。",
            "好きな枠かランダム抽選はチケット1枚。残りを一度に開けたいときは「全枠開封」を選ぼう。"
        )
    }
    static var hiddenOddsTitle: String { tr("Hunt for the Hidden", "寻找隐藏款", "尋找隱藏款", "シークレットを探そう") }
    static var hiddenOddsDetail: String {
        tr(
            "Every box has a 9% chance to hold a rare Hidden sticker. Once you collect all regular stickers, your chance rises to 45%.",
            "隐藏款很稀有：每盒有 9% 概率出现。集齐普通贴纸后，获得隐藏款的机会会提升到 45%。",
            "隱藏款很稀有：每盒有 9% 機率出現。集齊普通貼紙後，獲得隱藏款的機會會提升到 45%。",
            "シークレットはレアで、各ボックスに入る確率は9%です。通常ステッカーをすべて集めると、確率は45%まで上がります。"
        )
    }
    static var pointsTicketsTitle: String { tr("Need another ticket?", "券不够？", "券不夠？", "チケットが足りない？") }
    static var pointsTicketsDetail: String {
        tr(
            "You can exchange 100 points for 1 ticket once a day.",
            "每天可用 100 积分兑换 1 张盲盒券。",
            "每天可用 100 積分兌換 1 張盲盒券。",
            "1日1回、100ポイントでチケット1枚に交換できます。"
        )
    }
    static var revealedSurprisesTitle: String { tr("See what has been revealed", "先看看已揭晓的惊喜", "先看看已揭曉的驚喜", "すでに明かされたサプライズを見よう") }
    static var revealedSurprisesDetail: String {
        tr(
            "To give every opening more clues, a themed box can gradually reveal some positions. Even when you have not opened one, new sticker results may appear—look first, then save your tickets for surprises still hidden.",
            "为了让每次开盒更有线索，主题盒会慢慢自动揭晓部分位置。即使你暂时没有开启，也可能看到新的贴纸结果；先观察已经出现的款式，再把盲盒券留给还没露面的惊喜吧。",
            "為了讓每次開盒更有線索，主題盒會慢慢自動揭曉部分位置。即使你暫時沒有開啟，也可能看到新的貼紙結果；先觀察已經出現的款式，再把盲盒券留給還沒露面的驚喜吧。",
            "開封のヒントが増えるよう、テーマボックスでは一部の枠が少しずつ自動で明かされます。まだ開けていなくても新しい結果が見えることがあります。すでに出たステッカーを見て、まだ隠れているサプライズにチケットを使おう。"
        )
    }

    static var myBox: String { tr("My Box", "我的盲盒", "我的盲盒", "マイボックス") }
    static var customRewards: String { tr("Custom Rewards", "自定义奖励", "自訂獎勵", "カスタム報酬") }
    static var blindBoxStickers: String { tr("Blind box stickers", "盲盒贴纸", "盲盒貼紙", "ブラインドボックスステッカー") }
    static var restocking: String { tr("Restocking", "补货中", "補貨中", "補充中") }
    static var unlockMoreBoxes: String {
        tr(
            "Upgrade to unlock more box slots",
            "升级解锁更多盲盒位",
            "升級解鎖更多盲盒位",
            "アップグレードしてボックス枠を増やす"
        )
    }
    static var randomBox: String { tr("Random box", "随机抽取", "隨機抽取", "ランダム抽選") }
    static var wholeBox: String { tr("Whole box", "端盒", "整盒開啟", "全枠開封") }
    static var back: String { tr("Back", "返回", "返回", "戻る") }
    static var premium: String { tr("Premium", "会员专属", "會員專屬", "プレミアム") }
    static var saving: String { tr("Saving…", "保存中…", "儲存中…", "保存中…") }
    static var great: String { tr("Great!", "太好了！", "太好了！", "いいね！") }
    static var keepGoing: String { tr("Keep going!", "继续试试！", "繼續試試！", "もう一度！") }
    static var allThemesComplete: String { tr("All themes complete!", "已集齐全部主题！", "已集齊全部主題！", "すべてのテーマをコンプリート！") }
    static var newThemesSoon: String { tr("New sticker themes will arrive here soon.", "新的贴纸主题很快会在这里出现。", "新的貼紙主題很快會在這裡出現。", "新しいステッカーテーマはもうすぐここに登場します。") }
    static var viewMyBox: String { tr("View My Box", "查看我的盲盒", "查看我的盲盒", "マイボックスを見る") }

    static func ticketsBalance(_ balance: Int) -> String {
        tr("Blind Box tickets: \(balance). Get more tickets", "盲盒券：\(balance) 张。获取更多盲盒券", "盲盒券：\(balance) 張。取得更多盲盒券", "ブラインドボックスチケット：\(balance)枚。チケットを増やす")
    }
    static func left(_ count: Int, total: Int) -> String {
        tr("Left: \(count)/\(total)", "剩余：\(count)/\(total)", "剩餘：\(count)/\(total)", "残り：\(count)/\(total)")
    }
    static func refreshIn(_ countdown: String) -> String {
        tr("Countdown \(countdown)", "倒计时 \(countdown)", "倒計時 \(countdown)", "カウントダウン \(countdown)")
    }
    static func restocksIn(_ countdown: String) -> String {
        tr("Restocks in \(countdown)", "将在 \(countdown) 后补货", "將在 \(countdown) 後補貨", "補充まで \(countdown)")
    }
    static func owned(_ count: Int) -> String {
        tr("Owned ×\(count)", "拥有 ×\(count)", "擁有 ×\(count)", "所持 ×\(count)")
    }
    static func duplicateHeadline() -> String {
        tr("Another one for your collection!\nKeep opening for a new surprise!", "收藏又多一张！\n继续开启，下一个惊喜可能就是新贴纸！", "收藏又多一張！\n繼續開啟，下一個驚喜可能就是新貼紙！", "コレクションがまた1枚増えた！\nもう一度開けて、新しいサプライズを見つけよう！")
    }
    static var receivedStickerHeadline: String { tr("Congratulations on\nreceiving the sticker!", "恭喜你获得了\n这张贴纸！", "恭喜你獲得了\n這張貼紙！", "ステッカー獲得\nおめでとう！") }
    static var receivedStickersHeadline: String { tr("Congratulations on\nreceiving the stickers!", "恭喜你获得了\n这些贴纸！", "恭喜你獲得了\n這些貼紙！", "ステッカー獲得\nおめでとう！") }
    static var noTickets: String { tr("Not enough Blind Box tickets.", "盲盒券不足。", "盲盒券不足。", "ブラインドボックスチケットが足りません。") }
    static var boxRestocking: String { tr("This box is restocking.", "该盲盒正在补货中。", "該盲盒正在補貨中。", "このボックスは補充中です。") }
    static var boxAlreadyOpened: String { tr("This box has already been opened.", "这个位置已经开启过了。", "這個位置已經開啟過了。", "この枠はすでに開封済みです。") }
    static var finishPreviousOpening: String { tr("Finish viewing your previous opening first.", "请先查看上一次的开启结果。", "請先查看上一次的開啟結果。", "先に前回の開封結果を確認してください。") }
    static var openingFailed: String { tr("Unable to open this box. Please try again.", "盲盒开启失败，请再试一次。", "盲盒開啟失敗，請再試一次。", "ボックスを開けませんでした。もう一度お試しください。") }
    static var ticketExchangeUnavailable: String { tr("Ticket exchange is temporarily unavailable.", "盲盒券兑换暂不可用。", "盲盒券兌換暫不可用。", "チケット交換は現在利用できません。") }
    static func needMorePoints(_ count: Int) -> String { tr("You need \(count) more points.", "还需要 \(count) 积分。", "還需要 \(count) 積分。", "あと\(count)ポイント必要です。") }
    static var ticketBalanceFull: String { tr("Your Blind Box ticket balance is full.", "盲盒券已达到上限。", "盲盒券已達到上限。", "ブラインドボックスチケットは上限です。") }
    static var exchangedToday: String { tr("You already exchanged a ticket today.", "今天已兑换过盲盒券。", "今天已兌換過盲盒券。", "今日はすでにチケットを交換しています。") }
    static var ticketExchangeFailed: String { tr("Unable to exchange points. Please try again.", "积分兑换失败，请再试一次。", "積分兌換失敗，請再試一次。", "ポイント交換に失敗しました。もう一度お試しください。") }
    static var boxUnavailable: String { tr("This Blind Box is no longer available.", "该盲盒已不可用。", "該盲盒已不可用。", "このブラインドボックスは利用できません。") }
    static var previousThemes: String { tr("Previous sticker themes", "上一页贴纸主题", "上一頁貼紙主題", "前のステッカーテーマ") }
    static var nextThemes: String { tr("Next sticker themes", "下一页贴纸主题", "下一頁貼紙主題", "次のステッカーテーマ") }
    static var openedBox: String { tr("Opened box", "已开启盲盒", "已開啟盲盒", "開封済みボックス") }
    static var unopenedBox: String { tr("Unopened box", "未开启盲盒", "未開啟盲盒", "未開封ボックス") }
    static var getTickets: String { tr("Get tickets", "获取盲盒券", "取得盲盒券", "チケットを入手") }
    static var close: String { tr("Close", "关闭", "關閉", "閉じる") }
    static func pointsForTicket(_ points: Int) -> String { tr("\(points) points  →  1 ticket", "\(points) 积分  →  1 张盲盒券", "\(points) 積分  →  1 張盲盒券", "\(points)ポイント  →  チケット1枚") }
    static func ticketWallet(points: Int, tickets: Int) -> String { tr("You have \(points) points · \(tickets)/20 tickets", "你有 \(points) 积分 · \(tickets)/20 张盲盒券", "你有 \(points) 積分 · \(tickets)/20 張盲盒券", "\(points)ポイント・チケット \(tickets)/20枚") }
    static func dailyGrant(_ count: Int) -> String { tr("Daily grant: \(count) ticket\(count == 1 ? "" : "s") at 4:00 AM, up to 20 tickets.", "每日凌晨 4 点发放 \(count) 张盲盒券，最多可持有 20 张。", "每日凌晨 4 點發放 \(count) 張盲盒券，最多可持有 20 張。", "毎日午前4時にチケットを\(count)枚受け取れます。最大20枚まで所持できます。") }
    static func exchangePoints(_ points: Int) -> String { tr("Exchange \(points) points", "用 \(points) 积分兑换", "用 \(points) 積分兌換", "\(points)ポイントで交換") }
    static func exchangeHint(_ points: Int) -> String { tr("Exchanges \(points) points for one Blind Box ticket", "\(points) 积分兑换 1 张盲盒券", "\(points) 積分兌換 1 張盲盒券", "\(points)ポイントをチケット1枚に交換") }
    static func exchangeOnceAvailable(_ limit: Int) -> String { tr("Available \(limit == 1 ? "once" : "\(limit) times") each day. Resets at 4:00 AM.", "每天可兑换 \(limit) 次，凌晨 4 点重置。", "每天可兌換 \(limit) 次，凌晨 4 點重置。", "1日\(limit)回まで交換できます。午前4時にリセットされます。") }
    static func exchangeConfirmTitle(_ points: Int) -> String { tr("Exchange \(points) points?", "确认用 \(points) 积分兑换？", "確認用 \(points) 積分兌換？", "\(points)ポイントを交換しますか？") }
    static var exchangeConfirmDetail: String { tr("You will receive 1 Blind Box ticket. This exchange can’t be undone.", "你将获得 1 张盲盒券。兑换后不可撤销。", "你將獲得 1 張盲盒券。兌換後不可撤銷。", "チケットを1枚受け取ります。この交換は取り消せません。") }
    static var cancel: String { tr("Cancel", "取消", "取消", "キャンセル") }
    static var exchange: String { tr("Exchange", "兑换", "兌換", "交換") }
    static var home: String { tr("Home", "首页", "首頁", "ホーム") }
    static var blindBoxNeedsUpdate: String { tr("Blind Box needs an update", "盲盒需要更新", "盲盒需要更新", "ブラインドボックスの更新が必要です") }
    static var blindBoxUnavailable: String { tr("Blind Box is unavailable", "盲盒暂不可用", "盲盒暫不可用", "ブラインドボックスは利用できません") }
    static var collectionNeedsReview: String { tr("Your previous sticker collection needs review before Blind Box can start.", "旧贴纸收藏需要先完成检查，才能开启盲盒。", "舊貼紙收藏需要先完成檢查，才能開啟盲盒。", "ブラインドボックスを始める前に、以前のステッカーコレクションを確認する必要があります。") }
    static var preparingBlindBox: String { tr("Preparing Blind Box", "正在准备盲盒", "正在準備盲盒", "ブラインドボックスを準備中") }
    static var syncingCollection: String { tr("Syncing your collection", "正在同步你的收藏", "正在同步你的收藏", "コレクションを同期中") }
    static var preparingBlindBoxDetail: String { tr("Your tickets and collection are being prepared.", "正在准备你的盲盒券和收藏。", "正在準備你的盲盒券和收藏。", "チケットとコレクションを準備しています。") }
    static var syncingCollectionDetail: String { tr("Turn on iCloud Sync and wait for the first sync before opening Blind Box.", "请打开 iCloud 同步，并等待首次同步完成后再开启盲盒。", "請開啟 iCloud 同步，並等待首次同步完成後再開啟盲盒。", "iCloud同期をオンにして、初回同期が完了してからブラインドボックスを開けてください。") }
    static var allThemesCompleteHint: String { tr("All current Blind Box themes are complete. New themes will arrive soon.", "当前盲盒主题已全部集齐，新主题即将到来。", "目前盲盒主題已全部集齊，新主題即將到來。", "現在のテーマはすべてコンプリートしました。新テーマはもうすぐ登場します。") }
    static var pets: String { tr("Pets", "宠物", "寵物", "ペット") }
    static var cozyDaily: String { tr("Cozy Daily", "治愈日常", "療癒日常", "ほっこり日常") }
    static func themeName(_ theme: BlindBoxThemeDefinition) -> String {
        theme.id.rawValue == "pets" ? pets : cozyDaily
    }
    static var viewOdds: String { tr("View odds", "查看概率", "查看機率", "確率を見る") }
    static var oddsTitle: String { tr("Current box odds", "当前盲盒概率", "目前盲盒機率", "このボックスの確率") }
    static var regularSticker: String { tr("Regular stickers", "常规款", "常規款", "通常ステッカー") }
    static var hiddenSticker: String { tr("Hidden sticker", "隐藏贴纸", "隱藏貼紙", "シークレットステッカー") }
    static func hiddenOddsDetail(perDraw: String, perBox: String) -> String {
        tr(
            "\(perDraw) per draw · \(perBox) chance this box contains one.\nCollect all regular stickers to increase this chance.",
            "单抽 \(perDraw) · 本盒含 1 张的概率 \(perBox)。\n集齐所有常规款后，隐藏款的概率会增加。",
            "單抽 \(perDraw) · 本盒含 1 張的機率 \(perBox)。\n集齊所有常規款後，隱藏款的機率會增加。",
            "1回あたり \(perDraw) ・このボックスに1枚入る確率 \(perBox)。\n通常ステッカーをすべて集めると、シークレットの確率が上がります。"
        )
    }
    static func normalOddsDetail(_ odds: String) -> String {
        tr(
            "Each regular sticker: \(odds) per draw",
            "每一张常规贴纸的单抽概率：\(odds)",
            "每一張常規貼紙的單抽機率：\(odds)",
            "通常ステッカー1枚あたり：1回 \(odds)"
        )
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
                    normalStickerCount: theme.normalStickers.count,
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
            return BlindBoxL10n.exchangeOnceAvailable(exchangeLimit)
        case .disabled:
            return BlindBoxL10n.ticketExchangeUnavailable
        case let .insufficientPoints(required, current):
            return BlindBoxL10n.needMorePoints(max(required - current, 0))
        case .ticketBalanceAtCapacity:
            return BlindBoxL10n.ticketBalanceFull
        case .grantDayLimitReached:
            return BlindBoxL10n.exchangedToday
        }
    }

    var body: some View {
        ZStack {
            Button(action: onClose) {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BlindBoxL10n.close)

            VStack(spacing: 14) {
                HStack {
                    Text(BlindBoxL10n.getTickets)
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
                    .accessibilityLabel(BlindBoxL10n.close)
                }

                VStack(spacing: 8) {
                    Text(BlindBoxL10n.pointsForTicket(economyConfiguration.pointExchangePrice))
                        .font(.appSystem(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "A46D4C"))
                    Text(BlindBoxL10n.ticketWallet(points: availablePoints, tickets: ticketBalance))
                        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "8A6E59"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))

                Text(BlindBoxL10n.dailyGrant(dailyTicketAllowance))
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: "8A6E59"))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(statusMessage)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(canExchange ? Color(hex: "8A6E59") : Color(hex: "B56D56"))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(BlindBoxL10n.exchangePoints(economyConfiguration.pointExchangePrice)) {
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
                    .accessibilityHint(BlindBoxL10n.exchangeHint(economyConfiguration.pointExchangePrice))
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
                Text(BlindBoxL10n.exchangeConfirmTitle(pointExchangePrice))
                    .font(.appSystem(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "5A412C"))
                Text(BlindBoxL10n.exchangeConfirmDetail)
                    .font(.appSystem(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: "8A6E59"))
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button(BlindBoxL10n.cancel, action: onCancel)
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "A46D4C"))
                        .frame(width: 118, height: 44)
                        .background(.white, in: Capsule())

                    Button(BlindBoxL10n.exchange, action: onConfirm)
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
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
    }
}

private struct BlindBoxRulesIcon: View {
    var body: some View {
        BlindBoxImage("BlindBoxRulesIcon")
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
}

private struct BlindBoxMyBoxIcon: View {
    var body: some View {
        BlindBoxImage("BlindBoxMyBoxIcon")
            .frame(width: 35, height: 35)
            .accessibilityHidden(true)
    }
}

private struct BlindBoxTabBar: View {
    var body: some View {
        HomeMainTabBarView(selectedTab: .constant(.points), isPadLayout: false)
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
                    .scaledToFit()
                    // The middle SVG is a 420 pt export with 30 pt transparent
                    // gutters on each side. Keeping its source width makes its
                    // 360 pt visible cabinet match the top and bottom pieces.
                    .frame(width: 420, height: 175)
                    // Its final 15 pt are transparent. Crop that export tail so
                    // consecutive shelves meet at the pale shelf strip.
                    .scaleEffect(x: 1, y: 0.981, anchor: .top)
                    .frame(width: 420, height: 156, alignment: .top)
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
            .accessibilityLabel("\(BlindBoxL10n.themeName(theme)) \(BlindBoxL10n.blindBoxStickers)")
    }
}

private struct BlindBoxThemeHeader: View {
    let theme: BlindBoxThemeDefinition

    var body: some View {
        BlindBoxImage(theme.id.rawValue == "pets" ? "BlindBoxPetsHeader" : "BlindBoxCozyHeader")
            .accessibilityLabel("\(BlindBoxL10n.themeName(theme)) \(BlindBoxL10n.blindBoxStickers)")
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
            .accessibilityLabel("\(BlindBoxL10n.themeName(theme)) \(BlindBoxL10n.tr("sticker pack", "贴纸包", "貼紙包", "ステッカーパック"))")
    }
}

private struct BlindBoxShelfStatusOverlay: View {
    let title: String
    let fontSize: CGFloat

    var body: some View {
        Text(title)
            .font(.appSystem(size: fontSize, weight: .medium, design: .rounded))
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.62)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white.opacity(0.36))
                    }
            }
            .shadow(color: .white.opacity(0.75), radius: 6)
        .accessibilityHidden(true)
    }
}

private struct BlindBoxPremiumPlaceholder: View {
    let theme: BlindBoxThemeDefinition

    var body: some View {
        ZStack {
            BlindBoxThemeMiniBox(theme: theme)
                .frame(width: 131, height: 149)
                .opacity(0.5)
                .offset(y: -8)
            BlindBoxShelfStatusOverlay(title: BlindBoxL10n.unlockMoreBoxes, fontSize: 11)
                .frame(width: 131, height: 149)
                .offset(y: -8)
        }
        .frame(width: 146, height: 176)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BlindBoxL10n.unlockMoreBoxes)
    }
}

private struct BlindBoxCanvas<Content: View>: View {
    let backgroundAssetName: String?
    let contentHorizontalOffset: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        backgroundAssetName: String? = nil,
        contentHorizontalOffset: CGFloat = 5,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.backgroundAssetName = backgroundAssetName
        self.contentHorizontalOffset = contentHorizontalOffset
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let screenSize = UIScreen.main.bounds.size
            let canvasWidth = max(proxy.size.width, screenSize.width)
            let canvasHeight = max(proxy.size.height, screenSize.height)
            let scale = canvasWidth / 393

            ZStack(alignment: .topLeading) {
                if let backgroundAssetName {
                    Image(backgroundAssetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: 393, height: 852)
                        .scaleEffect(scale, anchor: .topLeading)
                        .accessibilityHidden(true)
                }

                content()
                    .frame(width: 393, height: 852)
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: contentHorizontalOffset * scale)
            }
            .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height, alignment: .topLeading)
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
