import SwiftUI
import CoreText
import UIKit
import Combine

enum OnboardingStateResolver {
    static func shouldPresentOnboarding() -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ForceOnboarding") {
            return true
        }
        #endif

        let defaults = UserDefaults.standard

        if defaults.object(forKey: AppSettings.hasSeenOnboardingKey) != nil {
            return defaults.bool(forKey: AppSettings.hasSeenOnboardingKey) == false
        }
        return true
    }
}

struct AppRootView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var shouldShowOnboarding = OnboardingStateResolver.shouldPresentOnboarding()
    @State private var finishedOnboardingInSession = false

    init() {
        FeatureNewBadgeEligibility.initializeIfNeeded()
    }

    var body: some View {
        Group {
            if shouldShowOnboarding {
                OnboardingFlowView(
                    onFinish: {
                        finishedOnboardingInSession = true
                        AnalyticsService.logOnboardingCompleted()
                        UserDefaults.standard.set(true, forKey: AppSettings.hasSeenOnboardingKey)
                        shouldShowOnboarding = false
                    }
                )
            } else {
                ContentView()
            }
        }
        .environmentObject(subscriptionManager)
        .onAppear {
            guard !finishedOnboardingInSession else { return }
            shouldShowOnboarding = OnboardingStateResolver.shouldPresentOnboarding()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            guard !finishedOnboardingInSession else { return }
            shouldShowOnboarding = OnboardingStateResolver.shouldPresentOnboarding()
        }
    }
}

private struct OnboardingEntryView: View {
    let onFinish: () -> Void
    let motionPhase: OnboardingPageMotionPhase
    private let holdDuration: TimeInterval = 0.45
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var pressing = false
    @State private var activated = false
    @State private var continuousHaptics = AppHapticContinuousPlayer()

    private var isExpanding: Bool {
        pressing || activated
    }

    private var circleAnimation: Animation {
        if reduceMotion {
            .easeOut(duration: 0.15)
        } else if isExpanding {
            .linear(duration: holdDuration)
        } else {
            .easeOut(duration: 0.15)
        }
    }

    private func tr(_ en: String, _ zh: String, _ ja: String, _ ko: String, _ de: String) -> String {
        switch AppLanguage.current {
        case .english: en
        case .simplifiedChinese: zh
        case .traditionalChinese: zh.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? zh
        case .japanese: ja
        case .korean: ko
        case .german: de
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: "FCF7F1").ignoresSafeArea()
                activation(size: geometry.size)
            }
            .foregroundStyle(Color(hex: "40270F"))
        }
        .preferredColorScheme(.light)
        .onAppear(perform: AppHaptics.prepareForInteraction)
        .task(id: activated) {
            guard activated else { return }
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard scenePhase == .active else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                onFinish()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                cancelPress()
            }
        }
        .onDisappear(perform: cancelPress)
    }

    private func activation(size: CGSize) -> some View {
        ZStack {
            ForEach(0..<4) { index in
                Circle()
                    .fill(index.isMultiple(of: 2) ? Color(hex: "FAF0E5") : Color.white)
                    .frame(width: CGFloat(4 - index) * 210, height: CGFloat(4 - index) * 210)
                    .scaleEffect(reduceMotion ? 1 : isExpanding ? 1 : 0.2)
                    .opacity(isExpanding ? 1 : 0)
                    .animation(circleAnimation, value: isExpanding)
            }
            VStack(spacing: 48) {
                Image(pressing || activated ? "OnboardingEnterPressed" : "OnboardingEnterNormal")
                    .resizable().scaledToFit()
                    .frame(width: 200, height: 200)
                .scaleEffect(pressing || activated ? 0.96 : 1)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 45) {
                    activate()
                } onPressingChanged: { value in
                    updatePressing(value)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tr("Press and hold to enter the world of Bingo", "长按进入Bingo的世界", "長押ししてBingoの世界へ", "길게 눌러 Bingo의 세계로 들어가기", "Gedrückt halten, um die Welt von Bingo zu betreten"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { activate() }
                .onboardingPageMotion(motionPhase, role: .artwork)
                Text(activated
                    ? tr("Starting Bingodays…", "Bingodays 启动中…", "Bingodaysを起動中…", "Bingodays 시작 중…", "Bingodays startet …")
                    : tr("Press and hold to enter the world of Bingo", "长按进入Bingo的世界", "長押ししてBingoの世界へ", "길게 눌러 Bingo의 세계로 들어가기", "Gedrückt halten, um die Welt von Bingo zu betreten"))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .contentTransition(.opacity)
                    .onboardingPageMotion(motionPhase, role: .supporting)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func activate() {
        guard !activated, scenePhase == .active else { return }
        continuousHaptics.stop()
        AppHaptics.completion()
        activated = true
    }

    private func updatePressing(_ value: Bool) {
        guard !activated, pressing != value else { return }

        if value {
            AppHaptics.control()
            continuousHaptics.start(
                initialIntensity: 0.18,
                peakIntensity: 0.85,
                rampDuration: holdDuration,
                sharpness: 0.25
            )
        } else {
            continuousHaptics.stop()
        }

        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) {
            pressing = value
        }
    }

    private func cancelPress() {
        continuousHaptics.stop()
        pressing = false
        activated = false
    }
}

struct OnboardingFlowView: View {
    private enum Page: Int, CaseIterable, Hashable {
        case intro
        case research
        case brand
        case grid
        case pace
        case entry
    }

    private let canvasSize = CGSize(width: 393, height: 852)
    private let introArtworkScale: CGFloat = 0.9
    private let backgroundColor = Color(hex: "F4EFE9")
    private let primaryTextColor = Color(hex: "17202C")
    private let buttonColor = Color(hex: "4A2F17")
    private let secondaryTextColor = Color(hex: "828282")
    private let pageSwipeThreshold: CGFloat = 44

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var brandDynamicFontSize: CGFloat = 46
    @AccessibilityFocusState private var accessibilityFocusedPage: Page?
    @State private var page: Page
    @State private var motionPhase = OnboardingPageMotionPhase.hidden
    @State private var isMovingForward = true
    @State private var isFinishing = false

    let onFinish: () -> Void

    private var pageBackgroundColor: Color {
        if page == .brand {
            return Color(hex: "FDF7F1")
        }
        return page == .intro || page == .research || page == .grid || page == .pace ? Color(hex: "F4F4F4") : backgroundColor
    }

    private var usesChineseIntroHeadline: Bool {
        AppLanguage.current == .simplifiedChinese || AppLanguage.current == .traditionalChinese
    }

    private var introHeadlineY: CGFloat {
        switch AppLanguage.current {
        case .simplifiedChinese, .traditionalChinese, .japanese: 430
        case .korean: 404
        case .english: 407
        case .german: 408
        }
    }

    private var brandContentVerticalOffset: CGFloat {
        switch AppLanguage.current {
        case .english, .german: 0
        case .simplifiedChinese, .traditionalChinese, .japanese, .korean: 60
        }
    }

    private var researchContinuousHeadline: String {
        let separator: String
        switch AppLanguage.current {
        case .simplifiedChinese, .traditionalChinese, .japanese:
            separator = ""
        case .english, .korean, .german:
            separator = " "
        }
        return L10n.onboardingResearchHeadline.replacingOccurrences(of: "\n", with: separator)
    }

    private var researchStatementWidth: CGFloat {
        AppLanguage.current == .german ? 341 : 310
    }

    private var researchLineSpacing: CGFloat {
        switch AppLanguage.current {
        case .simplifiedChinese, .traditionalChinese, .japanese, .german: 6
        case .english, .korean: 0
        }
    }

    private var usesReflowedLayout: Bool {
        dynamicTypeSize == .xLarge ||
            dynamicTypeSize == .xxLarge ||
            dynamicTypeSize == .xxxLarge ||
            dynamicTypeSize.isAccessibilitySize
    }

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _page = State(initialValue: Self.initialPageFromLaunchArguments())
    }

    var body: some View {
        ZStack {
            Group {
                if page == .entry {
                    OnboardingEntryView(onFinish: finishOnboarding, motionPhase: motionPhase)
                } else if !usesReflowedLayout {
                    introductionPages.ignoresSafeArea()
                } else {
                    introductionPages
                }
            }
            .id(page)
            .transition(pageTransition)
        }
        .modifier(HiddenStatusBarModifier())
        .task(id: page) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            showPageContentIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                showPageContentIfNeeded()
            }
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .move(edge: isMovingForward ? .trailing : .leading),
            removal: .move(edge: isMovingForward ? .leading : .trailing)
        )
    }

    private var introductionPages: some View {
        // Capture this page before the geometry closure is retained by a move
        // transition; the departing page must keep its own artwork and copy.
        let content = currentPage
        let reflowedContent = reflowedOnboardingLayout
        let background = pageBackgroundColor
        let reflows = usesReflowedLayout

        return GeometryReader { geometry in
            let scale = min(geometry.size.width / canvasSize.width, geometry.size.height / canvasSize.height)
            let fixedCanvas = content
                .frame(width: canvasSize.width, height: canvasSize.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(
                    width: canvasSize.width * scale,
                    height: canvasSize.height * scale,
                    alignment: .topLeading
                )

            let canvas = ZStack {
                background
                    .ignoresSafeArea()

                if reflows {
                    reflowedContent
                } else {
                    fixedCanvas
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())

            Group {
                if reflows {
                    canvas.simultaneousGesture(pageSwipeGesture)
                } else {
                    canvas.gesture(pageSwipeGesture)
                }
            }
        }
        .background(background)
    }

    @ViewBuilder
    private var currentPage: some View {
        switch page {
        case .intro:
            introPage
        case .research:
            researchPage
        case .brand:
            brandPage
        case .grid:
            gridPage
        case .pace:
            pacePage
        case .entry:
            EmptyView()
        }
    }

    private var reflowedOnboardingLayout: some View {
        VStack(spacing: 10) {
            ScrollView(showsIndicators: false) {
                reflowedPageContent
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 600)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.top, 12)
        .frame(maxWidth: 640, maxHeight: .infinity)
    }

    @ViewBuilder
    private var reflowedPageContent: some View {
        VStack(spacing: 24) {
            switch page {
            case .intro:
                OnboardingIntroIslandView()
                    .onboardingPageMotion(motionPhase, role: .artwork)
                    .frame(maxWidth: 340 * introArtworkScale, maxHeight: 370 * introArtworkScale)
                    .accessibilityHidden(true)
                Text(L10n.onboardingMadeForADHDBrains)
                    .font(.custom("Schoolbell-Regular", size: 18 * introArtworkScale, relativeTo: .body))
                    .foregroundStyle(secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .onboardingPageMotion(motionPhase, role: .supporting)
                Text(L10n.onboardingIntroHeadline)
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(primaryTextColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($accessibilityFocusedPage, equals: page)
                    .onboardingPageMotion(motionPhase, role: .heading)
                Text("BingoGame")
                    .font(.custom("ArchivoBlack-Regular", size: 44, relativeTo: .largeTitle))
                    .foregroundStyle(Color(hex: "E1AD80"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .shadow(color: .white, radius: 0, x: -2, y: -2)
                    .shadow(color: .white, radius: 0, x: 2, y: 2)
                    .onboardingPageMotion(motionPhase, role: .brand)
                primaryButton(title: L10n.onboardingGetStarted) {
                    moveToNextPage()
                }

            case .research:
                reflowedSupportingText(researchContinuousHeadline, size: 24)
                Text(L10n.onboardingResearchBody)
                    .appDynamicFont(size: 38, weight: .black, design: .rounded)
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(researchLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($accessibilityFocusedPage, equals: page)
                    .onboardingPageMotion(motionPhase, role: .heading)
                OnboardingResearchIllustrationView()
                    .onboardingPageMotion(motionPhase, role: .artwork)
                    .frame(maxWidth: 300, maxHeight: 300)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                primaryButton(title: L10n.onboardingNext) {
                    moveToNextPage()
                }

            case .brand:
                OnboardingBrandPortalView()
                    .onboardingPageMotion(motionPhase, role: .artwork)
                    .frame(maxWidth: 360, maxHeight: 420)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: brandContentVerticalOffset)
                    .accessibilityHidden(true)
                Text(L10n.onboardingBrandHeadline.replacingOccurrences(of: "\n", with: " "))
                    .font(AppLanguage.current == .english
                        ? .custom("ArchivoBlack-Regular", size: 36, relativeTo: .largeTitle)
                        : .largeTitle.weight(.black))
                    .foregroundStyle(primaryTextColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: brandContentVerticalOffset)
                    .padding(.bottom, brandContentVerticalOffset)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($accessibilityFocusedPage, equals: page)
                    .onboardingPageMotion(motionPhase, role: .heading)
                logoText(
                    "Bingodays",
                    colors: [Color(hex: "E8BD95"), Color(hex: "D3A375")],
                    size: brandDynamicFontSize
                )
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Bingodays")
                primaryButton(title: L10n.onboardingNext) {
                    moveToNextPage()
                }

            case .grid:
                OnboardingTaskBoardIllustration()
                    .onboardingPageMotion(motionPhase, role: .artwork)
                    .frame(maxWidth: 360)
                    .padding(.leading, 36)
                    .accessibilityHidden(true)
                reflowedHeading(L10n.onboardingGridHeadline, size: 36)
                primaryButton(title: L10n.onboardingNext) {
                    moveToNextPage()
                }

            case .pace:
                reflowedHeading(L10n.onboardingPaceHeadline, size: 36)
                OnboardingDJIllustrationView()
                    .onboardingPageMotion(motionPhase, role: .artwork)
                    .frame(maxWidth: 360, maxHeight: 420)
                    .accessibilityHidden(true)
                reflowedSupportingText(L10n.onboardingBestMode, size: 20)
                primaryButton(title: L10n.onboardingNext) {
                    moveToNextPage()
                }

            case .entry:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func reflowedHeading(_ text: String, size: CGFloat) -> some View {
        Text(text.replacingOccurrences(of: "\n", with: " "))
            .appDynamicFont(size: size, weight: .heavy, design: .rounded)
            .foregroundStyle(primaryTextColor)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($accessibilityFocusedPage, equals: page)
            .onboardingPageMotion(motionPhase, role: .heading)
    }

    private func reflowedSupportingText(_ text: String, size: CGFloat) -> some View {
        Text(text.replacingOccurrences(of: "\n", with: " "))
            .appDynamicFont(size: size, weight: .medium, design: .rounded)
            .foregroundStyle(secondaryTextColor)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .onboardingPageMotion(motionPhase, role: .supporting)
    }

    private var introArtwork: some View {
        ZStack(alignment: .topLeading) {
            OnboardingIntroIslandView()
                .onboardingPageMotion(motionPhase, role: .artwork)
                .figmaFrame(x: -63, y: -3, width: 386, height: 408)
                .accessibilityHidden(true)

            Text(L10n.onboardingMadeForADHDBrains)
                .font(OnboardingFonts.schoolbell(size: 18))
                .foregroundStyle(secondaryTextColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .onboardingPageMotion(motionPhase, role: .supporting)
                .figmaFrame(x: 239, y: 85, width: 146, height: 66, alignment: .topLeading)
        }
        .frame(width: canvasSize.width, height: 408, alignment: .topLeading)
        .scaleEffect(introArtworkScale, anchor: .bottom)
    }

    private var introPage: some View {
        ZStack(alignment: .topLeading) {
            pageBackgroundColor
            introArtwork

            headlineText(
                L10n.onboardingIntroHeadline,
                size: 60,
                lines: usesChineseIntroHeadline ? 2 : 3,
                alignment: .leading
            )
            .figmaFrame(
                x: 26,
                y: introHeadlineY,
                width: 341,
                height: usesChineseIntroHeadline ? 130 : 195,
                alignment: .topLeading
            )

            gradientOutlinedWord(
                "BingoGame",
                font: OnboardingFonts.uiArchivoBlack(size: 50),
                topColor: "E1AD80",
                bottomColor: "E1AD80",
                outlineWidth: 4.61,
                alignment: .left
            )
                .shadow(color: Color(hex: "B48B65").opacity(0.18), radius: 3, x: 0, y: 2)
                .figmaFrame(x: 26, y: usesChineseIntroHeadline ? 558 : 598, width: 341, height: 64)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("BingoGame")

            primaryButton(title: L10n.onboardingGetStarted) {
                moveToNextPage()
            }
            .figmaFrame(x: 82, y: 704, width: 207, height: 52)
        }
        .clipped()
    }

    private var researchPage: some View {
        ZStack(alignment: .topLeading) {
            pageBackgroundColor

            Text(researchContinuousHeadline)
                .font(OnboardingFonts.supporting(size: 24, weight: 600))
                .foregroundStyle(secondaryTextColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .onboardingPageMotion(motionPhase, role: .supporting)
                .figmaFrame(x: 26, y: 160, width: 341, height: 66, alignment: .topLeading)

            OnboardingResearchIllustrationView()
                .onboardingPageMotion(motionPhase, role: .artwork)
                .figmaFrame(x: 113, y: 385, width: 370, height: 370)
                .accessibilityHidden(true)

            // A single text block keeps the same font size on every wrapped line.
            Text(L10n.onboardingResearchBody)
                .font(OnboardingFonts.headline(size: 38))
                .foregroundStyle(.black)
                .multilineTextAlignment(.leading)
                .lineSpacing(researchLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .onboardingPageMotion(motionPhase, role: .heading)
                .figmaFrame(x: 24, y: 208, width: researchStatementWidth, height: 420, alignment: .topLeading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocusedPage, equals: page)

            primaryButton(title: L10n.onboardingNext) {
                moveToNextPage()
            }
            .figmaFrame(x: 93, y: 752, width: 207, height: 52)
        }
        .clipped()
    }

    private var brandPage: some View {
        ZStack(alignment: .topLeading) {
            pageBackgroundColor

            OnboardingBrandPortalView()
                .onboardingPageMotion(motionPhase, role: .artwork)
                .figmaFrame(x: 96, y: -35 + brandContentVerticalOffset, width: 318, height: 476)
                .accessibilityHidden(true)

            headlineText(
                L10n.onboardingBrandHeadline,
                size: 48,
                lines: 3,
                alignment: .leading
            )
            .figmaFrame(x: 20, y: 424 + brandContentVerticalOffset, width: 341, height: 156, alignment: .topLeading)

            gradientOutlinedWord(
                "Bingodays",
                font: OnboardingFonts.uiArchivoBlack(size: 48),
                topColor: "E8BD95",
                bottomColor: "D3A375",
                outlineWidth: 4.8,
                alignment: .left
            )
                .shadow(color: Color(hex: "B48B65").opacity(0.2), radius: 3, x: 0, y: 3)
                .figmaFrame(x: 20, y: 590, width: 341, height: 64)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Bingodays")

            primaryButton(title: L10n.onboardingNext) {
                moveToNextPage()
            }
            .figmaFrame(x: 92, y: 725, width: 208, height: 52)
        }
        .clipped()
    }

    private var gridPage: some View {
        ZStack(alignment: .topLeading) {
            pageBackgroundColor

            OnboardingTaskBoardIllustration()
                .onboardingPageMotion(motionPhase, role: .artwork)
                .figmaFrame(x: 78, y: 78, width: 416, height: 416)
                .accessibilityHidden(true)

            headlineText(
                L10n.onboardingGridHeadline,
                size: 48,
                lines: 3,
                alignment: .trailing
            )
            .figmaFrame(x: 90, y: 508, width: 297, height: 160, alignment: .topTrailing)

            primaryButton(title: L10n.onboardingNext) {
                moveToNextPage()
            }
            .figmaFrame(x: 93, y: 725, width: 207, height: 52)
        }
        .clipped()
    }

    private var pacePage: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: "F4F4F4")

            headlineText(
                L10n.onboardingPaceHeadline,
                size: 55,
                lines: 4,
                alignment: .leading
            )
            .figmaFrame(x: 28, y: 62, width: 342, height: 260, alignment: .leading)

            OnboardingDJIllustrationView()
                .onboardingPageMotion(motionPhase, role: .artwork)
                .figmaFrame(x: 39, y: 245, width: 348, height: 518)
                .accessibilityHidden(true)

            outlinedWord(
                L10n.onboardingBestMode,
                font: OnboardingFonts.uiSchoolbell(size: 24),
                fillColor: UIColor(Color(hex: "828282")),
                outlineWidth: 2,
                alignment: .right
            )
                .figmaFrame(x: 277, y: 405, width: 103, height: 36, alignment: .trailing)

            primaryButton(title: L10n.onboardingNext) {
                moveToNextPage()
            }
            .figmaFrame(x: 93, y: 704, width: 207, height: 52)
        }
    }

    private var onboardingStatusBar: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("9:41")
                .font(.appSystem(size: 15, weight: .semibold))
                .foregroundStyle(.black)

            Spacer()

            Image(systemName: "cellularbars")
                .font(.appSystem(size: 13, weight: .semibold))
                .foregroundStyle(.black)

            Image(systemName: "wifi")
                .font(.appSystem(size: 13, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.leading, 6)

            batteryShape
                .padding(.leading, 6)
        }
        .padding(.horizontal, 25)
        .padding(.top, 18)
    }

    private var batteryShape: some View {
        HStack(spacing: 2) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.6, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    .frame(width: 22, height: 11.333)

                RoundedRectangle(cornerRadius: 1.333, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 18, height: 7.333)
                    .padding(.leading, 2)
            }

            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.4))
                .frame(width: 1.328, height: 4)
        }
    }

    private func primaryButton(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if (page == .intro || page == .brand) && usesReflowedLayout {
                    Text(title)
                        .font(.title3.weight(.semibold))
                } else {
                    Text(title)
                        .appDynamicFont(size: 20, weight: .semibold, design: .rounded)
                }
            }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, usesReflowedLayout ? 12 : 0)
                .frame(minHeight: usesReflowedLayout ? 64 : 52)
                .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(page == .brand ? Color(hex: "40270F") : buttonColor)
        )
        .onboardingPageMotion(motionPhase, role: .action)
    }

    private func gradientOutlinedWord(
        _ text: String,
        font: UIFont,
        topColor: String,
        bottomColor: String,
        outlineWidth: CGFloat,
        alignment: NSTextAlignment
    ) -> some View {
        FigmaWordView(
            text: text,
            font: font,
            fillColors: [UIColor(hex: topColor), UIColor(hex: bottomColor)],
            fillColor: nil,
            strokeColor: .white,
            outlineWidth: outlineWidth,
            alignment: alignment
        )
        .onboardingPageMotion(motionPhase, role: .brand)
    }

    private func outlinedWord(
        _ text: String,
        font: UIFont,
        fillColor: UIColor,
        outlineWidth: CGFloat,
        alignment: NSTextAlignment
    ) -> some View {
        FigmaWordView(
            text: text,
            font: font,
            fillColors: nil,
            fillColor: fillColor,
            strokeColor: .white,
            outlineWidth: outlineWidth,
            alignment: alignment
        )
        .onboardingPageMotion(motionPhase, role: .supporting)
    }

    private func logoText(_ text: String, colors: [Color], size: CGFloat) -> some View {
        let outlineOffsets: [CGSize] = [
            CGSize(width: -2.2, height: 0),
            CGSize(width: 2.2, height: 0),
            CGSize(width: 0, height: -2.2),
            CGSize(width: 0, height: 2.2),
            CGSize(width: -1.8, height: -1.8),
            CGSize(width: 1.8, height: -1.8),
            CGSize(width: -1.8, height: 1.8),
            CGSize(width: 1.8, height: 1.8),
        ]

        return ZStack {
            ForEach(Array(outlineOffsets.enumerated()), id: \.offset) { _, offset in
                Text(text)
                    .font(OnboardingFonts.archivoBlack(size: size))
                    .foregroundStyle(.white)
                    .offset(x: offset.width, y: offset.height)
            }

            Text(text)
                .font(OnboardingFonts.archivoBlack(size: size))
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(hex: "B48B65").opacity(0.2), radius: 10, x: 0, y: 4)
        }
        .onboardingPageMotion(motionPhase, role: .brand)
    }

    private func headlineText(_ text: String, size: CGFloat, lines: Int, alignment: TextAlignment) -> some View {
        Text(text)
            .font(OnboardingFonts.headline(size: size))
            .foregroundStyle(primaryTextColor)
            .multilineTextAlignment(alignment)
            .lineLimit(lines)
            .minimumScaleFactor(0.62)
            .allowsTightening(true)
            .onboardingPageMotion(motionPhase, role: .heading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($accessibilityFocusedPage, equals: page)
    }

    private func emoji(_ value: String, size: CGFloat) -> some View {
        Text(value)
            .font(.appSystem(size: size))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityHidden(true)
    }

    private func progressBar(fill: Color) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(fill)
            .frame(width: 70, height: 6)
    }

    private func moveToNextPage() {
        guard let currentIndex = Page.allCases.firstIndex(of: page) else { return }
        let nextIndex = min(currentIndex + 1, Page.allCases.count - 1)
        requestPage(Page.allCases[nextIndex])
    }

    private func moveToPreviousPage() {
        guard let currentIndex = Page.allCases.firstIndex(of: page) else { return }
        let previousIndex = max(currentIndex - 1, 0)
        guard previousIndex != currentIndex else { return }

        requestPage(Page.allCases[previousIndex])
    }

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }

                if horizontal <= -pageSwipeThreshold {
                    moveToNextPage()
                } else if horizontal >= pageSwipeThreshold {
                    moveToPreviousPage()
                }
            }
    }

    private func showPageContentIfNeeded() {
        guard scenePhase == .active, motionPhase == .hidden else { return }
        motionPhase = .visible
        focusHeadingIfVoiceOverIsRunning(for: page)
    }

    private func requestPage(_ target: Page) {
        guard !isFinishing, target != page else { return }
        isMovingForward = target.rawValue > page.rawValue
        // Native move transitions retain the departing page while the next one
        // slides in, keeping the viewport covered without opacity changes.
        withAnimation(reduceMotion ? nil : OnboardingPageMotionPhase.animation(duration: 0.32)) {
            page = target
            motionPhase = .hidden
        }
    }

    private func finishOnboarding() {
        guard !isFinishing else { return }
        isFinishing = true
        withAnimation(
            reduceMotion ? nil : OnboardingPageMotionPhase.animation(duration: OnboardingPageMotionPhase.exitDuration),
            completionCriteria: .removed
        ) {
            motionPhase = .exiting
        } completion: {
            onFinish()
        }
    }

    private func focusHeadingIfVoiceOverIsRunning(for targetPage: Page) {
        guard UIAccessibility.isVoiceOverRunning else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard page == targetPage, motionPhase == .visible else { return }
            accessibilityFocusedPage = targetPage
        }
    }

    private static func initialPageFromLaunchArguments() -> Page {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments

        guard let index = arguments.firstIndex(of: "-OnboardingPage"),
              index + 1 < arguments.count else {
            return .intro
        }

        let rawValue = arguments[index + 1].lowercased()
        switch rawValue {
        case "1", "intro":
            return .intro
        case "2", "research":
            return .research
        case "3", "brand":
            return .brand
        case "4", "grid":
            return .grid
        case "5", "pace":
            return .pace
        case "6", "entry", "rewards":
            return .entry
        default:
            return .intro
        }
        #else
        return .intro
        #endif
    }
}

private struct OnboardingTaskBoardIllustration: View {
    private let symbols = ["🏃", "🍚", "", "🏊", "🛀", "", "🧘", "💻", ""]
    private let symbolSizes: [CGFloat] = [35.15, 38.842, 0, 42.961, 38.842, 0, 38.842, 32.912, 0]

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 338
            let cellSize = (geometry.size.width - 58 * scale) / 3

            VStack(spacing: 14 * scale) {
                ForEach(0..<3) { row in
                    HStack(spacing: 14 * scale) {
                        ForEach(0..<3) { column in
                            let index = row * 3 + column
                            RoundedRectangle(cornerRadius: 11.5 * scale)
                                .fill(.white)
                                .frame(width: cellSize, height: cellSize)
                                .overlay {
                                    if !symbols[index].isEmpty {
                                        Text(symbols[index])
                                            .font(.system(size: symbolSizes[index] * scale))
                                    }
                                }
                        }
                    }
                }
            }
            .padding(15 * scale)
            .background(RoundedRectangle(cornerRadius: 25 * scale).fill(Color(hex: "E9E2DC")))
            .overlay(alignment: .topLeading) {
                OnboardingCoffeeStickerView(scale: scale)
                    .position(x: -16 * scale, y: 67 * scale)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct HiddenStatusBarModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content.toolbarVisibility(.hidden, for: .statusBar)
        } else {
            content.statusBar(hidden: true)
        }
    }
}


enum OnboardingFonts {
    private static var usesLocalizedSystemFonts: Bool {
        switch AppLanguage.current {
        case .simplifiedChinese, .traditionalChinese, .japanese, .korean, .german:
            return true
        case .english:
            return false
        }
    }

    static func archivoBlack(size: CGFloat) -> Font {
        let font = uiArchivoBlack(size: size)
        return Font(font as CTFont)
    }

    static func schoolbell(size: CGFloat) -> Font {
        let font = uiSchoolbell(size: size)
        return Font(font as CTFont)
    }

    static func outfit(size: CGFloat, weight: CGFloat) -> Font {
        let font = outfitFont(size: size, weight: weight)
        return Font(font as CTFont)
    }

    static func headline(size: CGFloat) -> Font {
        if usesLocalizedSystemFonts {
            let uiFont = localizedUIFont(size: size * 0.9, weight: .bold)
            return Font(uiFont as CTFont)
        }

        return archivoBlack(size: size)
    }

    static func supporting(size: CGFloat, weight: CGFloat) -> Font {
        if usesLocalizedSystemFonts {
            let uiFont = localizedUIFont(size: size, weight: uiWeight(from: weight))
            return Font(uiFont as CTFont)
        }

        return outfit(size: size, weight: weight)
    }

    static func button(size: CGFloat, weight: CGFloat) -> Font {
        if usesLocalizedSystemFonts {
            let uiFont = localizedUIFont(size: size, weight: .semibold)
            return Font(uiFont as CTFont)
        }

        return outfit(size: size, weight: weight)
    }

    static func uiArchivoBlack(size: CGFloat) -> UIFont {
        UIFont(name: "Archivo Black", size: size)
            ?? UIFont(name: "ArchivoBlack-Regular", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .black)
    }

    static func uiSchoolbell(size: CGFloat) -> UIFont {
        UIFont(name: "Schoolbell", size: size)
            ?? UIFont(name: "Schoolbell-Regular", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .regular)
    }

    private static func outfitFont(size: CGFloat, weight: CGFloat) -> UIFont {
        let baseFont = UIFont(name: "Outfit", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .regular)

        let axisTag = NSNumber(value: fourCharCode(from: "wght"))
        let descriptor = baseFont.fontDescriptor.addingAttributes([
            kCTFontVariationAttribute as UIFontDescriptor.AttributeName: [
                axisTag: weight
            ]
        ])

        return UIFont(descriptor: descriptor, size: size)
    }

    private static func uiWeight(from weight: CGFloat) -> Font.Weight {
        switch weight {
        case ..<450:
            return .regular
        case ..<550:
            return .medium
        case ..<650:
            return .semibold
        default:
            return .bold
        }
    }

    private static func localizedUIFont(size: CGFloat, weight: Font.Weight) -> UIFont {
        let uiWeight = uiFontWeight(from: weight)

        switch AppLanguage.current {
        case .simplifiedChinese:
            return UIFont(name: pingFangSCName(for: weight), size: size)
                ?? UIFont.systemFont(ofSize: size, weight: uiWeight)
        case .traditionalChinese:
            return UIFont(name: pingFangTCName(for: weight), size: size)
                ?? UIFont.systemFont(ofSize: size, weight: uiWeight)
        case .japanese:
            return UIFont(name: hiraginoSansName(for: weight), size: size)
                ?? UIFont.systemFont(ofSize: size, weight: uiWeight)
        case .korean, .german:
            return UIFont.systemFont(ofSize: size, weight: uiWeight)
        case .english:
            let baseFont = UIFont(name: "Outfit", size: size)
            if let descriptor = baseFont?.fontDescriptor.addingAttributes([
                .traits: [UIFontDescriptor.TraitKey.weight: uiWeight]
            ]) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return baseFont ?? UIFont.systemFont(ofSize: size, weight: uiWeight)
        }
    }

    private static func uiFontWeight(from weight: Font.Weight) -> UIFont.Weight {
        if weight == .ultraLight {
            return .ultraLight
        }
        if weight == .thin {
            return .thin
        }
        if weight == .light {
            return .light
        }
        if weight == .regular {
            return .regular
        }
        if weight == .medium {
            return .medium
        }
        if weight == .semibold {
            return .semibold
        }
        if weight == .bold {
            return .bold
        }
        if weight == .heavy {
            return .heavy
        }
        if weight == .black {
            return .black
        }

        return .regular
    }

    private static func pingFangSCName(for weight: Font.Weight) -> String {
        if weight == .bold || weight == .heavy || weight == .black {
            return "PingFangSC-Semibold"
        }
        if weight == .semibold {
            return "PingFangSC-Semibold"
        }
        if weight == .medium {
            return "PingFangSC-Medium"
        }

        return "PingFangSC-Regular"
    }

    private static func pingFangTCName(for weight: Font.Weight) -> String {
        if weight == .bold || weight == .heavy || weight == .black {
            return "PingFangTC-Semibold"
        }
        if weight == .semibold {
            return "PingFangTC-Semibold"
        }
        if weight == .medium {
            return "PingFangTC-Medium"
        }

        return "PingFangTC-Regular"
    }

    private static func hiraginoSansName(for weight: Font.Weight) -> String {
        if weight == .bold || weight == .heavy || weight == .black {
            return "HiraginoSans-W6"
        }
        if weight == .semibold {
            return "HiraginoSans-W6"
        }
        if weight == .medium {
            return "HiraginoSans-W5"
        }

        return "HiraginoSans-W3"
    }

    private static func fourCharCode(from string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) + UInt32($1) }
    }
}

struct FigmaWordView: UIViewRepresentable {
    let text: String
    let font: UIFont
    let fillColors: [UIColor]?
    let fillColor: UIColor?
    let strokeColor: UIColor
    let outlineWidth: CGFloat
    let alignment: NSTextAlignment

    func makeUIView(context: Context) -> FigmaWordRenderView {
        let view = FigmaWordRenderView()
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ uiView: FigmaWordRenderView, context: Context) {
        uiView.text = text
        uiView.font = font
        uiView.fillColors = fillColors
        uiView.fillColor = fillColor
        uiView.strokeColor = strokeColor
        uiView.outlineWidth = outlineWidth
        uiView.alignment = alignment
        uiView.setNeedsDisplay()
    }
}

final class FigmaWordRenderView: UIView {
    var text = ""
    var font = UIFont.systemFont(ofSize: 17, weight: .bold)
    var fillColors: [UIColor]?
    var fillColor: UIColor?
    var strokeColor = UIColor.white
    var outlineWidth: CGFloat = 0
    var alignment: NSTextAlignment = .left

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .redraw
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard !text.isEmpty, rect.width > 0, rect.height > 0 else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
        ]

        let nsText = text as NSString
        let measured = nsText.boundingRect(
            with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: baseAttributes,
            context: nil
        )

        let drawRect = CGRect(
            x: 0,
            y: floor((rect.height - measured.height) / 2),
            width: rect.width,
            height: ceil(measured.height)
        )

        let strokePercent = (outlineWidth / max(font.pointSize, 1)) * 100
        let strokeAttributes = baseAttributes.merging([
            .strokeColor: strokeColor,
            .strokeWidth: strokePercent,
            .foregroundColor: UIColor.clear,
        ]) { _, new in new }

        nsText.draw(in: drawRect, withAttributes: strokeAttributes)

        let renderer = UIGraphicsImageRenderer(size: rect.size)
        let fillImage = renderer.image { renderContext in
            let fillAttributes = baseAttributes.merging([
                .foregroundColor: UIColor.white,
            ]) { _, new in new }

            nsText.draw(in: drawRect, withAttributes: fillAttributes)
            renderContext.cgContext.setBlendMode(.sourceIn)

            if let fillColors, fillColors.count >= 2 {
                let cgColors = fillColors.map(\.cgColor) as CFArray
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let locations: [CGFloat]? = fillColors.count == 2 ? [0, 1] : nil
                if let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: locations) {
                    renderContext.cgContext.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: 0, y: 0),
                        end: CGPoint(x: 0, y: rect.height),
                        options: []
                    )
                }
            } else {
                (fillColor ?? .black).setFill()
                renderContext.cgContext.fill(rect)
            }
        }

        fillImage.draw(in: rect)
    }
}

extension View {
    func figmaFrame(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        alignment: Alignment = .center
    ) -> some View {
        frame(width: width, height: height, alignment: alignment)
            .position(x: x + (width / 2), y: y + (height / 2))
    }
}
