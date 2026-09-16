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

    private struct PaywallFeature: Identifiable {
        let id: String
        let text: String
    }

    private struct PaywallBenefit: Identifiable {
        let id: String
        let iconAssetName: String
        let title: String
        let subtitle: String
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    let entrySource: String
    @Binding private var limitedOfferState: LimitedOfferHomeState

    @State private var selectedPlan: PaywallPlan = .lifetime
    @State private var feedbackMessage: String?
    @State private var didRunInitialPriceWarmup = false
    @State private var isRetryingPriceLoad = false
    @State private var didLogPaywallView = false
    @State private var selectedFeatureIndex = 0
    @State private var didSetInitialFeature = false
    @State private var didCompletePremiumPurchase = false

    init(
        entrySource: String,
        limitedOfferState: Binding<LimitedOfferHomeState>
    ) {
        self.entrySource = entrySource
        _limitedOfferState = limitedOfferState
    }

    private let designWidth: CGFloat = 393
    private let designHeight: CGFloat = 852
    @State private var measuredBlindBoxHeroHeight: CGFloat = 0
    private var isBlindBoxHero: Bool { classicHeroBenefit.id == "blindBox" && !isAllFeaturesEntrySource }
    private var blindBoxHeroExtraHeight: CGFloat {
        isBlindBoxHero ? max(0, 188 + measuredBlindBoxHeroHeight + 24 - 343) : 0
    }
    /// Keeps the Blind Box offer close to its hero artwork without changing the
    /// normal paywall layout.
    private let blindBoxPlanCardsLift: CGFloat = 66
    private var classicPaywallContentHeight: CGFloat { 1372 + blindBoxHeroExtraHeight }
    private var classicPlanCardsTop: CGFloat { 343 + blindBoxHeroExtraHeight }
    private let classicPlanCardsHeight: CGFloat = 144
    private let classicPinnedCountdownExtraHeight: CGFloat = 12
    private let classicPinnedBackgroundBleed: CGFloat = 2
    private var classicBenefitsTop: CGFloat { 519 + blindBoxHeroExtraHeight }
    private let classicBenefitsHeight: CGFloat = 521
    private let classicLegalFooterTopSpacing: CGFloat = 24

    private var classicPaywallBodyTop: CGFloat {
        classicBenefitsTop - classicPinnedCountdownExtraHeight
    }

    private var classicPaywallBodyHeight: CGFloat {
        classicPaywallContentHeight - classicPaywallBodyTop
    }

    private var classicLegalFooterTop: CGFloat {
        classicBenefitsTop + classicBenefitsHeight + classicLegalFooterTopSpacing
    }

    private var classicPinnedHeaderBodyHeight: CGFloat {
        return classicPlanCardsHeight + classicPinnedCountdownExtraHeight
    }

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

    private var hasResolvedPaywallPrices: Bool {
        subscriptionManager.hasDisplayPrices(
            for: SubscriptionManager.defaultPaywallProductIDs
        )
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

    private var paywallFeatures: [PaywallFeature] {
        [
            PaywallFeature(id: "boards", text: L10n.paywallFeatureUnlimitedBoards),
            PaywallFeature(id: "grid5x5", text: L10n.paywallFeatureGrid5x5),
            PaywallFeature(id: "quickTasks", text: L10n.paywallFeatureUnlimitedQuickTasks),
            PaywallFeature(id: "groups", text: L10n.paywallFeatureUnlimitedGroups),
            PaywallFeature(id: "customRewards", text: L10n.paywallFeatureCustomRewards),
            PaywallFeature(id: "history", text: L10n.paywallFeatureAllHistoryTasks),
            PaywallFeature(id: "customReset", text: L10n.paywallFeatureCustomResetTime)
        ]
    }

    private var classicPaywallPlanOrder: [PaywallPlan] {
        [.lifetime, .yearly, .monthly]
    }

    private var paywallBenefits: [PaywallBenefit] {
        [
            PaywallBenefit(
                id: "boards",
                iconAssetName: "PaywallBenefitBoards",
                title: L10n.paywallBenefitUnlimitedBoardsTitle,
                subtitle: L10n.paywallBenefitUnlimitedBoardsSubtitle
            ),
            PaywallBenefit(
                id: "bigger",
                iconAssetName: "PaywallBenefitBigger",
                title: L10n.paywallBenefitBiggerBoardsTitle,
                subtitle: L10n.paywallBenefitBiggerBoardsSubtitle
            ),
            PaywallBenefit(
                id: "reusable",
                iconAssetName: "PaywallBenefitReusable",
                title: L10n.paywallBenefitReusableTasksTitle,
                subtitle: L10n.paywallBenefitReusableTasksSubtitle
            ),
            PaywallBenefit(
                id: "groups",
                iconAssetName: "PaywallBenefitTask",
                title: L10n.paywallBenefitTaskGroupsTitle,
                subtitle: L10n.paywallBenefitTaskGroupsSubtitle
            ),
            PaywallBenefit(
                id: "rewards",
                iconAssetName: "PaywallBenefitRewards",
                title: L10n.paywallBenefitCustomRewardsTitle,
                subtitle: L10n.paywallBenefitCustomRewardsSubtitle
            ),
            PaywallBenefit(
                id: "blindBox",
                iconAssetName: "PaywallBenefitBlindBox",
                title: L10n.tr("More Blind Box Surprises", zhHans: "更多盲盒惊喜", zhHant: "更多盲盒驚喜", ja: "ブラインドボックスをもっと楽しむ"),
                subtitle: L10n.tr("Unlock All the Fun of Blind Box", zhHans: "解锁盲盒所有有趣玩法", zhHant: "解鎖盲盒所有有趣玩法", ja: "ブラインドボックスの楽しい遊び方をすべて解放")
            ),
            PaywallBenefit(
                id: "history",
                iconAssetName: "PaywallBenefitHistory",
                title: L10n.paywallBenefitTaskHistoryTitle,
                subtitle: L10n.paywallBenefitTaskHistorySubtitle
            ),
            PaywallBenefit(
                id: "reset",
                iconAssetName: "PaywallBenefitReset",
                title: L10n.paywallBenefitFlexibleResetTitle,
                subtitle: L10n.paywallBenefitFlexibleResetSubtitle
            ),
            PaywallBenefit(
                id: "more",
                iconAssetName: "PaywallBenefitMoreFeature",
                title: L10n.paywallBenefitMoreFeaturesTitle,
                subtitle: L10n.paywallBenefitMoreFeaturesSubtitle
            )
        ]
    }

    private var initialFeatureIndexForEntrySource: Int {
        let featureID = entryFeatureID(for: entrySource)
        return paywallFeatures.firstIndex { $0.id == featureID } ?? 0
    }

    private func entryFeatureID(for source: String) -> String {
        let source = source.lowercased()

        if source.contains("blind_box") || source.contains("blindbox") {
            return "blindBox"
        } else if source.contains("grid") {
            return "grid5x5"
        } else if source.contains("history") {
            return "history"
        } else if source.contains("reset") {
            return "customReset"
        } else if source.contains("reward") {
            return "customRewards"
        } else if source.contains("standalone_task") || source.contains("group_task") || source.contains("task_limit") || source.contains("quick_edit") {
            return "quickTasks"
        } else if source.contains("group_limit") || source.contains("group") {
            return "groups"
        } else if source.contains("board") {
            return "boards"
        } else {
            return "boards"
        }
    }

    private var classicHeroTitle: String {
        if isAllFeaturesEntrySource {
            return L10n.paywallHeroAllFeaturesTitle
        }
        return classicHeroBenefit.title
    }

    private var classicHeroSubtitle: String {
        if isAllFeaturesEntrySource {
            return L10n.paywallHeroAllFeaturesSubtitle
        }
        return classicHeroBenefit.subtitle
    }

    private var isAllFeaturesEntrySource: Bool {
        let normalizedEntrySource = entrySource.lowercased()
        return normalizedEntrySource == "sidebar_pro_entry" || normalizedEntrySource == "me_pro_entry"
    }

    private var classicHeroBenefit: PaywallBenefit {
        let featureID = entryFeatureID(for: entrySource)

        if featureID == "blindBox" {
            return PaywallBenefit(
                id: "blindBox",
                iconAssetName: "PaywallBenefitMoreFeature",
                title: L10n.paywallBenefitBlindBoxTitle,
                subtitle: L10n.paywallBenefitBlindBoxSubtitle
            )
        }

        let benefitID: String

        switch featureID {
        case "grid5x5":
            benefitID = "bigger"
        case "quickTasks":
            benefitID = "reusable"
        case "groups":
            benefitID = "groups"
        case "customRewards":
            benefitID = "rewards"
        case "history":
            benefitID = "history"
        case "customReset":
            benefitID = "reset"
        default:
            benefitID = "boards"
        }

        return paywallBenefits.first { $0.id == benefitID } ?? paywallBenefits[0]
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
        .ignoresSafeArea()
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
            if !didSetInitialFeature {
                selectedFeatureIndex = initialFeatureIndexForEntrySource
                didSetInitialFeature = true
            }
            AppHaptics.prepareForInteraction()
            guard !didLogPaywallView else { return }
            didLogPaywallView = true
            AnalyticsService.logPremiumPaywallViewed(
                source: entrySource,
                isMemberCenter: isMemberCenter
            )
        }
        .onDisappear {
            markLimitedOfferEligibleAfterPaywallExit()
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
        guard force || !hasResolvedPaywallPrices else { return }
        guard !isRetryingPriceLoad else { return }

        isRetryingPriceLoad = true
        defer { isRetryingPriceLoad = false }

        await subscriptionManager.warmupProductsForPaywall(
            requiredProductIDs: SubscriptionManager.defaultPaywallProductIDs
        )
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
        let scale = classicPaywallScale(for: geo.size)
        let contentWidth = designWidth * scale
        let pinnedTopInset = min(classicPlanCardsTop, (geo.safeAreaInsets.top + 60) / scale)

        return ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                heroSection
                    // The pinned header paints its inset too; reserve the entire hero
                    // so that background cannot cover the last subtitle lines.
                    .frame(width: designWidth, height: classicPlanCardsTop - (isBlindBoxHero ? blindBoxPlanCardsLift : pinnedTopInset), alignment: .topLeading)

                Section {
                    ZStack(alignment: .topLeading) {
                        benefitsSection
                            .offset(x: 0, y: -classicPaywallBodyTop)
                        legalFooter
                            .offset(x: 0, y: -classicPaywallBodyTop)
                    }
                    .frame(width: designWidth, height: classicPaywallBodyHeight, alignment: .topLeading)
                } header: {
                    pinnedPlanCardsHeader(topInset: pinnedTopInset)
                }
            }
            .frame(width: designWidth, height: classicPaywallContentHeight + (isBlindBoxHero ? pinnedTopInset - blindBoxPlanCardsLift : 0), alignment: .topLeading)
            .background(alignment: .top) {
                classicPaywallScrollBackground
            }
            .scaleEffect(scale, anchor: .top)
            .frame(width: contentWidth, height: (classicPaywallContentHeight + (isBlindBoxHero ? pinnedTopInset - blindBoxPlanCardsLift : 0)) * scale, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: geo.size.width, height: geo.size.height)
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            floatingSubscribeButton(scale: scale, bottomInset: geo.safeAreaInsets.bottom)
        }
    }

    private func classicPaywallScale(for size: CGSize) -> CGFloat {
        let widthScale = size.width / designWidth
        guard isPadLayout else { return widthScale }
        return min(widthScale, 1.12)
    }

    private func pinnedPlanCardsHeader(topInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(width: designWidth, height: topInset)
                .allowsHitTesting(false)
            planCardsSection
            Color.clear
                .frame(width: designWidth, height: classicPinnedCountdownExtraHeight)
                .allowsHitTesting(false)
        }
        .frame(
            width: designWidth,
            height: topInset + classicPinnedHeaderBodyHeight,
            alignment: .top
        )
        .background(alignment: .top) {
            classicPaywallPinnedHeaderBackground(topInset: topInset)
                .allowsHitTesting(false)
        }
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
            selectPlan(plan, animationDuration: 0.18)
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
        !subscriptionManager.hasLifetimeAccess
            && currentPlan != selectedPlan
            && subscriptionManager.isReadyToPurchase(productID: selectedPlan.productID)
    }

    private func syncSelectedPlanWithCurrentStatus() {
        if let currentPlan {
            selectedPlan = currentPlan
        }
    }

    private func selectPlan(_ plan: PaywallPlan, animationDuration: Double) {
        guard selectedPlan != plan else { return }
        AppHaptics.control()
        withAnimation(.easeInOut(duration: animationDuration)) {
            selectedPlan = plan
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
            let outcome = await subscriptionManager.purchase(
                productID: selectedPlan.productID,
                analyticsSource: entrySource,
                analyticsPlan: selectedPlan.rawValue
            )
            updateLimitedOfferEligibility(afterPurchaseOutcome: outcome)

            if selectedPlan == .lifetime,
               outcome.completedPurchase,
               hadAutoRenewableBeforePurchase {
                feedbackMessage = L10n.paywallLifetimePurchaseReminder
                return
            }

            if outcome.completedPurchase {
                if subscriptionManager.hasPremiumAccess {
                    dismiss()
                } else {
                    feedbackMessage = outcome.feedbackMessage
                }
            } else {
                feedbackMessage = outcome.feedbackMessage
            }
        }
    }

    private func updateLimitedOfferEligibility(afterPurchaseOutcome outcome: SubscriptionPurchaseOutcome) {
        if outcome.completedPurchase {
            clearLimitedOfferStateAfterPurchase()
        }
    }

    private func clearLimitedOfferStateAfterPurchase() {
        didCompletePremiumPurchase = true
        limitedOfferState = LimitedOfferHomeRules.applyingConfirmedPurchase(to: limitedOfferState)
        NotificationCenter.default.post(name: .limitedOfferEligibilityDidChange, object: nil)
    }

    private func markLimitedOfferEligibleAfterPaywallExit() {
        if !subscriptionManager.hasPremiumAccess && !didCompletePremiumPurchase {
            limitedOfferState = LimitedOfferHomeRules.applyingPaywallExitWithoutPurchase(
                to: limitedOfferState
            )
            NotificationCenter.default.post(name: .limitedOfferEligibilityDidChange, object: nil)
#if DEBUG
            print("[LimitedOffer] Marked eligible after paywall exit")
#endif
        }
    }

    private var classicPaywallScrollBackground: some View {
        ZStack(alignment: .top) {
            Color(hex: "1D1002")
                .frame(width: designWidth, height: classicPaywallContentHeight)

            Image("PaywallFigmaBlackBG")
                .resizable()
                .interpolation(.high)
                .renderingMode(.original)
                .frame(width: designWidth, height: designHeight)
        }
        .frame(width: designWidth, height: classicPaywallContentHeight, alignment: .top)
        .clipped()
        .allowsHitTesting(false)
    }

    private func classicPaywallPinnedHeaderBackground(topInset: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color(hex: "1D1002")
                .frame(
                    width: designWidth,
                    height: topInset + classicPinnedHeaderBodyHeight + classicPinnedBackgroundBleed
                )

            Image("PaywallFigmaBlackBG")
                .resizable()
                .interpolation(.high)
                .renderingMode(.original)
                .frame(width: designWidth, height: designHeight)
                // Match the header's actual starting position in the scroll content.
                .offset(y: -(classicPlanCardsTop - (isBlindBoxHero ? blindBoxPlanCardsLift : topInset) - classicPinnedBackgroundBleed))
        }
        .frame(
            width: designWidth,
            height: topInset + classicPinnedHeaderBodyHeight + classicPinnedBackgroundBleed,
            alignment: .top
        )
        .clipped()
        .offset(y: -classicPinnedBackgroundBleed)
        .allowsHitTesting(false)
    }

    private var heroSection: some View {
        ZStack(alignment: .topLeading) {
            backButton
                .offset(x: 20, y: 50)

            restoreSubscriptionButton
                .offset(x: 319, y: 50)

            VStack(alignment: .leading, spacing: 12) {
                Text(classicHeroTitle)
                    .font(paywallFont(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.82)

                Text(classicHeroSubtitle)
                    .font(paywallFont(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "C8BBB3"))
                    .lineSpacing(2)
                    .lineLimit(isBlindBoxHero ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 190, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 42, alignment: .topLeading)
                    .minimumScaleFactor(0.9)
            }
            .frame(width: 260, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                if isBlindBoxHero { measuredBlindBoxHeroHeight = height }
            }
            .offset(x: 23, y: 188)
        }
        .frame(width: designWidth, height: 320 + blindBoxHeroExtraHeight, alignment: .topLeading)
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Circle()
                .fill(Color.white.opacity(0.13))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: "chevron.left")
                        .font(.appSystem(size: 19, weight: .medium))
                        .foregroundColor(.white)
                }
        }
        .buttonStyle(.plain)
    }

    private var planCardsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(classicPaywallPlanOrder) { plan in
                    planCard(plan)
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(width: designWidth, height: 144)
    }

    private func planCard(_ plan: PaywallPlan) -> some View {
        let price = priceDisplay(for: plan)
        let isSelected = selectedPlan == plan
        let titleColor = isSelected ? Color.black : Color.white
        let subtitle = classicPlanSubtitle(for: plan, price: price)

        return Button {
            selectPlan(plan, animationDuration: 0.2)
        } label: {
            ZStack(alignment: .topLeading) {
                planCardBackground(isSelected: isSelected)

                if let badgeAssetName = badgeAssetName(for: plan, isSelected: isSelected) {
                    let badgeSize = badgeDisplaySize(for: plan)
                    Image(badgeAssetName)
                        .resizable()
                        .interpolation(.high)
                        .renderingMode(.original)
                        .frame(width: badgeSize.width, height: badgeSize.height)
                        .offset(x: 200 - badgeSize.width, y: 0)
                }

                Text(plan.title)
                    .font(paywallFont(size: 16, weight: .bold))
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(width: 130, height: 20, alignment: .leading)
                    .offset(x: 16, y: 16)

                Text(spacedCardPrice(price.displayPrice))
                    .font(paywallFont(size: 28, weight: .bold))
                    .foregroundStyle(priceStyle(isSelected: isSelected))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 150, height: 35, alignment: .leading)
                    .offset(x: 16, y: 72)

                if let subtitle {
                    Text(subtitle)
                        .font(paywallFont(size: 12, weight: .regular))
                        .foregroundColor(Color(hex: "828282"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(width: 168, height: 15, alignment: .leading)
                        .offset(x: 16, y: 113)
                }
            }
            .frame(width: 200, height: 144)
        }
        .buttonStyle(.plain)
        .disabled(
            subscriptionManager.isPurchasing
                || !subscriptionManager.isReadyToPurchase(productID: selectedPlan.productID)
        )
        .opacity(
            subscriptionManager.isPurchasing
                || !subscriptionManager.isReadyToPurchase(productID: selectedPlan.productID)
                ? 0.92
                : 1
        )
    }

    private func planCardBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isSelected
                    ? [Color(hex: "FFFAF5"), Color(hex: "F1D1B5")]
                    : [Color(hex: "5C4025"), Color(hex: "3D2610")],
                    startPoint: UnitPoint(x: 0.08, y: 0.0),
                    endPoint: UnitPoint(x: 1.0, y: 1.0)
                )
            )
    }

    private func priceStyle(isSelected: Bool) -> LinearGradient {
        LinearGradient(
            colors: isSelected
            ? [Color(hex: "291E0A"), Color(hex: "D3A375")]
            : [.white, .white],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func badgeAssetName(for plan: PaywallPlan, isSelected: Bool) -> String? {
        switch plan {
        case .lifetime:
            return isSelected ? "PaywallBadgeValueSelected" : "PaywallBadgeValueUnselect"
        case .yearly:
            return isSelected ? "PaywallBadgePopularSelected" : "PaywallBadgePopularUnselect"
        case .monthly:
            return nil
        }
    }

    private func badgeDisplaySize(for plan: PaywallPlan) -> CGSize {
        switch plan {
        case .yearly:
            CGSize(width: 97, height: 24)
        case .lifetime, .monthly:
            CGSize(width: 82, height: 24)
        }
    }

    private var benefitsSection: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 18) {
                Rectangle()
                    .fill(Color(hex: "6A452B").opacity(0.62))
                    .frame(height: 1)
                Text(L10n.paywallGetFullAccess)
                    .font(paywallFont(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "ECD5C2"), Color(hex: "D2A67F")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(width: 119, height: 23)
                Rectangle()
                    .fill(Color(hex: "6A452B").opacity(0.62))
                    .frame(height: 1)
            }
            .frame(width: 343, height: 23)
            .offset(x: 25, y: 0)

            VStack(spacing: 12) {
                ForEach(paywallBenefits) { benefit in
                    benefitRow(benefit)
                }
            }
            .offset(x: 20, y: 47)
        }
        .frame(width: 355, height: classicBenefitsHeight, alignment: .topLeading)
        .offset(x: 0, y: classicBenefitsTop)
    }

    private func benefitRow(_ benefit: PaywallBenefit) -> some View {
        let isLast = benefit.id == "more"
        let isBlindBox = benefit.id == "blindBox"

        return HStack(alignment: .top, spacing: 12) {
            Image(benefit.iconAssetName)
                .resizable()
                .interpolation(.high)
                .renderingMode(.original)
                .frame(width: 32, height: 32)
                .padding(.top, isLast ? 13 : 4)

            VStack(alignment: .leading, spacing: 0) {
                Text(benefit.title)
                    .font(paywallFont(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(width: 306, height: 20, alignment: .leading)

                Text(benefit.subtitle)
                    .font(paywallFont(size: 14, weight: .regular))
                    .foregroundColor(Color(hex: "828282"))
                    .lineLimit(isBlindBox ? nil : (isLast ? 2 : 1))
                    .minimumScaleFactor(0.82)
                    .frame(width: 306, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: isLast ? 36 : 18, alignment: .topLeading)
            }
        }
        .frame(width: 350, alignment: .topLeading)
        .frame(minHeight: isLast ? 58 : 40, alignment: .topLeading)
    }

    private var subscribeButton: some View {
        Button {
            Task {
                await subscriptionManager.refreshEntitlements()
                if subscriptionManager.hasPremiumAccess {
                    dismiss()
                    return
                }
                let outcome = await subscriptionManager.purchase(
                    productID: selectedPlan.productID,
                    analyticsSource: entrySource,
                    analyticsPlan: selectedPlan.rawValue
                )
                updateLimitedOfferEligibility(afterPurchaseOutcome: outcome)
                if outcome.completedPurchase {
                    if subscriptionManager.hasPremiumAccess {
                        dismiss()
                    } else {
                        feedbackMessage = outcome.feedbackMessage
                    }
                } else {
                    feedbackMessage = outcome.feedbackMessage
                }
            }
        } label: {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hex: "D3A375"))
                .frame(width: 350, height: 56)
                .overlay {
                    Text(subscriptionManager.isPurchasing ? L10n.subscriptionPleaseWait : primaryClassicPaywallActionTitle)
                        .font(paywallFont(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing)
        .opacity(subscriptionManager.isPurchasing ? 0.92 : 1)
    }

    private func floatingSubscribeButton(scale: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color(hex: "1D1002").opacity(0),
                    Color(hex: "1D1002").opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 42 * scale)
            .allowsHitTesting(false)

            subscribeButton
                .scaleEffect(scale, anchor: .bottom)
                .frame(width: 350 * scale, height: 56 * scale)
                .shadow(color: Color.black.opacity(0.38), radius: 18 * scale, x: 0, y: 10 * scale)
                .shadow(color: Color(hex: "D3A375").opacity(0.2), radius: 10 * scale, x: 0, y: 0)
                .padding(.bottom, max(32, bottomInset + 16))
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            Color(hex: "1D1002")
                .opacity(0.92)
                .frame(height: (92 * scale) + max(32, bottomInset + 16))
                .allowsHitTesting(false)
        }
    }

    private var restoreSubscriptionButton: some View {
        Button {
            Task {
                let message = await subscriptionManager.restorePurchases()
                if subscriptionManager.hasPremiumAccess {
                    clearLimitedOfferStateAfterPurchase()
                    dismiss()
                } else {
                    feedbackMessage = message
                }
            }
        } label: {
            Text(L10n.subscriptionRestore)
                .font(paywallFont(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: 58, height: 42, alignment: .center)
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing)
        .opacity(subscriptionManager.isPurchasing ? 0.72 : 1)
    }

    private var legalFooter: some View {
        Text(legalFooterAttributedText)
            .font(paywallFont(size: 11, weight: .medium))
            .foregroundColor(Color(hex: "828282"))
            .tint(Color(hex: "828282"))
            .lineLimit(1)
            .minimumScaleFactor(0.42)
            .allowsTightening(true)
            .truncationMode(.tail)
            .frame(width: 314, height: 15)
            .multilineTextAlignment(.center)
            .offset(x: 39, y: classicLegalFooterTop)
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

    @ViewBuilder
    private var paywallBackground: some View {
        if isMemberCenter {
            Image(usesLifetimeTheme ? "PaywallDarkBG" : "PaywallLightBG")
                .resizable()
                .interpolation(.high)
                .renderingMode(.original)
                .aspectRatio(contentMode: .fill)
        } else {
            Color(hex: "1D1002")
        }
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

    private var primaryClassicPaywallActionTitle: String {
        "\(selectedPlan.title) \(priceDisplay(for: selectedPlan).displayPrice)"
    }

    private func classicPlanSubtitle(for plan: PaywallPlan, price: PlanPriceDisplay) -> String? {
        switch plan {
        case .lifetime:
            return L10n.paywallEarlySupporterSubtitle
        case .yearly:
            if let yearlyPrice = subscriptionManager.price(for: plan.productID) {
                let monthlyPrice = NSDecimalNumber(decimal: yearlyPrice).dividing(by: 12).decimalValue
                let formattedMonthlyPrice = formattedMonthlyPrice(
                    monthlyPrice,
                    from: price.displayPrice
                )
                return L10n.paywallOnlyMonthlyPriceSubtitle(formattedMonthlyPrice)
            }
            if let cachedMonthlySubtitle = yearlyMonthlySubtitle(from: price.displayPrice) {
                return cachedMonthlySubtitle
            }
            return price.subtitle
        case .monthly:
            return L10n.paywallMilkTeaPriceSubtitle
        }
    }

    private func spacedCardPrice(_ displayPrice: String) -> String {
        guard let firstDigitIndex = displayPrice.firstIndex(where: { $0.isNumber }) else {
            return displayPrice
        }

        let prefix = displayPrice[..<firstDigitIndex]
        if prefix.isEmpty || prefix.last?.isWhitespace == true {
            return displayPrice
        }

        return "\(prefix) \(displayPrice[firstDigitIndex...])"
    }

    private func priceDisplay(for plan: PaywallPlan) -> PlanPriceDisplay {
        let displayPrice = subscriptionManager.displayPrice(for: plan.productID)
        let subtitle: String?
        switch plan {
        case .lifetime:
            subtitle = L10n.paywallOneTimePayment
        case .yearly:
            if let yearlyPrice = subscriptionManager.price(for: plan.productID) {
                subtitle = yearlyPerMonthSubtitle(
                    yearlyPrice: yearlyPrice,
                    displayPrice: displayPrice
                )
            } else {
                subtitle = yearlyMonthlySubtitle(from: displayPrice)
            }
        case .monthly:
            subtitle = nil
        }
        return PlanPriceDisplay(displayPrice: displayPrice, subtitle: subtitle)
    }

    private func yearlyPerMonthSubtitle(yearlyPrice: Decimal, displayPrice: String) -> String {
        let monthlyPrice = NSDecimalNumber(decimal: yearlyPrice).dividing(by: 12).decimalValue
        let formattedMonthlyPrice = formattedMonthlyPrice(
            monthlyPrice,
            from: displayPrice
        )
        return L10n.paywallPerMonth(formattedMonthlyPrice)
    }

    private func yearlyMonthlySubtitle(from displayPrice: String) -> String? {
        guard let yearlyPrice = decimalPrice(from: displayPrice) else {
            return nil
        }
        let monthlyPrice = NSDecimalNumber(decimal: yearlyPrice).dividing(by: 12).decimalValue
        let formattedMonthlyPrice = formattedMonthlyPrice(monthlyPrice, from: displayPrice)
        return L10n.paywallOnlyMonthlyPriceSubtitle(formattedMonthlyPrice)
    }

    private func decimalPrice(from displayPrice: String) -> Decimal? {
        let allowedCharacters = CharacterSet(charactersIn: "0123456789.,")
        let numericText = displayPrice
            .unicodeScalars
            .filter { allowedCharacters.contains($0) }
            .map(String.init)
            .joined()

        guard !numericText.isEmpty else { return nil }

        let decimalSeparator: Character
        if numericText.contains(",") && !numericText.contains(".") {
            decimalSeparator = ","
        } else {
            decimalSeparator = "."
        }

        let groupingSeparator: Character = decimalSeparator == "." ? "," : "."
        let normalized = numericText
            .filter { $0 != groupingSeparator }
            .map { $0 == decimalSeparator ? "." : String($0) }
            .joined()

        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
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
