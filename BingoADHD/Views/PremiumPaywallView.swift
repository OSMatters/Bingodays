import SwiftUI
import StoreKit

struct PremiumPaywallView: View {
    private enum PaywallPlan: String, CaseIterable, Identifiable {
        case monthly
        case yearly
        case lifetime

        var id: String { rawValue }

        init(kind: PremiumPlanKind) {
            switch kind {
            case .monthly:
                self = .monthly
            case .yearly:
                self = .yearly
            case .lifetime:
                self = .lifetime
            }
        }

        var productID: String {
            switch self {
            case .monthly:
                return SubscriptionManager.monthlyProductID
            case .yearly:
                return SubscriptionManager.yearlyProductID
            case .lifetime:
                return SubscriptionManager.lifetimeProductID
            }
        }

        var title: String {
            switch self {
            case .monthly:
                return L10n.paywallOneMonth
            case .yearly:
                return L10n.paywallOneYear
            case .lifetime:
                return L10n.paywallLifetime
            }
        }
    }

    private enum PaywallRegion {
        case mainlandChina
        case taiwan
        case international

        static var current: PaywallRegion {
            let regionIdentifier = AppLanguage.currentRegionCode

            if regionIdentifier == "HK" {
                return .international
            }
            if regionIdentifier == "TW" || AppLanguage.hasTaiwanLanguageHint {
                return .taiwan
            }
            if regionIdentifier == "CN" {
                return .mainlandChina
            }

            return .international
        }
    }

    private struct PlanPriceDisplay {
        let displayPrice: String
        let subtitle: String?
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    let entrySource: String

    @State private var selectedPlan: PaywallPlan = .monthly
    @State private var feedbackMessage: String?
    @State private var didRunInitialPriceWarmup = false
    @State private var isRetryingPriceLoad = false
    @State private var didLogPaywallView = false

    private let designWidth: CGFloat = 393
    private let designHeight: CGFloat = 852

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var classicPaywallVerticalLift: CGFloat {
        isPadLayout ? 22 : 18
    }

    private var featurePanelHeight: CGFloat {
        isPadLayout ? 232 : 236
    }

    private var isMemberCenter: Bool {
        subscriptionManager.hasPremiumAccess
    }

    private var currentPlan: PaywallPlan? {
        guard let kind = subscriptionManager.currentPlanKind else { return nil }
        return PaywallPlan(kind: kind)
    }

    private var hasLoadedAllPaywallProducts: Bool {
        subscriptionManager.hasLoadedAllPaywallProducts
    }

    private var usesLifetimeTheme: Bool {
        selectedPlan == .lifetime
    }

    private var backgroundGradient: LinearGradient {
        if usesLifetimeTheme {
            return LinearGradient(
                stops: [
                    .init(color: Color(hex: "734A37"), location: 0),
                    .init(color: Color(hex: "1D1002"), location: 0.52549),
                    .init(color: Color(hex: "1D1002"), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            stops: [
                .init(color: Color(hex: "D3A375"), location: 0),
                .init(color: Color(hex: "F2E9DF"), location: 0.42324),
                .init(color: Color(hex: "F2E9DF"), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var featureTitleColor: Color {
        usesLifetimeTheme ? .white : Color(hex: "3F270F")
    }

    private var featureBodyColor: Color {
        usesLifetimeTheme ? .white : Color(hex: "373F4B")
    }

    private var actionButtonColor: Color {
        usesLifetimeTheme ? Color(hex: "D3A375") : Color(hex: "3F270F")
    }

    private var actionButtonTextColor: Color {
        .white
    }

    private var backButtonFillColor: Color {
        Color.black.opacity(0.06)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                paywallBackground
                    .ignoresSafeArea()

                if isMemberCenter {
                    memberCenterContent
                } else {
                    classicPaywallContent(in: geo)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .task {
            if !didRunInitialPriceWarmup {
                didRunInitialPriceWarmup = true
                await refreshProductsForPaywallIfNeeded(force: true)
            } else {
                await refreshProductsForPaywallIfNeeded()
            }
            syncSelectedPlanWithCurrentStatus()
        }
        .onChange(of: subscriptionManager.currentPlanKind) { _, _ in
            syncSelectedPlanWithCurrentStatus()
        }
        .onAppear {
            guard !didLogPaywallView else { return }
            didLogPaywallView = true
            AnalyticsService.logPremiumPaywallViewed(
                source: entrySource,
                isMemberCenter: isMemberCenter
            )
        }
        .alert(L10n.subscription, isPresented: feedbackAlertBinding) {
            Button(L10n.ok) {
                feedbackMessage = nil
            }
        } message: {
            Text(feedbackMessage ?? "")
        }
    }

    @MainActor
    private func refreshProductsForPaywallIfNeeded(force: Bool = false) async {
        guard force || !hasLoadedAllPaywallProducts else { return }
        guard !isRetryingPriceLoad else { return }

        isRetryingPriceLoad = true
        defer { isRetryingPriceLoad = false }

        for attempt in 0..<3 {
            await subscriptionManager.refreshAll()
            if hasLoadedAllPaywallProducts { break }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }

    private var feedbackAlertBinding: Binding<Bool> {
        Binding(
            get: { feedbackMessage != nil },
            set: { isPresented in
                if !isPresented {
                    feedbackMessage = nil
                }
            }
        )
    }

    private func classicPaywallContent(in geo: GeometryProxy) -> some View {
        let scale = min(geo.size.width / designWidth, geo.size.height / designHeight)
        let contentWidth = designWidth * scale
        let horizontalOffset = max((geo.size.width - contentWidth) / 2, 0)

        return ZStack(alignment: .topLeading) {
            heroSection
            featureSection
            planCardsSection
            subscribeButton
            restoreSubscriptionButton
        }
        .frame(width: designWidth, height: designHeight, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .offset(x: horizontalOffset, y: 0)
        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            legalFooter
                .padding(.bottom, 0)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .clipped()
    }

    private var memberCenterContent: some View {
        VStack(spacing: 0) {
            memberCenterHeader
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    memberSummaryCard
                    memberPlanSelectionSection
                    memberActionsSection
                    if selectedPlan == .lifetime && subscriptionManager.hasActiveAutoRenewable {
                        memberNoticeCard(text: L10n.paywallLifetimeAutoRenewNote)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
    }

    private var memberCenterHeader: some View {
        HStack(spacing: 12) {
            backButton
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.paywallMembershipTitle)
                    .font(paywallFont(size: 28, weight: .bold))
                    .foregroundColor(featureTitleColor)
                Text(L10n.paywallMembershipSubtitle)
                    .font(paywallFont(size: 14, weight: .medium))
                    .foregroundColor(featureBodyColor.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 54)
        .padding(.bottom, 14)
    }

    private var memberSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.subscriptionCurrentPlan)
                .font(paywallFont(size: 14, weight: .medium))
                .foregroundColor(featureBodyColor.opacity(0.72))

            Text(currentPlanTitle)
                .font(paywallFont(size: 26, weight: .bold))
                .foregroundColor(featureTitleColor)

            Text(currentPlanDetailText)
                .font(paywallFont(size: 14, weight: .medium))
                .foregroundColor(featureBodyColor.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(memberCardBackground)
    }

    private var memberPlanSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(PaywallPlan.allCases) { plan in
                memberPlanCard(plan)
            }
        }
    }

    private func memberPlanCard(_ plan: PaywallPlan) -> some View {
        let isSelected = selectedPlan == plan
        let isCurrent = currentPlan == plan
        let price = priceDisplay(for: plan)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedPlan = plan
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(paywallFont(size: 19, weight: .semibold))
                            .foregroundColor(featureTitleColor)
                        if isCurrent {
                            Text(L10n.paywallCurrentPlanButton)
                                .font(paywallFont(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color(hex: "3F270F").opacity(0.85))
                                )
                        }
                    }

                    if let subtitle = price.subtitle {
                        Text(subtitle)
                            .font(paywallFont(size: 13, weight: .medium))
                            .foregroundColor(featureBodyColor.opacity(0.72))
                    }
                }

                Spacer(minLength: 12)

                Text(price.displayPrice)
                    .font(paywallFont(size: 22, weight: .semibold))
                    .foregroundColor(featureTitleColor)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(isSelected ? Color(hex: "D3A375") : Color.white.opacity(0.24), lineWidth: isSelected ? 2.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing || subscriptionManager.hasLifetimeAccess)
        .opacity(subscriptionManager.hasLifetimeAccess && plan != .lifetime ? 0.7 : 1)
    }

    private var memberActionsSection: some View {
        VStack(spacing: 12) {
            Button {
                handlePrimaryMembershipAction()
            } label: {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(actionButtonColor)
                    .frame(height: 54)
                    .overlay {
                        Text(primaryMembershipActionTitle)
                            .font(paywallFont(size: 18, weight: .semibold))
                            .foregroundColor(actionButtonTextColor)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canPerformPrimaryMembershipAction || subscriptionManager.isPurchasing)
            .opacity((!canPerformPrimaryMembershipAction || subscriptionManager.isPurchasing) ? 0.6 : 1)

            HStack(spacing: 12) {
                memberSecondaryActionButton(title: L10n.subscriptionRestoreSubscription) {
                    Task {
                        feedbackMessage = await subscriptionManager.restorePurchases()
                    }
                }

                if subscriptionManager.hasActiveAutoRenewable {
                    memberSecondaryActionButton(title: L10n.paywallManageSubscription) {
                        openManageSubscriptionPage()
                    }
                }
            }
        }
    }

    private func memberSecondaryActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .frame(height: 48)
                .overlay {
                    Text(title)
                        .font(paywallFont(size: 15, weight: .semibold))
                        .foregroundColor(featureTitleColor)
                }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func memberNoticeCard(text: String) -> some View {
        Text(text)
            .font(paywallFont(size: 13, weight: .medium))
            .foregroundColor(featureBodyColor.opacity(0.82))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(memberCardBackground)
    }

    private var memberCardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(selectedPlan == .lifetime ? 0.08 : 0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(selectedPlan == .lifetime ? 0.18 : 0.3), lineWidth: 1)
            )
    }

    private var currentPlanTitle: String {
        guard let currentPlan else {
            return L10n.subscriptionStatusInactive
        }

        return currentPlan.title
    }

    private var currentPlanDetailText: String {
        if subscriptionManager.hasLifetimeAccess {
            return L10n.subscriptionLifetimeOwned
        }

        if let expirationDate = subscriptionManager.currentPlanExpirationDate {
            return L10n.subscriptionRenewsOn(formattedMembershipDate(expirationDate))
        }

        return L10n.subscriptionStatusActive
    }

    private var primaryMembershipActionTitle: String {
        if subscriptionManager.hasLifetimeAccess || currentPlan == selectedPlan {
            return L10n.paywallCurrentPlanButton
        }

        switch selectedPlan {
        case .monthly:
            return L10n.paywallSwitchToMonthly
        case .yearly:
            return L10n.paywallSwitchToYearly
        case .lifetime:
            return L10n.paywallBuyLifetime
        }
    }

    private var canPerformPrimaryMembershipAction: Bool {
        !subscriptionManager.hasLifetimeAccess && currentPlan != selectedPlan
    }

    private func syncSelectedPlanWithCurrentStatus() {
        if let currentPlan {
            selectedPlan = currentPlan
        }
    }

    private func formattedMembershipDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func openManageSubscriptionPage() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        openURL(url) { accepted in
            if !accepted {
                feedbackMessage = L10n.subscriptionManageFailed
            }
        }
    }

    private func handlePrimaryMembershipAction() {
        guard canPerformPrimaryMembershipAction else { return }

        Task {
            let hadAutoRenewableBeforePurchase = subscriptionManager.hasActiveAutoRenewable
            let message = await subscriptionManager.purchase(
                productID: selectedPlan.productID,
                analyticsSource: entrySource,
                analyticsPlan: selectedPlan.rawValue
            )

            if selectedPlan == .lifetime,
               shouldTrackPremiumPurchaseSuccess(for: message),
               hadAutoRenewableBeforePurchase {
                feedbackMessage = L10n.paywallLifetimePurchaseReminder
                return
            }

            if shouldTrackPremiumPurchaseSuccess(for: message) {
                if subscriptionManager.hasPremiumAccess {
                    dismiss()
                } else {
                    feedbackMessage = message
                }
            } else {
                feedbackMessage = message
            }
        }
    }

    private func shouldTrackPremiumPurchaseSuccess(for message: String) -> Bool {
        message == L10n.subscriptionPurchaseSucceeded || message == L10n.subscriptionActivationPending
    }

    private var heroSection: some View {
        ZStack(alignment: .topLeading) {
            backButton
                .offset(x: 10, y: 49)

            Image("PaywallBearAndStar")
                .resizable()
                .interpolation(.high)
                .renderingMode(.original)
                .frame(width: 196.5, height: 146)
                .opacity(usesLifetimeTheme ? 0.98 : 1)
                .offset(x: 98, y: 6)
        }
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image("PaywallBack")
                .resizable()
                .interpolation(.high)
                .renderingMode(.original)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
    }

    private var featureSection: some View {
        ZStack(alignment: .topLeading) {
            featurePanelBackground

            Text(L10n.paywallUnlockProFeatures)
                .font(paywallFont(size: 24, weight: .bold))
                .foregroundColor(featureTitleColor)
                .frame(width: 373, alignment: .center)
                .offset(x: 0, y: 28)

            featureRow(
                text: L10n.paywallUnlimitedBoardsTasksAndGroups,
                x: 36,
                y: 94
            )

            featureRow(
                text: L10n.paywallEditAllHistoryTasks,
                x: 36,
                y: 145
            )

            featureRow(
                text: L10n.paywallCustomResetTime,
                x: 36,
                y: 196
            )

        }
        .frame(width: 373, height: featurePanelHeight)
        .offset(x: 10, y: 183 - classicPaywallVerticalLift)
    }

    private var featurePanelBackground: some View {
        Image(usesLifetimeTheme ? "PaywallPrivilegeBGDark" : "PaywallPrivilegeBG")
            .resizable()
            .interpolation(.high)
            .renderingMode(.original)
            .frame(width: 373, height: featurePanelHeight)
    }

    private func featureRow(text: String, x: CGFloat, y: CGFloat) -> some View {
        HStack(spacing: 12) {
            featureCheckIcon
                .frame(width: 19, height: 19)

            Text(text)
                .font(paywallFont(size: 18, weight: .medium))
                .foregroundColor(featureBodyColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .offset(x: x, y: y)
    }

    private var featureCheckIcon: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "D3A375"))

            Image(systemName: "checkmark")
                .font(.appSystem(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private var planCardsSection: some View {
        ZStack(alignment: .topLeading) {
            planCard(.monthly, y: 455 - classicPaywallVerticalLift)
            planCard(.yearly, y: 551 - classicPaywallVerticalLift)
            planCard(.lifetime, y: 647 - classicPaywallVerticalLift)
        }
    }

    private func planCard(_ plan: PaywallPlan, y: CGFloat) -> some View {
        let price = priceDisplay(for: plan)
        let isSelected = selectedPlan == plan

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlan = plan
            }
        } label: {
            ZStack(alignment: .topLeading) {
                if usesLifetimeTheme {
                    darkPlanCardBackground(for: plan, isSelected: isSelected)
                } else {
                    lightPlanCardBackground(isSelected: isSelected)
                }

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(plan.title)
                                .font(paywallFont(size: 20, weight: .semibold))
                                .foregroundColor(usesLifetimeTheme ? .white : Color(hex: "3F270F"))
                                .lineLimit(1)
                                .minimumScaleFactor(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)

                            if plan == .yearly {
                                popularBadge
                            }
                        }

                        if let subtitle = price.subtitle {
                            Text(subtitle)
                                .font(paywallFont(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "828282"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(price.displayPrice)
                        .font(paywallFont(size: 32, weight: .medium))
                        .foregroundColor(usesLifetimeTheme ? .white : Color(hex: "3F270F"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, usesLifetimeTheme ? 20 : 24)
                .padding(.vertical, 16)
                .frame(width: 349, height: 80)
            }
            .frame(width: 349, height: 80)
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing)
        .opacity(subscriptionManager.isPurchasing ? 0.92 : 1)
        .offset(x: 21, y: y)
    }

    @ViewBuilder
    private func lightPlanCardBackground(isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        ZStack {
            if isSelected {
                shape
                    .fill(Color.clear)
                    .overlay(
                        shape
                            .stroke(Color(hex: "D3A375"), lineWidth: 3)
                    )
            } else {
                shape
                    .fill(Color(hex: "EDE2D7").opacity(0.88))
                    .overlay(
                        shape
                            .stroke(Color.white.opacity(0.92), lineWidth: 1)
                    )
            }
        }
        .shadow(color: Color.white.opacity(isSelected ? 0.45 : 0.7), radius: 10, x: -4, y: -4)
        .shadow(color: Color(hex: "D3A375").opacity(isSelected ? 0.16 : 0.12), radius: 12, x: 6, y: 6)
    }

    @ViewBuilder
    private func darkPlanCardBackground(for plan: PaywallPlan, isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        shape
            .fill(Color(hex: "321B06"))
            .overlay(
                shape
                    .stroke(isSelected ? Color(hex: "D3A375") : Color(hex: "3F270F"), lineWidth: isSelected ? 3 : 1)
            )
            .shadow(color: Color(hex: "0A0500").opacity(0.35), radius: 10, x: 4, y: 6)
            .shadow(color: Color(hex: "8C5F39").opacity(0.12), radius: 8, x: -3, y: -3)
    }

    private var popularBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    usesLifetimeTheme
                    ? LinearGradient(
                        colors: [Color(hex: "643D19"), Color(hex: "9B6E45"), Color(hex: "58310E")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    : LinearGradient(
                        colors: [Color(hex: "E6B17D"), Color(hex: "E6B78A"), Color(hex: "DBA169")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(
                    color: usesLifetimeTheme ? Color(hex: "0A0500") : Color(hex: "CFD4DA").opacity(0.7),
                    radius: 12,
                    x: 6,
                    y: 6
                )
                .shadow(
                    color: usesLifetimeTheme ? Color(hex: "9D734B").opacity(0.3) : .white.opacity(0.7),
                    radius: 12,
                    x: -6,
                    y: -6
                )

            Text(L10n.paywallPopular)
                .font(paywallFont(size: 13, weight: .medium))
                .foregroundColor(.white)
        }
        .frame(width: 85, height: 26)
    }

    private var subscribeButton: some View {
        Button {
            Task {
                let message = await subscriptionManager.purchase(
                    productID: selectedPlan.productID,
                    analyticsSource: entrySource,
                    analyticsPlan: selectedPlan.rawValue
                )
                if shouldTrackPremiumPurchaseSuccess(for: message) {
                    if subscriptionManager.hasPremiumAccess {
                        dismiss()
                    } else {
                        feedbackMessage = message
                    }
                } else {
                    feedbackMessage = message
                }
            }
        } label: {
            RoundedRectangle(cornerRadius: 100, style: .continuous)
                .fill(actionButtonColor)
                .frame(width: 350, height: 56)
                .overlay {
                    Text(subscriptionManager.isPurchasing ? L10n.subscriptionPleaseWait : L10n.paywallSubscribeNow)
                        .font(paywallFont(size: 20, weight: .semibold))
                        .foregroundColor(actionButtonTextColor)
                }
                .shadow(
                    color: usesLifetimeTheme ? .clear : Color(hex: "CFD4DA").opacity(0.7),
                    radius: 12,
                    x: 6,
                    y: 6
                )
                .shadow(
                    color: usesLifetimeTheme ? .clear : .white.opacity(0.7),
                    radius: 12,
                    x: -6,
                    y: -6
                )
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing)
        .opacity(subscriptionManager.isPurchasing ? 0.92 : 1)
        .offset(x: 20, y: 755 - classicPaywallVerticalLift)
    }

    private var restoreSubscriptionButton: some View {
        Button {
            Task {
                let message = await subscriptionManager.restorePurchases()
                if subscriptionManager.hasPremiumAccess {
                    dismiss()
                } else {
                    feedbackMessage = message
                }
            }
        } label: {
            Text(L10n.subscriptionRestoreSubscription)
                .font(paywallFont(size: 14, weight: .semibold))
                .foregroundColor(usesLifetimeTheme ? .white.opacity(0.95) : .black.opacity(0.82))
                .frame(width: 350, alignment: .center)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing)
        .opacity(subscriptionManager.isPurchasing ? 0.72 : 1)
        .offset(x: 20, y: 817 - classicPaywallVerticalLift)
    }

    private var legalFooter: some View {
        Text(legalFooterAttributedText)
            .font(paywallFont(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.92))
            .tint(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.42)
            .allowsTightening(true)
            .truncationMode(.tail)
            .frame(width: 350)
            .multilineTextAlignment(.center)
    }
    private var legalFooterAttributedText: AttributedString {
        var text = AttributedString(L10n.paywallLegalOneLine)

        if let termsRange = text.range(of: L10n.paywallTermsOfUse) {
            text[termsRange].link = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
        }

        if let privacyRange = text.range(of: L10n.paywallPrivacyPolicy) {
            text[privacyRange].link = URL(string: "https://osmatters.github.io/bingoday-support/privacy")
        }

        return text
    }

    private var paywallBackground: some View {
        Image(usesLifetimeTheme ? "PaywallDarkBG" : "PaywallLightBG")
            .resizable()
            .interpolation(.high)
            .renderingMode(.original)
            .aspectRatio(contentMode: .fill)
    }

    private var wordmarkPositions: [(x: CGFloat, y: CGFloat, opacity: Double)] {
        let baseOpacity = usesLifetimeTheme ? 0.30 : 1.0
        return [
            (-17.7, -73.3, 0.20 * baseOpacity),
            (-7.7, -22.3, 0.20 * baseOpacity),
            (1.8, 30.25, 0.15 * baseOpacity),
            (10.7, 79.46, 0.10 * baseOpacity),
            (19.58, 128.66, 0.05 * baseOpacity),
            (359, -0.86, 0.20 * baseOpacity),
            (369, 50.14, 0.20 * baseOpacity),
            (378.5, 102.73, 0.15 * baseOpacity),
            (387.39, 151.93, 0.10 * baseOpacity),
            (396.29, 201.13, 0.05 * baseOpacity)
        ]
    }

    private func priceDisplay(for plan: PaywallPlan) -> PlanPriceDisplay {
        if let product = subscriptionManager.productsByID[plan.productID] {
            let subtitle: String?
            switch plan {
            case .yearly:
                subtitle = yearlyPerMonthSubtitle(for: product)
            case .lifetime:
                subtitle = L10n.paywallOneTimePayment
            case .monthly:
                subtitle = nil
            }
            return PlanPriceDisplay(displayPrice: product.displayPrice, subtitle: subtitle)
        }

        let cachedPrice = subscriptionManager.displayPrice(for: plan.productID)
        let fallbackSubtitle: String?
        switch plan {
        case .lifetime:
            fallbackSubtitle = L10n.paywallOneTimePayment
        case .yearly, .monthly:
            fallbackSubtitle = nil
        }
        return PlanPriceDisplay(displayPrice: cachedPrice, subtitle: fallbackSubtitle)
    }

    private func yearlyPerMonthSubtitle(for product: Product) -> String {
        let monthlyPrice = NSDecimalNumber(decimal: product.price).dividing(by: 12).decimalValue
        let formattedMonthlyPrice = formattedMonthlyPrice(monthlyPrice, from: product.displayPrice)
        return L10n.paywallPerMonth(formattedMonthlyPrice)
    }

    private func formattedMonthlyPrice(_ monthlyPrice: Decimal, from displayPrice: String) -> String {
        guard let firstDigit = displayPrice.firstIndex(where: { $0.isNumber }),
              let lastDigit = displayPrice.lastIndex(where: { $0.isNumber }) else {
            return decimalString(monthlyPrice, decimalSeparator: ".")
        }

        let prefix = String(displayPrice[..<firstDigit])
        let suffixStart = displayPrice.index(after: lastDigit)
        let suffix = suffixStart < displayPrice.endIndex ? String(displayPrice[suffixStart...]) : ""
        let numericPortion = String(displayPrice[firstDigit...lastDigit])
        let decimalSeparator: String = (numericPortion.contains(",") && !numericPortion.contains(".")) ? "," : "."
        let amount = decimalString(monthlyPrice, decimalSeparator: decimalSeparator)

        return "\(prefix)\(amount)\(suffix)"
    }

    private func decimalString(_ value: Decimal, decimalSeparator: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = decimalSeparator
        formatter.groupingSeparator = ""
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
    }

    private func paywallFont(size: CGFloat, weight: Font.Weight) -> Font {
        switch AppLanguage.current {
        case .english:
            return .custom("Outfit", size: size).weight(weight)
        case .simplifiedChinese, .traditionalChinese, .japanese:
            return .system(size: size, weight: weight, design: .default)
        }
    }

    private func sparkleShape(fill: Color) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 4.19505, y: 0.39209))
            path.addCurve(to: CGPoint(x: 5.17148, y: 0.39209), control1: CGPoint(x: 4.3106, y: -0.1307), control2: CGPoint(x: 5.05593, y: -0.1307))
            path.addLine(to: CGPoint(x: 5.58452, y: 2.26079))
            path.addCurve(to: CGPoint(x: 7.10574, y: 3.78201), control1: CGPoint(x: 5.75247, y: 3.02063), control2: CGPoint(x: 6.34591, y: 3.61406))
            path.addLine(to: CGPoint(x: 8.97444, y: 4.19505))
            path.addCurve(to: CGPoint(x: 8.97444, y: 5.17148), control1: CGPoint(x: 9.49723, y: 4.3106), control2: CGPoint(x: 9.49723, y: 5.05593))
            path.addLine(to: CGPoint(x: 7.10575, y: 5.58452))
            path.addCurve(to: CGPoint(x: 5.58452, y: 7.10574), control1: CGPoint(x: 6.34591, y: 5.75247), control2: CGPoint(x: 5.75247, y: 6.34591))
            path.addLine(to: CGPoint(x: 5.17148, y: 8.97444))
            path.addCurve(to: CGPoint(x: 4.19505, y: 8.97444), control1: CGPoint(x: 5.05593, y: 9.49723), control2: CGPoint(x: 4.3106, y: 9.49723))
            path.addLine(to: CGPoint(x: 3.78201, y: 7.10575))
            path.addCurve(to: CGPoint(x: 2.26079, y: 5.58452), control1: CGPoint(x: 3.61406, y: 6.34591), control2: CGPoint(x: 3.02063, y: 5.75247))
            path.addLine(to: CGPoint(x: 0.39209, y: 5.17148))
            path.addCurve(to: CGPoint(x: 0.39209, y: 4.19505), control1: CGPoint(x: -0.1307, y: 5.05593), control2: CGPoint(x: -0.1307, y: 4.3106))
            path.addLine(to: CGPoint(x: 2.26079, y: 3.78201))
            path.addCurve(to: CGPoint(x: 3.78201, y: 2.26079), control1: CGPoint(x: 3.02063, y: 3.61406), control2: CGPoint(x: 3.61406, y: 3.02063))
            path.addLine(to: CGPoint(x: 4.19505, y: 0.39209))
        }
        .fill(fill)
        .shadow(color: fill.opacity(0.4), radius: 3, x: 0, y: 1)
    }
}
