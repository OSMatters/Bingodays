import SwiftUI
import UIKit
import CoreText

enum BlindBoxPremiumPaywallEntry {
    static let source = "blind_box"
    static let didDismiss = Notification.Name("blindBoxPaywallDidDismiss")
}

/// Settle tickets while the app is active; presentation remains click-triggered.
struct BlindBoxSilentTicketRefresh: ViewModifier {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var sync: NativeICloudSyncCoordinator
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: "\(subscriptionManager.hasPremiumAccess)-\(sync.state)-\(scenePhase)") {
            guard AppDebugFlags.blindBoxLiveFlowEnabled,
                  scenePhase == .active,
                  case .ready = sync.state else { return }
            let store = BlindBoxFeatureStore()
            while !Task.isCancelled {
                await store.refresh(
                    hasPremiumAccess: subscriptionManager.hasPremiumAccess,
                    candidateZoneWasPresented: false,
                    nativeICloudInitialImportComplete: true
                )
                let next = Calendar.current.nextDate(
                    after: .now, matching: DateComponents(hour: 4),
                    matchingPolicy: .nextTime
                ) ?? Date.now.addingTimeInterval(86400)
                do { try await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 1))) }
                catch { return }
            }
        }
    }
}

/// The Figma-backed, development-only blind-box flow. It intentionally uses a
/// separate preview store until the CloudKit transaction repository is ready.
struct BlindBoxFlowView: View {
    @Environment(\.blindBoxEntranceReady) private var entranceReady
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
    @AppStorage("blindBox.suppressFreeTicketReminder") private var suppressFreeTicketReminder = false
    @State private var isDailyTicketReceipt = false
    @State private var isExplicitTicketWalletEntry = false
    @State private var receivedTickets: Int?
    @State private var isExchangeReceipt = false
    @State private var requiredTickets = 0
    @State private var isProcessingTickets = false
    @State private var isAwaitingUpgrade = false
    @State private var restoreWalletAfterPaywall = false
    @State private var isShowingRules = false
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// The existing reward flow is kept separate while the sticker flow is
    /// replaced. Wiring this closure into the old Custom Rewards tab happens in
    /// the integration pass so it cannot affect a release before this feature is
    /// enabled.
    var onSelectCustomRewards: (() -> Void)?
    var onShowPremiumPaywall: () -> Void = {}

    init(
        previewAvailablePoints: Int = 320,
        onSelectCustomRewards: (() -> Void)? = nil,
        onShowPremiumPaywall: @escaping () -> Void = {}
    ) {
        _store = StateObject(
            wrappedValue: BlindBoxPreviewStore(
                previewAvailablePoints: previewAvailablePoints,
                persistence: .standard
            )
        )
        _connectivity = StateObject(
            wrappedValue: BlindBoxConnectivityMonitor(
                forceOffline: AppDebugFlags.blindBoxPreviewForcesOffline
            )
        )
        self.onSelectCustomRewards = onSelectCustomRewards
        self.onShowPremiumPaywall = onShowPremiumPaywall
    }

    var body: some View {
        ZStack {
            switch route {
            case .lobby:
                BlindBoxLobbyView(
                    highlightsAvailableBoxes: toastMessage == BlindBoxL10n.chooseBoxToOpen,
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
                    onSelectTicketBalance: { showTicketWallet() },
                    onSelectBatch: { batchID in
                        route = .detail(batchID)
                    },
                    onShowMyBox: {
                        route = .myBox
                    },
                    onShowPremiumPaywall: beginUpgrade,
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
                        onTickets: showTicketWallet,
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
                    .allowsHitTesting(false)
                    .zIndex(20)
            }

            if isShowingTicketExchange {
                BlindBoxTicketExchangeSheet(
                    availablePoints: store.previewAvailablePoints,
                    ticketBalance: store.state.ticketBalance,
                    dailyTicketAllowance: BlindBoxTicketPolicy.dailyAllowance(
                        hasPremiumAccess: subscriptionManager.hasPremiumAccess
                    ),
                    eligibility: store.pointExchangeEligibility(),
                    isLobbyEntry: routeDescription == "lobby",
                    isExplicitTicketWalletEntry: isExplicitTicketWalletEntry,
                    isDailyTicketReceipt: isDailyTicketReceipt,
                    receivedTickets: receivedTickets,
                    isExchangeReceipt: isExchangeReceipt,
                    requiredTickets: requiredTickets,
                    exchangesToday: store.state.lastPointExchangeDayIdentifier == BlindBoxGrantDay.identifier(for: .now, calendar: .current) ? store.state.pointExchangesUsedOnLastGrantDay : 0,
                    isProcessing: isProcessingTickets,
                    onUpgrade: beginUpgrade,
                    onGoOpen: {
                        isShowingTicketExchange = false
                        if case .lobby = route {
                            presentToast(BlindBoxL10n.chooseBoxToOpen)
                        }
                    },
                    onClose: {
                        isShowingTicketExchange = false
                    },
                    onRequestExchange: { _ in confirmTicketExchange() }
                )
                .zIndex(10)
            }

        }
        .task(id: subscriptionManager.hasPremiumAccess) {
            if let pendingReveal = store.state.pendingReveal {
                route = .reveal(pendingReveal.result)
            }
            store.refreshTickets(hasPremiumAccess: subscriptionManager.hasPremiumAccess)
        }
        .task(id: "\(entranceReady)-\(routeDescription)-\(store.state.pendingTicketReceipt?.id.uuidString ?? "none")-\(isShowingTicketExchange)-\(isShowingRules)") {
            guard entranceReady, case .lobby = route, !isShowingTicketExchange, !isShowingRules,
                  !isAwaitingUpgrade, let receipt = store.consumeTicketReceipt(), receipt.count > 0,
                  !suppressFreeTicketReminder else { return }
            receivedTickets = receipt.count
            isDailyTicketReceipt = true
            isExchangeReceipt = false
            requiredTickets = 0
            isShowingTicketExchange = true
        }
        .animation(.easeInOut(duration: 0.22), value: routeDescription)
        .onReceive(NotificationCenter.default.publisher(for: BlindBoxPremiumPaywallEntry.didDismiss)) { _ in
            if isAwaitingUpgrade {
                isAwaitingUpgrade = false
                if subscriptionManager.hasPremiumAccess { presentTicketWallet(showReceipt: true) }
                else { isShowingTicketExchange = restoreWalletAfterPaywall }
            }
        }
        .onDisappear {
            toastDismissalTask?.cancel()
        }
        .sheet(isPresented: $isShowingRules) {
            BlindBoxRulesSheet()
        }
    }

    private func beginUpgrade() {
        isAwaitingUpgrade = true
        restoreWalletAfterPaywall = isShowingTicketExchange
        isShowingTicketExchange = false
        onShowPremiumPaywall()
    }

    private func showTicketWallet() {
        isExplicitTicketWalletEntry = true
        presentTicketWallet(showReceipt: false)
    }

    private func presentTicketWallet(showReceipt: Bool) {
        isDailyTicketReceipt = false
        if showReceipt { isExplicitTicketWalletEntry = false }
        store.refreshTickets(hasPremiumAccess: subscriptionManager.hasPremiumAccess)
        requiredTickets = 0
        let receipt = store.consumeTicketReceipt()?.count
        receivedTickets = showReceipt ? receipt : nil
        isExchangeReceipt = false
        isShowingTicketExchange = true
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
        guard !isProcessingTickets else { return }
        store.refreshTickets(hasPremiumAccess: subscriptionManager.hasPremiumAccess)
        let cost = request.mode == .wholeBox
            ? store.state.candidateBatches.first(where: { $0.id == request.batchID })?.remainingPositionCount ?? 1 : 1
        if store.state.ticketBalance < cost {
            isDailyTicketReceipt = false
            isExplicitTicketWalletEntry = false
            requiredTickets = cost
            receivedTickets = nil
            _ = store.consumeTicketReceipt()
            isShowingTicketExchange = true
            return
        }
        guard connectivity.status.canMakeNetworkRequests else {
            presentToast(connectivity.status.unavailableMessage)
            return
        }
        isProcessingTickets = true
        Task {
            defer { isProcessingTickets = false }
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
        guard !isProcessingTickets else { return }
        isProcessingTickets = true
        defer { isProcessingTickets = false }
        guard connectivity.status.canMakeNetworkRequests else {
            presentToast(connectivity.status.unavailableMessage)
            return
        }
        do {
            _ = try store.exchangePointsForOneTicket()
            receivedTickets = 1
            isExchangeReceipt = true
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
    @Environment(\.blindBoxEntranceReady) private var entranceReady
    private enum Route {
        case lobby
        case detail(UUID)
        case reveal(BlindBoxOpenResult)
        case myBox
    }

    @ObservedObject var pointsFeatureStore: PointsFeatureStore
    let totalPoints: Int
    var onSelectCustomRewards: (() -> Void)?
    var onShowPremiumPaywall: () -> Void = {}

    @StateObject private var store = BlindBoxFeatureStore()
    @StateObject private var connectivity = BlindBoxConnectivityMonitor()
    @State private var route: Route = .lobby
    @State private var toastMessage: String?
    @State private var toastDismissalTask: Task<Void, Never>?
    @State private var isShowingTicketExchange = false
    @AppStorage("blindBox.suppressFreeTicketReminder") private var suppressFreeTicketReminder = false
    @State private var isDailyTicketReceipt = false
    @State private var isExplicitTicketWalletEntry = false
    @State private var receivedTickets: Int?
    @State private var isExchangeReceipt = false
    @State private var requiredTickets = 0
    @State private var isProcessingTickets = false
    @State private var isAwaitingUpgrade = false
    @State private var restoreWalletAfterPaywall = false
    @State private var isShowingRules = false
    @State private var isAcknowledgingReveal = false
    @State private var isConsumingDailyTicketReceipt = false
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
                    onBack: { if let onSelectCustomRewards { onSelectCustomRewards() } else { dismiss() } }
                )
            case .failed(let message):
                BlindBoxLiveStatusView(
                    title: BlindBoxL10n.blindBoxUnavailable,
                    message: message,
                    onBack: { if let onSelectCustomRewards { onSelectCustomRewards() } else { dismiss() } }
                )
            case .idle, .loading, .waitingForICloudInitialImport:
                BlindBoxLiveStatusView(
                    title: nativeICloudInitialImportComplete ? BlindBoxL10n.preparingBlindBox : BlindBoxL10n.syncingCollection,
                    message: nativeICloudInitialImportComplete
                        ? BlindBoxL10n.preparingBlindBoxDetail
                        : BlindBoxL10n.syncingCollectionDetail,
                    showsProgress: true,
                    onBack: { if let onSelectCustomRewards { onSelectCustomRewards() } else { dismiss() } }
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
        .task(id: "\(entranceReady)-\(routeDescription)-\(store.accountState.pendingTicketReceipt?.id.uuidString ?? "none")-\(store.availability)-\(isShowingTicketExchange)-\(isShowingRules)-\(isProcessingTickets)-\(scenePhase)") {
            await presentDailyTicketReceiptIfNeeded()
        }
        .onChange(of: store.accountState.pendingReveal) { _, pendingReveal in
            guard let pendingReveal else { return }
            route = .reveal(pendingReveal.result)
        }
        .animation(.easeInOut(duration: 0.22), value: routeDescription)
        .onReceive(NotificationCenter.default.publisher(for: BlindBoxPremiumPaywallEntry.didDismiss)) { _ in
            if isAwaitingUpgrade {
                isAwaitingUpgrade = false
                if subscriptionManager.hasPremiumAccess { presentTicketWallet(showReceipt: true) }
                else { isShowingTicketExchange = restoreWalletAfterPaywall }
            }
        }
        .onDisappear {
            toastDismissalTask?.cancel()
        }
        .sheet(isPresented: $isShowingRules) {
            BlindBoxRulesSheet()
        }
    }

    private func beginUpgrade() {
        isAwaitingUpgrade = true
        restoreWalletAfterPaywall = isShowingTicketExchange
        isShowingTicketExchange = false
        onShowPremiumPaywall()
    }

    private func showTicketWallet() {
        isExplicitTicketWalletEntry = true
        presentTicketWallet(showReceipt: false)
    }

    @MainActor
    private func presentDailyTicketReceiptIfNeeded() async {
        guard entranceReady, isDisplayingLobby, scenePhase == .active, store.availability == .ready,
              !isShowingTicketExchange, !isShowingRules, !isProcessingTickets, !isAwaitingUpgrade,
              !isConsumingDailyTicketReceipt,
              store.accountState.pendingTicketReceipt != nil else { return }
        isConsumingDailyTicketReceipt = true
        defer { isConsumingDailyTicketReceipt = false }
        do {
            guard let receipt = try await store.consumeTicketReceipt(), receipt.count > 0,
                  !suppressFreeTicketReminder, isDisplayingLobby,
                  !isShowingTicketExchange, !isAwaitingUpgrade else { return }
            receivedTickets = receipt.count
            isDailyTicketReceipt = true
            isExchangeReceipt = false
            requiredTickets = 0
            isShowingTicketExchange = true
        } catch { presentFailure(error) }
    }

    private func presentTicketWallet(showReceipt: Bool) {
        isDailyTicketReceipt = false
        if showReceipt { isExplicitTicketWalletEntry = false }
        guard !isProcessingTickets else { return }
        isProcessingTickets = true
        Task {
            defer { isProcessingTickets = false }
            await store.refresh(
                hasPremiumAccess: subscriptionManager.hasPremiumAccess,
                candidateZoneWasPresented: false,
                nativeICloudInitialImportComplete: nativeICloudInitialImportComplete
            )
            do {
                guard store.availability == .ready else { return }
                let receipt = try await store.consumeTicketReceipt()?.count
                receivedTickets = showReceipt ? receipt : nil
                isExchangeReceipt = false
                requiredTickets = 0
                isShowingTicketExchange = true
            } catch { presentFailure(error) }
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
                highlightsAvailableBoxes: toastMessage == BlindBoxL10n.chooseBoxToOpen,
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
                onSelectTicketBalance: { showTicketWallet() },
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
                onShowPremiumPaywall: beginUpgrade,
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
                    onTickets: showTicketWallet,
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
                    .allowsHitTesting(false)
                    .zIndex(20)
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
                    isLobbyEntry: routeDescription == "lobby",
                    isExplicitTicketWalletEntry: isExplicitTicketWalletEntry,
                    isDailyTicketReceipt: isDailyTicketReceipt,
                    receivedTickets: receivedTickets,
                    isExchangeReceipt: isExchangeReceipt,
                    requiredTickets: requiredTickets,
                    exchangesToday: store.accountState.lastPointExchangeDayIdentifier == BlindBoxGrantDay.identifier(for: .now, calendar: .current) ? store.accountState.pointExchangesUsedOnLastGrantDay : 0,
                    isProcessing: isProcessingTickets,
                    onUpgrade: beginUpgrade,
                    onGoOpen: {
                        isShowingTicketExchange = false
                        if case .lobby = route {
                            presentToast(BlindBoxL10n.chooseBoxToOpen)
                        }
                    },
                    onClose: {
                        isShowingTicketExchange = false
                    },
                    onRequestExchange: { configuration in confirmTicketExchange(configuration) }
                )
                .zIndex(10)
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
        guard !isProcessingTickets else { return }
        isProcessingTickets = true
        let openedBatch = store.accountState.candidateBatches.first { $0.id == request.batchID }
        let openedTheme = openedBatch.flatMap { store.theme(for: $0.plan.themeID) }
        Task {
            defer { isProcessingTickets = false }
            await store.refresh(
                hasPremiumAccess: subscriptionManager.hasPremiumAccess,
                candidateZoneWasPresented: false,
                nativeICloudInitialImportComplete: nativeICloudInitialImportComplete
            )
            do {
                guard store.availability == .ready else { return }
                let cost = request.mode == .wholeBox
                    ? store.accountState.candidateBatches.first(where: { $0.id == request.batchID })?.remainingPositionCount ?? 1 : 1
                if store.accountState.ticketBalance < cost {
                    isDailyTicketReceipt = false
                    isExplicitTicketWalletEntry = false
                    requiredTickets = cost
                    receivedTickets = nil
                    _ = try await store.consumeTicketReceipt()
                    isShowingTicketExchange = true
                    return
                }
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
        guard !isProcessingTickets else { return }
        guard connectivity.status.canMakeNetworkRequests else {
            AnalyticsService.logBlindBoxActionFailed(
                action: .pointExchange,
                reason: connectivityFailureReason
            )
            presentToast(connectivity.status.unavailableMessage)
            return
        }
        isProcessingTickets = true
        Task {
            defer { isProcessingTickets = false }
            do {
                let result = try await store.exchangePointsForOneTicket(
                    availablePoints: pointsFeatureStore.availablePoints(totalPoints: totalPoints),
                    expectedEconomyConfigurationVersion: configuration.version
                )
                AnalyticsService.logBlindBoxPointTicketExchanged(result: result)
                pointsFeatureStore.reloadAfterExternalDataChange()
                receivedTickets = 1
                isExchangeReceipt = true
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
    var highlightsAvailableBoxes = false
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
    let onShowPremiumPaywall: () -> Void
    let onDismiss: () -> Void

    private let referenceWidth: CGFloat = 393

    var body: some View {
        BlindBoxCanvas(backgroundAssetName: "BlindBoxLobbyBackground", backgroundVerticalOffset: 20) {
            ZStack {
                Button(action: onSelectCustomRewards ?? onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .appLiquidGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BlindBoxL10n.back)
                .position(x: 38, y: 73)

                ticketBadge
                    .position(x: 292, y: 252)

                Button(action: onShowMyBox) {
                    BlindBoxMyBoxIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BlindBoxL10n.myBox)
                .position(x: 85, y: 252)

                Button(action: onShowRules) {
                    Image(systemName: "questionmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .appLiquidGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BlindBoxL10n.rulesTitle)
                .position(x: 355, y: 73)

                BlindBoxShelf()
                    .frame(width: 360, height: 530)
                    .position(x: 196, y: 536)

                lobbyCandidates
                    .offset(y: 20)

                if hasCollectedEveryActiveTheme, candidates.isEmpty {
                    BlindBoxCollectionCompleteNotice(onShowMyBox: onShowMyBox)
                        .position(x: 196, y: 515)
                }

                if !isPremium {
                    premiumPlaceholders
                        .offset(y: 20)
                }

            }
            .appGlassEffectContainer()
        }
    }

    private var lobbyTabs: some View {
        HStack(spacing: 12) {
            Button {
                onSelectCustomRewards?()
            } label: {
                Text(BlindBoxL10n.customRewards)
                    .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 164, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(BlindBoxL10n.blindBoxStickers)
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 164, height: 44)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(Color(hex: "E5A05E"))
                        .frame(width: 32, height: 4)
                        .offset(y: -3)
                }
                .accessibilityAddTraits(.isSelected)
        }
        .frame(width: 340, height: 44)
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
                Text("\(ticketBalance)/\(BlindBoxRuleConfiguration.maximumTicketBalance)")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
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
                .shadow(color: .white.opacity(highlightsAvailableBoxes && batch.remainingPositionCount > 0 ? 0.8 : 0), radius: 8)
                .animation(.easeOut(duration: 0.2), value: highlightsAvailableBoxes)
                .position(x: slots[index].0, y: slots[index].1)
            }
        }
    }

    @ViewBuilder
    private var premiumPlaceholders: some View {
        if let firstTheme = themes.first {
            let secondTheme = themes.dropFirst().first ?? firstTheme
            BlindBoxPremiumPlaceholder(theme: firstTheme, isCollectionComplete: hasCollectedEveryActiveTheme, onTap: onShowPremiumPaywall)
                .position(x: 116, y: 670)
            BlindBoxPremiumPlaceholder(theme: secondTheme, isCollectionComplete: hasCollectedEveryActiveTheme, onTap: onShowPremiumPaywall)
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
                    .frame(width: 137.5, height: 156.5)
                    .opacity(batch.isSoldOut ? 0.5 : 1)
                    .offset(y: -8)

                if batch.isSoldOut {
                    BlindBoxShelfStatusOverlay(title: BlindBoxL10n.restocking, fontSize: 11)
                        .frame(width: 137.5, height: 156.5)
                        .offset(y: -8)

                    Capsule()
                        .fill(Color.white)
                        .frame(width: 100, height: 22)
                        .overlay {
                            BlindBoxRestockCountdownLabel(
                                restockAt: batch.restockAt(),
                                prefix: "Refresh in",
                                font: .appSystem(size: 10, weight: .medium, design: .rounded),
                                foregroundColor: Color(hex: "594A3D")
                            )
                        }
                        .offset(y: -5)
                } else {
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 83, height: 22)
                        .overlay {
                            Text(statusText)
                                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(hex: "594A3D"))
                        }
                        .offset(y: -5)
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
    let onTickets: () -> Void
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

                detailContent

            }
        }
        .sheet(isPresented: $isShowingOdds) {
            BlindBoxBatchOddsSheet(
                normalStickerCount: theme.normalStickers.count,
                probabilityMode: batch.plan.probabilityMode
            )
        }
    }

    private var detailContent: some View {
        ZStack {
            Button(action: onBack) {
                LiquidGlassIconBadge(
                    systemName: "chevron.left",
                    size: 42,
                    iconSize: 17,
                    foregroundColor: Color(hex: "5A412C"),
                    glassTint: .white
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BlindBoxL10n.back)
            .position(x: 41, y: 74)

            Button(action: onTickets) { detailTicketBadge }
                .buttonStyle(.plain)
                .accessibilityLabel(BlindBoxL10n.getTickets)
                .position(x: 192, y: 74)

            Button {
                isShowingOdds = true
            } label: {
                LiquidGlassIconBadge(
                    systemName: "questionmark",
                    size: 42,
                    iconSize: 17,
                    foregroundColor: Color(hex: "5A412C"),
                    glassTint: .white
                )
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
        }
        .offset(y: 25)
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
            Text("\(ticketBalance)/\(BlindBoxRuleConfiguration.maximumTicketBalance)")
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 44)
                .offset(x: 39)
            BlindBoxTicketIcon()
                .frame(width: 46, height: 46)
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
                .position(x: 137, y: 8)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedOpening = false
    @State private var boxAngle = 0.0
    @State private var boxOffset = 0.0
    @State private var boxOpened = false
    @State private var showsResult = false
    @State private var openingFinished = false
    @State private var stickerRising = false
    @State private var boxFaded = false
    @State private var starsExpanded = false

    private var openedTheme: BlindBoxThemeDefinition? {
        guard let openedSticker else { return nil }
        return themes.first { $0.stickers.contains { $0.id == openedSticker.stickerID } }
    }

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

                Group {
                    if result.openedStickers.count == 1, let openedSticker, let stickerDefinition {
                        singleReveal(openedSticker: openedSticker, stickerDefinition: stickerDefinition)
                    } else {
                        wholeBoxReveal
                    }
                }
                .offset(y: 40)
                .allowsHitTesting(openingFinished)
                .accessibilityHidden(!openingFinished)

                if !openingFinished, let openedTheme {
                    openingBox(theme: openedTheme)
                        .offset(y: 40)
                        .accessibilityLabel(BlindBoxL10n.tr("Opening your box", "正在开盒", "正在開盒", "ボックスを開封中"))
                }
            }
        }
        .task { await animateOpening() }
        .onChange(of: scenePhase) { _, phase in
            // The draw is already committed. Backgrounding must never delay access to it.
            if phase != .active { finishOpening() }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { finishOpening() }
        }
    }

    private func openingBox(theme: BlindBoxThemeDefinition) -> some View {
        ZStack {
            BlindBoxMyBoxThemePackage(theme: theme)
                .frame(width: 180, height: 228)
                .mask(alignment: .top) { Rectangle().frame(height: 82) }
                .offset(y: boxOpened && !reduceMotion ? -95 : 0)
                .rotationEffect(.degrees(boxOpened && !reduceMotion ? -18 : 0))
                .opacity(boxFaded ? 0 : 1)

            if !reduceMotion {
                ForEach(0..<8) { index in
                    let angle = Double(index) * .pi / 4
                    Image(systemName: "star.fill")
                        .font(.system(size: index.isMultiple(of: 2) ? 22 : 14))
                        .foregroundStyle(index.isMultiple(of: 2) ? Color(hex: "FFE49A") : .white)
                        .rotationEffect(.degrees(starsExpanded ? Double(index * 35) : 0))
                        .offset(
                            x: cos(angle) * (starsExpanded ? 145 : 28),
                            y: sin(angle) * (starsExpanded ? 135 : 18) + (starsExpanded ? -20 : 50)
                        )
                        .animation(
                            .timingCurve(0.23, 1, 0.32, 1, duration: 0.5)
                                .delay(index.isMultiple(of: 2) ? 0 : 0.05),
                            value: starsExpanded
                        )
                        .opacity(boxOpened && !showsResult ? 1 : 0)
                }
                .accessibilityHidden(true)
            }

            BlindBoxMyBoxThemePackage(theme: theme)
                .frame(width: 180, height: 228)
                .mask(alignment: .bottom) { Rectangle().frame(height: 146) }
                .offset(y: boxOpened && !reduceMotion ? 55 : 0)
                .opacity(boxFaded ? 0 : 1)
        }
        .rotationEffect(.degrees(reduceMotion ? 0 : boxAngle), anchor: .bottom)
        .offset(x: reduceMotion ? 0 : boxOffset)
        .position(x: 196.5, y: 377.5)
    }

    @MainActor
    private func animateOpening() async {
        guard !startedOpening else { return }
        startedOpening = true
        AppHaptics.prepareForInteraction()
        do {
            if !reduceMotion {
                // Build amplitude across six quick shakes, then settle straight into opening.
                let angles = [-5.0, 5, -7, 7, -10, 10, -12, 12, -9, 9, -5, 5, 0]
                for (index, angle) in angles.enumerated() {
                    guard !openingFinished, scenePhase == .active else { return }
                    withAnimation(.easeInOut(duration: 0.075)) {
                        boxAngle = angle
                        boxOffset = angle * 0.6
                    }
                    if index.isMultiple(of: 2), angle != 0 { AppHaptics.control() }
                    try await Task.sleep(for: .milliseconds(75))
                }
            }
            try Task.checkCancellation()
            guard !openingFinished, scenePhase == .active else { return }
            AppHaptics.emphasis()
            PointsSoundPlayer.shared.playRewardRedeemed()
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.25)) {
                boxOpened = true
            }
            try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 50))
            guard !openingFinished else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.2)) {
                stickerRising = true
            }
            withAnimation(.easeOut(duration: 0.6)) {
                starsExpanded = true
            }
            try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 200))
            guard !openingFinished else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                boxFaded = true
            }
            try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 400))
            guard !openingFinished else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                showsResult = true
            }
            try await Task.sleep(for: .milliseconds(200))
            openingFinished = true
        } catch {
            finishOpening()
        }
    }

    private func finishOpening() {
        boxOpened = true
        stickerRising = true
        boxFaded = true
        starsExpanded = true
        showsResult = true
        openingFinished = true
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
                .opacity(showsResult ? 1 : 0)

            ZStack {
                if stickerDefinition.isHidden {
                    BlindBoxImage("BlindBoxRevealLight")
                        .frame(width: 369, height: 369)
                        .opacity(showsResult ? 1 : 0)
                }
                BlindBoxImage(stickerDefinition.assetName)
                    .frame(width: 231, height: 231)
                    .scaledToFit()
            }
            // Keep this same image alive from the box interior through the settled result.
            .scaleEffect(reduceMotion || stickerRising ? 1 : 0.65)
            .rotationEffect(.degrees(reduceMotion || stickerRising ? 0 : -8))
            .offset(y: reduceMotion || stickerRising ? 0 : 95)
            .opacity(boxOpened ? 1 : 0)
            .position(x: 196.5, y: 377.5)

            if openedSticker.isDuplicate {
                Text(BlindBoxL10n.owned(openedSticker.resultingOwnedCount))
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .position(x: 196.5, y: 525)
                    .opacity(showsResult ? 1 : 0)
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
            .opacity(showsResult ? 1 : 0)
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
                .opacity(showsResult ? 1 : 0)

            let positions: [(CGFloat, CGFloat)] = [
                (99.2, 290.4), (195.2, 290.4), (294.2, 290.4),
                (101.4, 396.2), (195.2, 396.2), (294.2, 396.2),
                (99.2, 499.9), (195.2, 503.5), (294.2, 504)
            ]
            ForEach(Array(result.openedStickers.prefix(positions.count).enumerated()), id: \.element.positionIndex) { index, sticker in
                if let definition = themes
                    .flatMap(\.stickers)
                    .first(where: { $0.id == sticker.stickerID }) {
                    ZStack {
                        if definition.isHidden {
                            BlindBoxImage("BlindBoxRevealLight")
                                .frame(width: 150, height: 150)
                        }
                        BlindBoxImage(definition.assetName)
                            .frame(width: 86.4, height: 86.4)
                            .scaledToFit()
                    }
                    .opacity(boxOpened ? 1 : 0)
                    .scaleEffect(reduceMotion || stickerRising ? 1 : 0.9)
                    // Every result leaves the same box together, then settles into its slot.
                    .position(
                        x: reduceMotion || stickerRising ? positions[index].0 : 196.5,
                        y: reduceMotion || stickerRising ? positions[index].1 : 415
                    )
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
            .opacity(showsResult ? 1 : 0)
        }
        .frame(width: 393, height: 852)
    }
}

private struct BlindBoxCollectionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

                collectionContent
            }
        }
        .onAppear(perform: synchronizeThemeSelection)
        .onChange(of: themes.map(\.id)) { _, _ in
            synchronizeThemeSelection()
        }
    }

    private var collectionContent: some View {
        ZStack {
            Button(action: onBack) {
                LiquidGlassIconBadge(
                    systemName: "chevron.left",
                    size: 42,
                    iconSize: 18,
                    foregroundColor: Color(hex: "5A412C"),
                    glassTint: .white
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

            collectionPager
                .position(x: 194.5, y: 522)
        }
        .offset(y: 25)
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

            let pickerPositions: [CGFloat] = [69.5, 152.6, 236.6, 320.6]
            ForEach(Array(visibleThemes.enumerated()), id: \.element.id) { index, theme in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0)) {
                        selectedThemeID = theme.id
                    }
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

            if selectedPageIndex == max(themePages.count - 1, 0) {
                BlindBoxComingSoonTile()
                    .frame(width: 59.21, height: 75)
                    .position(x: pickerPositions[visibleThemes.count], y: 179.5)
            }
        }
        .frame(width: 393, height: 852)
    }

    private var collectionPager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(themes, id: \.id) { theme in
                    BlindBoxImage("BlindBoxCollectionBook")
                    .frame(width: 345, height: 520)
                    .overlay {
                        // Position stickers in the book's own coordinate space.
                        // An oversized 852pt child would recenter the entire page
                        // before the scroll viewport clips it.
                        ZStack {
                            collectionStickers(for: theme, origin: CGPoint(x: 22, y: 262))
                        }
                    }
                    .contentShape(Rectangle())
                    .clipped()
                    .scrollTransition(.interactive, axis: .horizontal) { [reduceMotion] content, phase in
                        content
                            .rotation3DEffect(
                                .degrees(reduceMotion ? 0 : -phase.value * 28),
                                axis: (x: 0, y: 1, z: 0),
                                anchor: phase.value < 0 ? .trailing : .leading,
                                perspective: 0.35
                            )
                            .scaleEffect(reduceMotion ? 1 : 1 - abs(phase.value) * 0.04)
                            .opacity(reduceMotion ? 1 : 1 - abs(phase.value) * 0.2)
                    }
                    .id(theme.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: Binding<BlindBoxThemeID?>(
            get: { selectedTheme?.id },
            set: { id in
                guard let id, let index = themes.firstIndex(where: { $0.id == id }) else { return }
                selectedThemeID = id
                selectedPageIndex = index / 3
            }
        ))
        .frame(width: 345, height: 520)
    }

    @ViewBuilder
    private func collectionStickers(for theme: BlindBoxThemeDefinition, origin: CGPoint = .zero) -> some View {
        ForEach(collectionLayout(for: theme), id: \.stickerID) { item in
            if let sticker = theme.stickers.first(where: { $0.id == item.stickerID }) {
                BlindBoxCollectionSticker(
                    sticker: sticker,
                    ownedCount: ownedStickerCounts[sticker.id.rawValue] ?? 0,
                    displaySize: CGFloat(item.displaySize)
                )
                .position(x: item.centerX - origin.x, y: item.centerY - origin.y)
            }
        }
    }

    private func collectionLayout(for theme: BlindBoxThemeDefinition) -> [BlindBoxCollectionPlacement] {
        if let presentation = theme.presentation { return presentation.collectionPlacements }
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
    /// A sticker below Secret fills the gap above the orange cat; the bottom
    /// pair balances the page without crowding the rings or page border.
    private func petNormalPlacements(
        for stickers: [BlindBoxStickerDefinition]
    ) -> [BlindBoxCollectionPlacement] {
        let referenceCenters: [String: (x: Double, y: Double)] = [
            "pets_01": (281, 354),
            "pets_12": (118, 446),
            "pets_07": (285, 446),
            "pets_03": (118, 539),
            "pets_02": (198, 551),
            "pets_08": (283, 540),
            "pets_05": (118, 634),
            "pets_11": (199, 642),
            "pets_04": (283, 630),
            "pets_10": (139, 721),
            "pets_06": (196, 466),
            "pets_09": (259, 726)
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

    /// Keeps Cozy Daily's Secret frame while arranging all eleven regular
    /// stickers in a compact, staggered composition around it.
    private func cozyDailyNormalPlacements(
        for stickers: [BlindBoxStickerDefinition]
    ) -> [BlindBoxCollectionPlacement] {
        let referenceCenters: [String: (x: Double, y: Double)] = [
            "cozy_02": (285, 371),
            "cozy_07": (281, 455),
            "cozy_06": (132, 490),
            "cozy_03": (204, 520),
            "cozy_04": (286, 548),
            "cozy_05": (130, 592),
            "cozy_08": (204, 625),
            "cozy_10": (288, 635),
            "cozy_11": (132, 696),
            "cozy_12": (210, 716),
            "cozy_13": (288, 704)
        ]

        return stickers.enumerated().map { index, sticker in
            let fallback = scatteredNormalCenters[index % scatteredNormalCenters.count]
            let center = referenceCenters[sticker.id.rawValue] ?? fallback
            return BlindBoxCollectionPlacement(
                stickerID: sticker.id,
                centerX: center.x,
                centerY: center.y,
                displaySize: 75,
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
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(minWidth: 34, minHeight: 19)
                    .background(Color(hex: "F3E8D9"), in: RoundedRectangle(cornerRadius: 9.5, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                            .stroke(.white, lineWidth: 1.5)
                    }
                    // Keep the count visually attached to the sticker's lower edge.
                    .offset(y: 4)
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
        NavigationStack {
            List {
                Section {
                    BlindBoxNativeInformationRow(
                        title: BlindBoxL10n.regularSticker,
                        detail: BlindBoxL10n.normalOddsDetail(normalPerPositionPercent)
                    )
                    BlindBoxNativeInformationRow(
                        title: BlindBoxL10n.hiddenSticker,
                        detail: BlindBoxL10n.hiddenOddsDetail(
                            perDraw: hiddenPerPositionPercent,
                            perBox: hiddenPerBoxPercent
                        )
                    )
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .navigationTitle(BlindBoxL10n.oddsTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.white)
        .preferredColorScheme(.light)
    }

    private func percent(_ value: Double) -> String {
        "\((value * 100).formatted(.number.precision(.fractionLength(2))))%"
    }
}

/// The main Figma screens include a rules affordance but no corresponding
/// panel. This compact sheet makes the agreed odds and wallet constraints
/// inspectable before a ticket is spent.
private struct BlindBoxRulesSheet: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    BlindBoxNativeInformationRow(title: BlindBoxL10n.dailyTicketsTitle, detail: BlindBoxL10n.dailyTicketsDetail)
                    BlindBoxNativeInformationRow(title: BlindBoxL10n.mixedBoxTitle, detail: BlindBoxL10n.mixedBoxDetail)
                    BlindBoxNativeInformationRow(title: BlindBoxL10n.hiddenOddsTitle, detail: BlindBoxL10n.hiddenOddsDetail)
                    BlindBoxNativeInformationRow(title: BlindBoxL10n.revealedSurprisesTitle, detail: BlindBoxL10n.revealedSurprisesDetail)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .navigationTitle(BlindBoxL10n.rulesTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.white)
        .preferredColorScheme(.light)
    }
}

private struct BlindBoxNativeInformationRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private enum BlindBoxL10n {
    static var receivedTicketsTitle: String { tr("Tickets Received", "获得盲盒券", "獲得盲盒券", "チケット獲得") }
    static var exchangeTicketsTitle: String { tr("Exchange Tickets", "兑换盲盒券", "兌換盲盒券", "チケット交換") }
    static var ticketUnit: String { tr("tickets", "张盲盒券", "張盲盒券", "枚") }
    static var oneTicket: String { tr("1 ticket", "1 张盲盒券", "1 張盲盒券", "チケット1枚") }
    static var goOpenBox: String { tr("Go open a box", "去开盲盒", "去開盲盒", "ボックスを開けよう") }
    static var memberTicketBenefit: String { tr("Get 2 more tickets every day with Premium!", "成为会员，每天多领 2 张盲盒券！", "成為會員，每天多領 2 張盲盒券！", "プレミアムなら毎日チケットが2枚多く！") }
    static var memberTicketComparison: String { tr("Premium: 3 daily · Free: 1 daily", "会员每日 3 张 · 普通用户每日 1 张", "會員每日 3 張 · 一般用戶每日 1 張", "プレミアム：毎日3枚 · 無料：毎日1枚") }
    static var memberTicketAction: String { tr("Get more tickets", "领取更多盲盒券", "領取更多盲盒券", "チケットをもっと受け取る") }
    static var exchangeResetsAtFour: String { tr("Daily limit reached. Exchanges reset at 4 AM.", "今日兑换次数已用完，凌晨 4 点刷新。", "今日兌換次數已用完，凌晨 4 點刷新。", "本日の交換回数を使い切りました。午前4時にリセットされます。") }
    static func pointsAmount(_ count: Int) -> String { tr("\(count) points", "\(count) 积分", "\(count) 積分", "\(count)ポイント") }
    static var dailyExchangeLimit: String { tr("Up to 3 exchanges daily", "每日限兑 3 次", "每日限兌 3 次", "交換は1日3回まで") }
    static func exchangeProgress(_ count: Int) -> String { tr("Daily exchanges: \(count)/3", "今日已兑 \(count)/3 次", "今日已兌 \(count)/3 次", "本日の交換：\(count)/3回") }
    static var dailyTicketRule: String { tr("Free blind-box tickets arrive at 4 AM daily. Remember to claim them!", "每日凌晨4点发放免费盲盒券，记得来领取～", "每日凌晨4點發放免費盲盒券，記得來領取～", "毎日午前4時に無料のブラインドボックスチケットを配布。忘れずに受け取ろう！") }
    static var pointExchangeRule: String { tr("You can exchange points for blind-box tickets up to 3 times a day", "每日可以用积分兑换盲盒券3次", "每日可以用積分兌換盲盒券3次", "ポイントでブラインドボックスチケットを1日3回まで交換できます") }
    static var ticketsExhaustedTitle: String { tr("Not Enough Tickets", "盲盒券不足", "盲盒券不足", "チケットが足りません") }
    static var ticketsFullTitle: String { tr("My Tickets", "我的盲盒券", "我的盲盒券", "所持チケット") }
    static func ticketArrival(_ count: Int) -> String { tr("+\(count) tickets added", "\(count) 张盲盒券已到账", "\(count) 張盲盒券已到帳", "チケット\(count)枚を受け取りました") }
    static var ticketCapacityHint: String { tr("Store up to 20 tickets at a time. Use some to make room for more.", "盲盒券最多可同时存放 20 张，使用后可继续获取", "盲盒券最多可同時存放 20 張，使用後可繼續獲取", "同時に保管できるのは20枚まで。使用するとまた受け取れます") }
    static var ticketsFullDetail: String { tr("You can keep up to 20 tickets. Open a box and discover a new sticker!", "最多可存 20 张，先开个盲盒，收获新贴纸吧！", "最多可存 20 張，先開個盲盒，收穫新貼紙吧！", "チケットは20枚まで。ボックスを開けてステッカーを集めよう！") }
    static var chooseBoxToOpen: String { tr("Choose an available box on the shelf", "点选架上可开启的盲盒，收获新贴纸吧", "點選架上可開啟的盲盒，收穫新貼紙吧", "棚から開けられるボックスを選んでね") }
    static var zeroTickets: String { tr("0 tickets", "0 张盲盒券", "0 張盲盒券", "チケット0枚") }
    static var ticketsExhaustedReturn: String { tr("Come back for more surprises! New tickets arrive at 4 AM.", "明日再继续来抽吧，凌晨 4:00 自动发放新的盲盒券～", "明日再繼續來抽吧，凌晨 4:00 自動發放新的盲盒券～", "また引きに来てね。午前4時に新しいチケットが届きます！") }
    static var exchangedTodayLabel: String { tr("Daily limit reached", "今日已兑 3/3 次", "今日已兌 3/3 次", "本日の交換：3/3回") }
    static var exchangeComeBackTomorrow: String { tr("All 3 exchanges used. Come back tomorrow for more surprises!", "今日 3 次已兑完，明天再来收获惊喜", "今日 3 次已兌完，明天再來收穫驚喜", "本日の3回は交換済み。明日もサプライズを楽しもう！") }
    static var exchangeSuccessTomorrow: String { tr("Enjoy your next surprise!", "去开盲盒，收获下一份惊喜吧", "去開盲盒，收穫下一份驚喜吧", "ボックスを開けて次のサプライズを楽しもう！") }
    static var exchangeRefreshTime: String { tr("Resets daily at 4 AM", "每日凌晨 4 点刷新", "每日凌晨 4 點刷新", "毎日午前4時にリセット") }
    static func dailyExchangeDescription(_ points: Int) -> String { tr("\(points) points for 1 ticket, up to 3 exchanges daily", "\(points) 积分兑换 1 张，每日限兑 3 次", "\(points) 積分兌換 1 張，每日限兌 3 次", "\(points)ポイントで1枚、1日3回まで") }
    static func missingTickets(_ count: Int) -> String { tr("You need \(count) more tickets.", "还差 \(count) 张盲盒券。", "還差 \(count) 張盲盒券。", "チケットがあと\(count)枚必要です。") }
    static func dailyAllowanceCaption(_ count: Int) -> String { tr("\(count) daily tickets · Refreshes at 4 AM", "每日凌晨 4 点发放 \(count) 张盲盒券", "每日凌晨 4 點發放 \(count) 張盲盒券", "毎日午前4時にチケット\(count)枚を付与") }
    static func tr(_ english: String, _ zhHans: String, _ zhHant: String, _ japanese: String) -> String {
        L10n.tr(english, zhHans: zhHans, zhHant: zhHant, ja: japanese)
    }

    static var rulesTitle: String { tr("Blind Box Rules", "盲盒规则", "盲盒規則", "ブラインドボックスのルール") }
    static var closeRules: String { tr("Close Blind Box rules", "关闭盲盒规则", "關閉盲盒規則", "ブラインドボックスのルールを閉じる") }
    static var gotIt: String { tr("Got it", "知道了", "知道了", "わかった") }

    static var dailyTicketsTitle: String { tr("Fresh Tickets Every Day", "每天都有新盲盒券", "每天都有新盲盒券", "毎日チケットが届く") }
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
    static var mixedBoxTitle: String { tr("Every box is a mix", "每盒都是混合款", "每盒都是混合款", "ボックスごとにランダム") }
    static var mixedBoxDetail: String {
        tr(
            "Regular stickers are randomly mixed in each box. Even if you open every spot, you may not collect every regular design.",
            "常规款会随机混合出现；即使开完整盒，也不保证能集齐所有常规款。",
            "常規款會隨機混合出現；即使開完整盒，也不保證能集齊所有常規款。",
            "通常ステッカーはランダムに混ざっています。ボックスをすべて開けても、通常ステッカーをすべて集められるとは限りません。"
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
    static var pointsTicketsTitle: String { tr("Need Another Ticket?", "券不够？", "券不夠？", "チケットが足りない？") }
    static var pointsTicketsDetail: String {
        tr(
            "100 points for 1 ticket, up to 3 exchanges daily.",
            "100 积分兑换 1 张盲盒券，每日限兑 3 次。",
            "100 積分兌換 1 張盲盒券，每日限兌 3 次。",
            "100ポイントでチケット1枚、1日3回まで交換できます。"
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
    static var comingSoon: String { tr("Coming\nSoon", "即将\n推出", "即將\n推出", "近日\n公開") }
    static var customRewards: String { tr("Custom Rewards", "自定义奖励", "自訂獎勵", "カスタム報酬") }
    static var blindBoxStickers: String { tr("Blind box stickers", "盲盒贴纸", "盲盒貼紙", "ブラインドボックスステッカー") }
    static var restocking: String { tr("Restocking", "补货中", "補貨中", "補充中") }
    static var moreStylesComing: String { tr("More new styles are on the way", "更多新款正在路上", "更多新款正在路上", "新しいラインナップが登場予定です") }
    static var moreStylesComingTitle: String { tr("More new styles", "更多新款", "更多新款", "新しいラインナップ") }
    static var moreStylesComingSubtitle: String { tr("are on the way", "正在路上", "正在路上", "登場予定です") }

    static var unlockMoreBoxes: String {
        tr(
            "Upgrade to unlock more box slots",
            "解锁更多盲盒位",
            "升級解鎖更多盲盒位",
            "アップグレードしてボックス枠を増やす"
        )
    }
    static var unlockMoreBoxesTitle: String {
        tr("Upgrade", "解锁更多", "解鎖更多", "アップグレードして")
    }
    static var unlockMoreBoxesSubtitle: String {
        tr("to unlock more box slots", "盲盒位", "盲盒位", "ボックス枠を増やす")
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
        tr("Countdown \(countdown)", "倒计时 \(countdown)", "倒計時 \(countdown)", "更新まで \(countdown)")
    }
    static func restocksIn(_ countdown: String) -> String {
        tr("Restocks in \(countdown)", "将在 \(countdown) 后补货", "將在 \(countdown) 後補貨", "更新まで \(countdown)")
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
    static var exchangedToday: String { tr("All 3 exchanges used today. Come back tomorrow!", "今日 3 次兑换已用完，明天再来吧！", "今日 3 次兌換已用完，明天再來吧！", "本日の3回は交換済みです。また明日！") }
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
    static func exchangeConfirmTitle(_ points: Int) -> String { tr("Exchange \(points) Points?", "确认用 \(points) 积分兑换？", "確認用 \(points) 積分兌換？", "\(points)ポイントを交換しますか？") }
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
        if theme.id.rawValue == "zodiac" { return tr("Zodiac", "星座", "星座", "星座") }
        return theme.id.rawValue == "pets" ? pets : cozyDaily
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

        }
        .sheet(isPresented: $isShowingOdds) {
            if let theme, let probabilityMode {
                BlindBoxBatchOddsSheet(
                    normalStickerCount: theme.normalStickers.count,
                    probabilityMode: probabilityMode
                )
            }
        }
    }

    private func percent(_ value: Double) -> String {
        "\((value * 100).formatted(.number.precision(.fractionLength(2))))%"
    }
}

/// Click-triggered receipt and exchange states share the supplied popup artwork.
private struct BlindBoxTicketExchangeSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var successVisible = false
    let availablePoints: Int
    let ticketBalance: Int
    let dailyTicketAllowance: Int
    let eligibility: BlindBoxPointExchangeEligibility
    var economyConfiguration: BlindBoxEconomyConfiguration = .defaultValue
    var isLobbyEntry = false
    var isExplicitTicketWalletEntry = false
    var isDailyTicketReceipt = false
    @AppStorage("blindBox.suppressFreeTicketReminder") private var suppressFreeTicketReminder = false
    var receivedTickets: Int? = nil
    var isExchangeReceipt = false
    var requiredTickets: Int = 0
    var exchangesToday: Int = 0
    var isProcessing = false
    var onUpgrade: () -> Void = {}
    var onGoOpen: () -> Void = {}
    let onClose: () -> Void
    let onRequestExchange: (BlindBoxEconomyConfiguration) -> Void

    private var isPremium: Bool { dailyTicketAllowance == 3 }
    private var hasExchangedToday: Bool { exchangesToday >= economyConfiguration.effectivePointExchangesPerGrantDay || eligibility == .grantDayLimitReached }
    private var canExchange: Bool { eligibility == .eligible && !hasExchangedToday && !isProcessing }
    private var showsTicketsFull: Bool {
        ticketBalance >= BlindBoxRuleConfiguration.maximumTicketBalance && receivedTickets == nil
    }
    private var showsExchangeOptions: Bool {
        !showsWalletOverview && !showsTicketsFull && receivedTickets == nil
    }
    private var lacksExchangePoints: Bool {
        if case .insufficientPoints = eligibility { return true }
        return false
    }
    /// A full wallet is informational when the user explicitly taps its balance,
    /// regardless of whether that tap happened in the lobby or a box detail page.
    private var showsWalletOverview: Bool {
        !isDailyTicketReceipt && (isLobbyEntry || (isExplicitTicketWalletEntry && showsTicketsFull))
    }
    private var nextFreeTicketsMessage: String {
        BlindBoxL10n.tr("Come back tomorrow! Get \(dailyTicketAllowance) free tickets at 4 AM.",
            "明天再来，凌晨 4 点可领取 \(dailyTicketAllowance) 张免费盲盒券～",
            "明天再來，凌晨 4 點可領取 \(dailyTicketAllowance) 張免費盲盒券～",
            "明日も来てね！午前4時に無料チケット\(dailyTicketAllowance)枚を受け取れます。")
    }
    /// An opening attempt needs more tickets than the user currently has.
    /// This changes the popup's visual context without hiding an available exchange.
    private var showsOpeningTicketShortfall: Bool {
        requiredTickets > ticketBalance && receivedTickets == nil
    }
    private var showsInsufficientTicketHeader: Bool {
        !showsWalletOverview && receivedTickets == nil
            && (ticketBalance == 0 || showsOpeningTicketShortfall)
    }
    /// Give non-members a next step whenever points cannot solve the current ticket need.
    private var shouldShowPremiumTicketBenefit: Bool {
        guard !isDailyTicketReceipt, !showsWalletOverview, !isPremium, !showsTicketsFull else { return false }
        if showsExchangeOptions { return true }
        if requiredTickets > ticketBalance || receivedTickets != nil { return true }
        if hasExchangedToday { return true }
        if case .insufficientPoints = eligibility { return true }
        return false
    }
    private var statusMessage: String? {
        if hasExchangedToday { return BlindBoxL10n.exchangeComeBackTomorrow }
        switch eligibility {
        case .eligible: return nil
        case .disabled: return BlindBoxL10n.ticketExchangeUnavailable
        case let .insufficientPoints(required, current):
            return BlindBoxL10n.needMorePoints(max(required - current, 0)) + " " + BlindBoxL10n.tr("Complete tasks to earn points.", "完成任务即可获得积分。", "完成任務即可獲得積分。", "タスクを完了してポイントを獲得しましょう。")
        case .ticketBalanceAtCapacity: return BlindBoxL10n.ticketBalanceFull
        case .grantDayLimitReached: return BlindBoxL10n.exchangeResetsAtFour
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .onTapGesture { if !isProcessing { onClose() } }

                if !showsWalletOverview, isExchangeReceipt, let receivedTickets {
                    exchangeSuccess(count: receivedTickets)
                        .transition(.opacity)
                } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Image(showsInsufficientTicketHeader ? "BlindBoxTicketExhaustedTop" : "BlindBoxTicketPopupTop")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 288, height: 169)
                            .scaleEffect(1.08, anchor: .bottom)
                            .offset(
                                x: showsInsufficientTicketHeader ? 8 : 0,
                                y: showsInsufficientTicketHeader ? 14 : 0
                            )
                            .overlay(alignment: .bottom) {
                                outlinedTitle
                                    .offset(y: 32)
                            }
                            .padding(.top, 15)
                            .padding(.bottom, -56)
                            // The exchange controls sit closer to the title, while the
                            // bear artwork and its title remain in their original place.
                            .offset(y: 10 + (showsExchangeOptions ? 35 : 0))
                            .zIndex(2)

                        VStack(spacing: 18) {
                            // Reserve the title's space; it is drawn above the bear artwork.
                            Color.clear.frame(height: showsWalletOverview || showsTicketsFull ? 55 : 70).accessibilityHidden(true)
                            if showsWalletOverview {
                                VStack(spacing: 22) {
                                    walletBalanceDisplay
                                    walletRules
                                }
                            } else if showsTicketsFull {
                                walletBalanceDisplay
                            } else if showsExchangeOptions {
                                exchangeOptions
                            } else if let receivedTickets {
                                HStack(spacing: 14) {
                                    Image("BlindBoxTicketIcon")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 62, height: 70)
                                        .accessibilityHidden(true)
                                    receiptCount(receivedTickets)
                                    Text(BlindBoxL10n.ticketUnit)
                                        .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(Color(hex: "A2692A"))
                                .frame(maxWidth: .infinity, minHeight: 90)
                                .background(Color(hex: "FFFBEA"), in: RoundedRectangle(cornerRadius: 20))
                                Text(isExchangeReceipt
                                     ? BlindBoxL10n.exchangeSuccessTomorrow
                                     : BlindBoxL10n.dailyAllowanceCaption(dailyTicketAllowance))
                                    .font(.appSystem(size: 13, design: .rounded))
                                    .foregroundStyle(Color(hex: "8B8172"))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                if isExchangeReceipt {
                                    Text(BlindBoxL10n.exchangeRefreshTime)
                                        .font(.appSystem(size: 11, design: .rounded))
                                        .foregroundStyle(Color(hex: "8B8172"))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                        .padding(.bottom, showsWalletOverview || showsTicketsFull ? 16 : 28)
                        .frame(maxWidth: .infinity)
                        .background(Color(hex: "FCF3DC"), in: RoundedRectangle(cornerRadius: 22))

                        if shouldShowPremiumTicketBenefit {
                            premiumCard
                                .padding(.top, 14)
                                .overlay(alignment: .top) {
                                    HStack {
                                        connector
                                        Spacer()
                                        connector
                                    }
                                    .padding(.horizontal, 28)
                                    .offset(y: -20)
                                    .allowsHitTesting(false)
                                }
                        }

                        if showsTicketsFull && !showsWalletOverview {
                            Button(action: onGoOpen) {
                                Text(BlindBoxL10n.goOpenBox)
                                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(hex: "57361F"))
                                    .frame(width: 180, height: 48)
                                    .background(.white, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(isProcessing)
                            .padding(.top, 22)
                        } else if !showsWalletOverview && receivedTickets != nil && !showsTicketsFull {
                        Button {
                            if receivedTickets != nil { onGoOpen() }
                            else { onRequestExchange(economyConfiguration) }
                        } label: {
                            Text(receivedTickets != nil ? BlindBoxL10n.goOpenBox
                                 : isProcessing ? BlindBoxL10n.saving
                                 : hasExchangedToday ? BlindBoxL10n.exchangedTodayLabel : BlindBoxL10n.exchange)
                                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(hex: "57361F"))
                                .frame(width: 160, height: 44)
                                .background(
                                    receivedTickets != nil || canExchange
                                        ? .white
                                        : Color(hex: "F4E6D0"),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color(hex: "C59565").opacity(receivedTickets != nil || canExchange ? 0 : 0.6), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isProcessing || (receivedTickets == nil && !canExchange))
                        .opacity(receivedTickets != nil || canExchange ? 1 : 0.82)
                        .padding(.top, 22)
                        }

                        if isDailyTicketReceipt {
                            Button { suppressFreeTicketReminder.toggle() } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: suppressFreeTicketReminder ? "checkmark.square.fill" : "square")
                                    Text(BlindBoxL10n.tr("Don't remind me again", "不再提醒", "不再提醒", "今後表示しない"))
                                }
                                .font(.appSystem(size: 13))
                                .foregroundStyle(.white)
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(suppressFreeTicketReminder ? BlindBoxL10n.tr("Selected", "已勾选", "已勾選", "選択済み") : BlindBoxL10n.tr("Not selected", "未勾选", "未勾選", "未選択"))
                            .padding(.top, 6)
                        }

                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.14), in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isProcessing)
                        .accessibilityLabel(BlindBoxL10n.close)
                        .padding(.top, 18)
                    }
                    .frame(width: min(proxy.size.width - 40, 350))
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                    .offset(y: -30)
                    .offset(y: showsExchangeOptions ? -35 : 0)
                }
                }
            }
            .animation(.easeOut(duration: 0.2), value: isExchangeReceipt)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func exchangeSuccess(count: Int) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)
            Image("BlindBoxTicketIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 110, height: 120)
                .rotationEffect(.degrees(reduceMotion || successVisible ? 0 : -8))
                .scaleEffect(reduceMotion || successVisible ? 1 : 0.9)
                .offset(y: reduceMotion || successVisible ? 0 : 16)
                .opacity(successVisible ? 1 : 0)
                .accessibilityHidden(true)

            VStack(spacing: 14) {
                Text(BlindBoxL10n.tr("Exchange Successful", "兑换成功", "兌換成功", "交換しました"))
                    .font(.appSystem(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 12) {
                    receiptCount(count)
                    Text(BlindBoxL10n.ticketUnit)
                        .font(.appSystem(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .opacity(successVisible ? 1 : 0)

            Spacer(minLength: 36)
            Button(action: onClose) {
                Text(BlindBoxL10n.goOpenBox)
                    .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "57361F"))
                    .frame(width: 180, height: 48)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            .padding(.bottom, 52)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
        .task {
            guard !successVisible else { return }
            AppHaptics.completion()
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.2)) {
                successVisible = true
            }
        }
    }

    private var outlinedTitle: some View {
        let title = showsWalletOverview || showsTicketsFull ? BlindBoxL10n.ticketsFullTitle
            : showsInsufficientTicketHeader ? BlindBoxL10n.ticketsExhaustedTitle
            : receivedTickets != nil ? BlindBoxL10n.receivedTicketsTitle : BlindBoxL10n.exchangeTicketsTitle
        return Canvas { context, size in
            let baseFont = UIFont.systemFont(ofSize: 44, weight: .heavy)
            let font = UIFont(descriptor: baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor, size: 44)
            let letters = title.map { String($0) }
            let lines = letters.map {
                CTLineCreateWithAttributedString(NSAttributedString(string: $0, attributes: [.font: font]))
            }
            let widths = lines.map { CTLineGetTypographicBounds($0, nil, nil, nil) }
            let letterSpacing = -3.5
            let totalWidth = max(widths.reduce(0, +) + Double(max(letters.count - 1, 0)) * letterSpacing, 1)
            let scale = min(1, (Double(size.width) - 20) / totalWidth)
            let titlePath = CGMutablePath()
            var cursor = 0.0
            for index in letters.indices {
                let midpoint = cursor + widths[index] / 2
                let progress = (midpoint / totalWidth - 0.5) * 2
                var transform = CGAffineTransform(
                    translationX: (Double(size.width) - totalWidth * scale) / 2 + midpoint * scale,
                    y: Double(size.height) / 2 - 4 + 8 * progress * progress
                )
                transform = transform.rotated(by: atan(32 * progress / (totalWidth * scale))).scaledBy(x: scale, y: -scale)
                let linePath = CGMutablePath()
                for run in CTLineGetGlyphRuns(lines[index]) as! [CTRun] {
                    let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
                    let count = CTRunGetGlyphCount(run)
                    var glyphs = [CGGlyph](repeating: 0, count: count)
                    var positions = [CGPoint](repeating: .zero, count: count)
                    CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                    CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                    for glyphIndex in glyphs.indices {
                        if let path = CTFontCreatePathForGlyph(runFont, glyphs[glyphIndex], nil) {
                            linePath.addPath(path, transform: CGAffineTransform(translationX: positions[glyphIndex].x, y: positions[glyphIndex].y))
                        }
                    }
                }
                let bounds = linePath.boundingBoxOfPath
                if !bounds.isNull {
                    transform = transform.translatedBy(x: -widths[index] / 2, y: -bounds.midY)
                    titlePath.addPath(linePath, transform: transform)
                }
                cursor += widths[index] + letterSpacing
            }
            // Draw the entire outline first so neighboring letters cannot cover each other's fill.
            let path = Path(titlePath)
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 9, lineJoin: .round))
            context.fill(path, with: .color(Color(hex: "BF8A72")))
        }
        .frame(height: 70)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
        .allowsHitTesting(false)
    }

    private var connector: some View {
        Image("BlindBoxTicketConnector")
            .resizable()
            .scaledToFit()
            .frame(width: 22, height: 54)
            .accessibilityHidden(true)
    }

    private var walletBalanceDisplay: some View {
        HStack(spacing: 8) {
            Image("BlindBoxTicketIcon")
                .resizable().scaledToFit()
                .frame(width: 52, height: 58)
                .accessibilityHidden(true)
            HStack(alignment: .bottom, spacing: 0) {
                receiptGlyph("\(ticketBalance)", size: 36, rounded: false,
                             color: Color(hex: ticketBalance == 0 ? "E66C43" : "A2692A"))
                    .offset(x: -4)
                Text("/\(BlindBoxRuleConfiguration.maximumTicketBalance)")
                    .font(.appSystem(size: 17, weight: .heavy))
                    .foregroundStyle(Color(hex: "929292"))
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: 260, minHeight: 72)
        .background(Color(hex: "F5E9CC"), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BlindBoxL10n.ticketsBalance(ticketBalance))
    }

    private var walletRules: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array([BlindBoxL10n.dailyTicketRule, BlindBoxL10n.pointExchangeRule, BlindBoxL10n.ticketCapacityHint].enumerated()), id: \.offset) { index, rule in
                HStack(alignment: .top, spacing: 4) {
                    Text("\(index + 1).")
                    Text(rule).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.appSystem(size: 13))
        .foregroundStyle(Color(hex: "928B7E"))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }

    private var exchangeActionTitle: String {
        if hasExchangedToday {
            return BlindBoxL10n.tr("Tomorrow", "明日再来", "明日再來", "また明日")
        }
        if lacksExchangePoints {
            return BlindBoxL10n.tr("Need points", "积分不足", "積分不足", "ポイント不足")
        }
        if isProcessing { return BlindBoxL10n.saving }
        if eligibility != .eligible {
            return BlindBoxL10n.tr("Unavailable", "暂不可兑", "暫不可兌", "交換できません")
        }
        return BlindBoxL10n.exchange
    }

    private var exchangeOptions: some View {
        let limit = economyConfiguration.effectivePointExchangesPerGrantDay
        let remaining = hasExchangedToday ? 0 : max(limit - max(exchangesToday, 0), 0)
        let price = economyConfiguration.pointExchangePrice
        return VStack(spacing: 16) {
            HStack(spacing: 42) {
                exchangeBalanceBadge(value: "\(ticketBalance)/\(BlindBoxRuleConfiguration.maximumTicketBalance)", isTicket: true)
                exchangeBalanceBadge(value: "\(availablePoints)", isTicket: false)
            }
            .offset(y: 15)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Image("BlindBoxTicketIcon")
                            .resizable().scaledToFit()
                            .frame(width: 28, height: 32)
                            .accessibilityHidden(true)
                        Text(BlindBoxL10n.tr("Tickets", "盲盒券", "盲盒券", "チケット"))
                            .font(.appSystem(size: 17, weight: .semibold))
                            .foregroundStyle(Color(hex: "57361F"))
                    }
                    Text(BlindBoxL10n.tr("\(price) points for 1 ticket", "\(price)积分兑换1张盲盒券", "\(price)積分兌換1張盲盒券", "\(price)ポイントで1枚"))
                    Text(BlindBoxL10n.tr("\(remaining)/\(limit) exchanges left today", "今日剩余 \(remaining)/\(limit) 次", "今日剩餘 \(remaining)/\(limit) 次", "本日の残り \(remaining)/\(limit) 回"))
                }
                .font(.appSystem(size: 12))
                .foregroundStyle(Color(hex: "929292"))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button { onRequestExchange(economyConfiguration) } label: {
                    Text(exchangeActionTitle)
                        .font(.appSystem(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 84, height: 36)
                        .background(Color(hex: canExchange ? "E5A05E" : "BEBBB8"), in: Capsule())
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(!canExchange)
            }
            .padding(14)
            .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))

            VStack(spacing: 6) {
                if !hasExchangedToday, let statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(Color(hex: "A2692A"))
                }
                Text(hasExchangedToday || lacksExchangePoints
                     ? nextFreeTicketsMessage
                     : BlindBoxL10n.tr("Free tickets arrive daily at 4 AM", "每日凌晨4点赠送免费盲盒券", "每日凌晨4點贈送免費盲盒券", "毎日午前4時に無料チケットを配布"))
                    .foregroundStyle(Color(hex: "928B7E"))
            }
            .font(.appSystem(size: 12))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func exchangeBalanceBadge(value: String, isTicket: Bool) -> some View {
        ZStack {
            Capsule()
                .fill(Color(hex: "E3A65E"))
                .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                .frame(width: 88, height: 30)

            Text(value)
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(width: 88, height: 30, alignment: .center)
        }
        .overlay(alignment: .leading) {
            if isTicket {
                Image("BlindBoxTicketIcon")
                    .resizable().scaledToFit()
                    .frame(width: 36, height: 42)
                    .offset(x: -14)
                    .accessibilityHidden(true)
            } else {
                Image("BlindBoxPointIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 29, height: 29)
                    .offset(x: -11)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 88, height: 42)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isTicket ? BlindBoxL10n.ticketsBalance(ticketBalance) : BlindBoxL10n.pointsAmount(availablePoints))
    }

    private func receiptCount(_ count: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            receiptGlyph("+", size: 40, rounded: true)
            receiptGlyph("\(count)", size: 52, rounded: false)
        }
        .fixedSize()
        .padding(.horizontal, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("+\(count)")
    }

    private func receiptGlyph(_ value: String, size: CGFloat, rounded: Bool, color: Color = Color(hex: "A2692A")) -> some View {
        let baseFont = UIFont.systemFont(ofSize: size, weight: .heavy)
        let descriptor = rounded
            ? baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor
            : baseFont.fontDescriptor
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        let characters = Array(value.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
        let outline = CGMutablePath()
        var cursor: CGFloat = 0
        for index in glyphs.indices {
            if let glyphPath = CTFontCreatePathForGlyph(font, glyphs[index], nil) {
                outline.addPath(glyphPath, transform: CGAffineTransform(translationX: cursor, y: 0))
            }
            cursor += advances[index].width
        }
        let bounds = outline.boundingBoxOfPath
        let glyphPath = Path(outline)
        return Canvas { context, canvasSize in
            context.translateBy(x: (canvasSize.width - bounds.width) / 2 - bounds.minX,
                                y: (canvasSize.height + bounds.height) / 2 + bounds.minY)
            context.scaleBy(x: 1, y: -1)
            // Round joins prevent acute glyph corners from extending into miter spikes.
            context.stroke(glyphPath, with: .color(.white),
                           style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            context.fill(glyphPath, with: .color(color))
        }
        .frame(width: bounds.width + 12, height: size * 1.2 + 8)
        .accessibilityHidden(true)
        .compositingGroup()
        .shadow(color: Color(hex: "E7B653").opacity(0.48), radius: 4, x: 0, y: 7)
        .fixedSize()
    }

    private var premiumCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Image("BlindBoxMemberTicketBenefit")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 75)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(BlindBoxL10n.memberTicketBenefit)
                        .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "57361F"))
                }
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: 8)
            }
            Button(action: onUpgrade) {
                Text(BlindBoxL10n.memberTicketAction)
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color(hex: "65CEFF"), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 26)
        .background(
            LinearGradient(colors: [Color(hex: "CFF1FF"), .white], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }
}

/// A soft-cornered star keeps the points badge playful without the sharp spikes
/// of the system symbol at this compact size.
private struct BlindBoxRoundedStar: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.48
        let points: [CGPoint] = (0..<10).map { index in
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 5
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
        guard let first = points.first else { return Path() }
        let radius = min(cornerRadius, outerRadius * 0.32)

        func roundedPoint(from source: CGPoint, toward destination: CGPoint, by distance: CGFloat) -> CGPoint {
            let dx = destination.x - source.x
            let dy = destination.y - source.y
            let length = max(hypot(dx, dy), .leastNonzeroMagnitude)
            return CGPoint(x: source.x + dx / length * distance, y: source.y + dy / length * distance)
        }

        var path = Path()
        let previous = points[points.count - 1]
        path.move(to: roundedPoint(from: first, toward: previous, by: radius))
        for index in points.indices {
            let point = points[index]
            let next = points[(index + 1) % points.count]
            path.addQuadCurve(
                to: roundedPoint(from: point, toward: next, by: radius),
                control: point
            )
        }
        path.closeSubpath()
        return path
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

private struct BlindBoxMyBoxIcon: View {
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(hex: "E3A65E"))
                .frame(width: 70, height: 26)
                .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1.5))
                .offset(x: 14)
            Text("My box")
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 44)
                .offset(x: 39)
            BlindBoxImage("BlindBoxMyBoxIcon")
                .frame(width: 40, height: 40)
                .frame(width: 46, height: 46)
        }
        .frame(width: 92, height: 43)
        .accessibilityHidden(true)
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
        BlindBoxImage(theme.artwork?.lobbyCardAssetName ?? (theme.id.rawValue == "pets" ? "BlindBoxLobbyPets" : "BlindBoxLobbyCozy"))
            .accessibilityLabel("\(BlindBoxL10n.themeName(theme)) \(BlindBoxL10n.blindBoxStickers)")
    }
}

private struct BlindBoxThemeHeader: View {
    let theme: BlindBoxThemeDefinition

    var body: some View {
        BlindBoxImage(theme.artwork?.detailHeaderAssetName ?? (theme.id.rawValue == "pets" ? "BlindBoxPetsHeader" : "BlindBoxCozyHeader"))
            .accessibilityLabel("\(BlindBoxL10n.themeName(theme)) \(BlindBoxL10n.blindBoxStickers)")
    }
}

private struct BlindBoxComingSoonTile: View {
    var body: some View {
        ZStack {
            BlindBoxImage("BlindBoxComingSoon")
            Text(BlindBoxL10n.comingSoon)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "5A412C"))
                .multilineTextAlignment(.center)
                .lineSpacing(-1)
                .offset(y: 9)
        }
    }
}

private struct BlindBoxMyBoxThemePackage: View {
    let theme: BlindBoxThemeDefinition

    var body: some View {
        BlindBoxImage(theme.artwork?.collectionPickerAssetName ?? (theme.id.rawValue == "pets" ? "BlindBoxPetsPackage" : "BlindBoxCozyPackage"))
            .accessibilityLabel("\(BlindBoxL10n.themeName(theme)) \(BlindBoxL10n.tr("sticker pack", "贴纸包", "貼紙包", "ステッカーパック"))")
    }
}

private struct BlindBoxShelfStatusOverlay: View {
    let title: String
    let subtitle: String?
    let fontSize: CGFloat

    init(title: String, subtitle: String? = nil, fontSize: CGFloat) {
        self.title = title
        self.subtitle = subtitle
        self.fontSize = fontSize
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
            if let subtitle {
                Text(subtitle)
            }
        }
            .font(.appSystem(size: fontSize, weight: .medium, design: .rounded))
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
            }
            .shadow(color: .white.opacity(0.75), radius: 6)
        .accessibilityHidden(true)
    }
}

private struct BlindBoxPremiumPlaceholder: View {
    let theme: BlindBoxThemeDefinition
    var isCollectionComplete = false
    let onTap: () -> Void

    var body: some View {
        if isCollectionComplete {
            artwork
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(BlindBoxL10n.moreStylesComing)
        } else {
            Button(action: onTap) { artwork }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(BlindBoxL10n.unlockMoreBoxes)
        }
    }

    private var artwork: some View {
            ZStack {
                BlindBoxThemeMiniBox(theme: theme)
                    .frame(width: 137.5, height: 156.5)
                    .opacity(0.5)
                    .offset(y: -8)
                BlindBoxShelfStatusOverlay(
                    title: isCollectionComplete ? BlindBoxL10n.moreStylesComingTitle : BlindBoxL10n.unlockMoreBoxesTitle,
                    subtitle: isCollectionComplete ? BlindBoxL10n.moreStylesComingSubtitle : BlindBoxL10n.unlockMoreBoxesSubtitle,
                    fontSize: 11
                )
                    .frame(width: 137.5, height: 156.5)
                    .offset(y: -8)
            }
            .frame(width: 146, height: 176)
    }
}

/// Keeps the Figma-authored phone canvas intact while making its presentation
/// safe for iPad, Split View, and rotation.  Blind Box's artwork and tap
/// targets share this coordinate system, so scaling the whole canvas is less
/// error-prone than independently resizing every positioned element.
enum BlindBoxCanvasLayout {
    static let referenceSize = CGSize(width: 393, height: 852)

    struct Metrics: Equatable {
        let scale: CGFloat
        let canvasSize: CGSize
        let origin: CGPoint
    }

    static func metrics(in containerSize: CGSize) -> Metrics {
        let availableWidth = max(containerSize.width, 1)
        let availableHeight = max(containerSize.height, 1)
        let scale = min(
            availableWidth / referenceSize.width,
            availableHeight / referenceSize.height
        )
        let canvasSize = CGSize(
            width: referenceSize.width * scale,
            height: referenceSize.height * scale
        )
        return Metrics(
            scale: scale,
            canvasSize: canvasSize,
            origin: CGPoint(
                x: (availableWidth - canvasSize.width) / 2,
                y: (availableHeight - canvasSize.height) / 2
            )
        )
    }
}

private struct BlindBoxCanvas<Content: View>: View {
    let backgroundAssetName: String?
    let backgroundVerticalOffset: CGFloat
    let contentHorizontalOffset: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        backgroundAssetName: String? = nil,
        backgroundVerticalOffset: CGFloat = 0,
        contentHorizontalOffset: CGFloat = 5,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.backgroundAssetName = backgroundAssetName
        self.backgroundVerticalOffset = backgroundVerticalOffset
        self.contentHorizontalOffset = contentHorizontalOffset
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = BlindBoxCanvasLayout.metrics(in: proxy.size)

            ZStack {
                if backgroundAssetName != "BlindBoxLobbyBackground" {
                    BlindBoxCanvasBackdrop(
                        assetName: backgroundAssetName,
                        containerSize: proxy.size
                    )
                }

                ZStack(alignment: .topLeading) {
                    if let backgroundAssetName {
                        Image(backgroundAssetName)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(
                                width: BlindBoxCanvasLayout.referenceSize.width,
                                height: BlindBoxCanvasLayout.referenceSize.height
                            )
                            .accessibilityHidden(true)
                            .offset(y: backgroundVerticalOffset)
                    }

                    content()
                        .frame(
                            width: BlindBoxCanvasLayout.referenceSize.width,
                            height: BlindBoxCanvasLayout.referenceSize.height
                        )
                        .offset(x: contentHorizontalOffset)
                }
                .frame(
                    width: BlindBoxCanvasLayout.referenceSize.width,
                    height: BlindBoxCanvasLayout.referenceSize.height,
                    alignment: .topLeading
                )
                .scaleEffect(layout.scale)
                .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

private struct BlindBoxCanvasBackdrop: View {
    let assetName: String?
    let containerSize: CGSize

    var body: some View {
        ZStack {
            Color(hex: "F7E9D5")

            if let assetName {
                Image(assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: containerSize.width, height: containerSize.height)
                    .blur(radius: 24)
                    .scaleEffect(1.08)
                    .opacity(0.36)
                    .accessibilityHidden(true)
            }
        }
        .clipped()
        .accessibilityHidden(true)
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
