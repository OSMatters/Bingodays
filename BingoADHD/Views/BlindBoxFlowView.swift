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
    @State private var pendingOpenRequest: BlindBoxOpenRequest?
    @State private var isShowingTicketExchange = false
    @State private var isConfirmingTicketExchange = false
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
                    onSelectCustomRewards: onSelectCustomRewards,
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
                BlindBoxOpenConfirmation(
                    ticketCost: pendingOpenRequest.ticketCost,
                    isWholeBox: pendingOpenRequest.isWholeBox,
                    onCancel: {
                        self.pendingOpenRequest = nil
                    },
                    onConfirm: {
                        confirm(pendingOpenRequest)
                    }
                )
                .zIndex(10)
            }

            if isShowingTicketExchange {
                BlindBoxTicketExchangeSheet(
                    availablePoints: store.previewAvailablePoints,
                    ticketBalance: store.state.ticketBalance,
                    eligibility: store.pointExchangeEligibility(),
                    onClose: {
                        isShowingTicketExchange = false
                    },
                    onRequestExchange: {
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
        withAnimation { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
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
    let onSelectCustomRewards: (() -> Void)?
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
                    BlindBoxImage("BlindBoxMyBoxIcon")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("My Box")
                .position(x: 360, y: 223)

                Button(action: {}) {
                    BlindBoxImage("BlindBoxRulesIcon")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Blind Box rules")
                .position(x: 130, y: 223)

                Image("BlindBoxShelf")
                    .resizable(capInsets: EdgeInsets(top: 38, leading: 24, bottom: 42, trailing: 24), resizingMode: .stretch)
                    .scaledToFill()
                    .frame(width: 360, height: 530)
                    .clipped()
                    .position(x: 196, y: 516)

                lobbyCandidates

                if !isPremium {
                    premiumPlaceholders
                }

                BlindBoxImage("BlindBoxTabBar")
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
                BlindBoxImage("BlindBoxTicketIcon")
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
            BlindBoxImage("BlindBoxPremiumPlaceholder")
                .frame(width: 128, height: 133)
                .position(x: 116, y: 654)
            BlindBoxImage("BlindBoxPremiumPlaceholder")
                .frame(width: 128, height: 133)
                .position(x: 262, y: 654)
        }
    }
}

private struct BlindBoxLobbyCard: View {
    let batch: BlindBoxCandidateBatch
    let theme: BlindBoxThemeDefinition
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                BlindBoxImage(lobbyAssetName)
                    .frame(width: 122, height: 136)

                if batch.isSoldOut {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "6D625A").opacity(0.8))
                            .frame(width: 72, height: 72)
                        BlindBoxImage("BlindBoxRestockingIcon")
                            .frame(width: 72, height: 72)
                    }
                    .offset(y: -17)
                }

                Capsule()
                    .fill(.white)
                    .frame(width: batch.isSoldOut ? 100 : 83, height: 22)
                    .overlay {
                        Text(statusText)
                            .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: "594A3D"))
                    }
                    .offset(y: 11)
            }
            .frame(width: 128, height: 148)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.id.rawValue), \(statusText)")
    }

    private var lobbyAssetName: String {
        theme.id.rawValue == "pets" ? "BlindBoxPetsMyBox" : "BlindBoxCozyMyBox"
    }

    private var statusText: String {
        if batch.isSoldOut {
            return "Refresh in 21:00"
        }
        return "Left: \(batch.remainingPositionCount)/9"
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
                .position(x: 41, y: 74)

                detailTicketBadge
                    .position(x: 197, y: 74)

                BlindBoxImage(headerAssetName)
                    .frame(width: 325, height: 173)
                    .position(x: 200.5, y: 191.1)

                BlindBoxImage(boardAssetName)
                    .frame(width: 362, height: 391)
                    .position(x: 197, y: 473.5)

                positionGrid

                if batch.isSoldOut {
                    Text("Restocks in \(restockText)")
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "88644C"))
                        .position(x: 196, y: 741)
                }

                actionButtons
                    .position(x: 196, y: 714.5)
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
            BlindBoxImage("BlindBoxTicketIcon")
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

    private var headerAssetName: String {
        theme.id.rawValue == "pets"
            ? "BlindBoxPetsHeaderComposite"
            : "BlindBoxCozyHeaderComposite"
    }

    private var boardAssetName: String {
        theme.id.rawValue == "pets" ? "BlindBoxPetsBoard" : "BlindBoxCozyBoard"
    }

    private var restockText: String {
        guard let date = batch.restockAt() else { return "24:00:00" }
        let interval = max(0, Int(date.timeIntervalSinceNow))
        return String(format: "%02d:%02d:%02d", interval / 3600, (interval % 3600) / 60, interval % 60)
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
                    BlindBoxImage("BlindBoxTicketIcon")
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
                Text("Great!")
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 157.5, height: 42)
                    .background(Color(hex: "DCAF7A"), in: Capsule())
            }
            .buttonStyle(.plain)
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
                Text("Great!")
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 157.5, height: 42)
                    .background(Color(hex: "DCAF7A"), in: Capsule())
            }
            .buttonStyle(.plain)
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

    private var selectedTheme: BlindBoxThemeDefinition? {
        themes.first(where: { $0.id == selectedThemeID }) ?? themes.first
    }

    var body: some View {
        BlindBoxCanvas {
            ZStack {
                BlindBoxImage("BlindBoxMyBoxBackground")
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

                Button(action: {}) {
                    Image(systemName: "chevron.left")
                        .font(.appSystem(size: 30, weight: .bold))
                        .foregroundStyle(Color(hex: "CD9863"))
                }
                .buttonStyle(.plain)
                .position(x: 98, y: 742)

                Button(action: {}) {
                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 30, weight: .bold))
                        .foregroundStyle(Color(hex: "CD9863"))
                }
                .buttonStyle(.plain)
                .position(x: 344, y: 742)
            }
        }
    }

    private var collectionThemePicker: some View {
        ZStack {
            BlindBoxImage("BlindBoxMyBoxThemeTray")
                .frame(width: 353, height: 109)
                .position(x: 196.5, y: 177.5)

            ForEach(Array(themes.prefix(2).enumerated()), id: \.element.id) { index, theme in
                Button {
                    selectedThemeID = theme.id
                } label: {
                    BlindBoxImage(theme.id.rawValue == "pets" ? "BlindBoxPetsLobbySet" : "BlindBoxCozyLobbySet")
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
                .position(x: index == 0 ? 69.5 : 152.6, y: 179.5)
            }

            BlindBoxImage("BlindBoxComingSoon")
                .frame(width: 59.21, height: 75)
                .position(x: 236.6, y: 179.5)
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

/// Small states were intentionally not prescribed by the main Figma frames.
/// This confirmation protects the eventual CloudKit transaction from accidental
/// taps while retaining the existing warm, rounded Blind Box visual language.
private struct BlindBoxOpenConfirmation: View {
    let ticketCost: Int
    let isWholeBox: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

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
    }
}

/// The Figma board does not prescribe this small state. It is intentionally a
/// compact continuation of the ticket badge rather than a new primary screen.
private struct BlindBoxTicketExchangeSheet: View {
    let availablePoints: Int
    let ticketBalance: Int
    let eligibility: BlindBoxPointExchangeEligibility
    let onClose: () -> Void
    let onRequestExchange: () -> Void

    private var canExchange: Bool {
        eligibility == .eligible
    }

    private var statusMessage: String {
        switch eligibility {
        case .eligible:
            return "Available once each day. Resets at 4:00 AM."
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
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

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
                    Text("100 points  →  1 ticket")
                        .font(.appSystem(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "A46D4C"))
                    Text("You have \(availablePoints) points · \(ticketBalance)/20 tickets")
                        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "8A6E59"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))

                Text(statusMessage)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(canExchange ? Color(hex: "8A6E59") : Color(hex: "B56D56"))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Exchange 100 points", action: onRequestExchange)
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
                    .accessibilityHint("Exchanges 100 points for one Blind Box ticket")
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
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Exchange 100 points?")
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
        Image(name)
            .resizable()
            .scaledToFit()
    }
}
