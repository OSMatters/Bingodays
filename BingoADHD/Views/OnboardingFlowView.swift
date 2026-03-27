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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var accountSession = AccountSession.shared
    @StateObject private var subscriptionManager = SubscriptionManager()
    @State private var shouldShowOnboarding = OnboardingStateResolver.shouldPresentOnboarding()

    var body: some View {
        Group {
            if shouldShowOnboarding {
                OnboardingFlowView(
                    onFinish: {
                        UserDefaults.standard.set(true, forKey: AppSettings.hasSeenOnboardingKey)
                        shouldShowOnboarding = false
                    }
                )
            } else {
                ContentView()
            }
        }
        .environmentObject(accountSession)
        .environmentObject(subscriptionManager)
        .onAppear {
            shouldShowOnboarding = OnboardingStateResolver.shouldPresentOnboarding()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            shouldShowOnboarding = OnboardingStateResolver.shouldPresentOnboarding()
        }
        .onChange(of: scenePhase) { _, newValue in
            accountSession.handleScenePhaseChange(newValue)
        }
    }
}

struct OnboardingFlowView: View {
    private enum Page: Int, CaseIterable {
        case intro
        case research
        case brand
        case grid
        case pace
        case rewards
    }

    private let canvasSize = CGSize(width: 393, height: 852)
    private let backgroundColor = Color(hex: "F4EFE9")
    private let primaryTextColor = Color(hex: "17202C")
    private let buttonColor = Color(hex: "3F270F")
    private let secondaryTextColor = Color(hex: "828282")
    private let onboardingStepColor = Color(hex: "D3A375")

    @State private var page: Page
    @State private var introEyesWiggle = false
    @State private var introBrainWiggle = false
    @State private var introEyesEntryOffset: CGFloat = -96
    @State private var introBrainEntryOffset: CGFloat = 96
    @State private var textEntranceVisible = false
    @State private var researchLaptopWiggle = false
    @State private var researchScribbleWiggle = false
    @State private var rewardsFacesWiggle = false

    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _page = State(initialValue: Self.initialPageFromLaunchArguments())
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / canvasSize.width, geometry.size.height / canvasSize.height)

            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                currentPage
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(
                        width: canvasSize.width * scale,
                        height: canvasSize.height * scale,
                        alignment: .topLeading
                    )

                if page != .intro {
                    onboardingStepsBar
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(
                            width: canvasSize.width * scale,
                            height: canvasSize.height * scale,
                            alignment: .topLeading
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .statusBar(hidden: true)
        .background(backgroundColor)
        .onAppear {
            triggerTextEntranceAnimation()
        }
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
        case .rewards:
            rewardsPage
        }
    }

    private var introPage: some View {
        ZStack(alignment: .topLeading) {
            backgroundColor

            ZStack {
                Image("Onboarding1ImgEye")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 104.266, height: 104.266)
                    .rotationEffect(.degrees(-157.45))
                    .scaleEffect(x: 1, y: -1)
                    .offset(x: introEyesEntryOffset + (introEyesWiggle ? 3 : -3))
                    .animation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true), value: introEyesWiggle)
            }
            .figmaFrame(x: 14, y: 16, width: 136.283, height: 136.283)

            Image("Onboarding1Ellipse4")
                .resizable()
                .interpolation(.high)
                .frame(width: 186, height: 186)
                .offset(x: introBrainEntryOffset + (introBrainWiggle ? -2.6 : 2.6))
                .animation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true), value: introBrainWiggle)
                .figmaFrame(x: 156, y: 67, width: 186, height: 186)

            Image("Onboarding1Image14")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 119.48, height: 39.57)
                .rotationEffect(Angle(degrees: 5.72))
                .shadow(color: Color(hex: "AE2353").opacity(0.15), radius: 8, x: 0, y: 4)
                .figmaFrame(x: 107.904, y: 206.908, width: 122.829, height: 51.281)

            DoodleArrowView()
                .stroke(Color(hex: "C9C9C9"), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                .figmaFrame(x: 71.5, y: 263, width: 89, height: 48)

            Text(L10n.onboardingMadeForADHDBrains)
                .font(OnboardingFonts.schoolbell(size: 18))
                .foregroundStyle(secondaryTextColor)
                .onboardingTextEntrance(textEntranceVisible)
                .figmaFrame(x: 26, y: 324, width: 160, height: 25, alignment: .leading)

            headlineText(
                L10n.onboardingIntroHeadline,
                size: 60,
                lines: 2,
                alignment: .center
            )
            .figmaFrame(x: 26, y: 384, width: 341, height: 130)

            gradientOutlinedWord(
                "Bingo",
                font: OnboardingFonts.uiArchivoBlack(size: 60),
                topColor: "E8BD95",
                bottomColor: "D3A375",
                outlineWidth: 4.61,
                alignment: .center
            )
                .shadow(color: Color(hex: "B48B65").opacity(0.2), radius: 10, x: 0, y: 4)
                .shadow(color: .white.opacity(0.25), radius: 4, x: -4, y: -4)
                .figmaFrame(x: 103, y: 522, width: 187, height: 65)

            primaryButton(title: L10n.onboardingGetStarted) {
                moveToNextPage()
            }
            .figmaFrame(x: 93, y: 657, width: 207, height: 52)
        }
        .onAppear {
            introEyesEntryOffset = -96
            introBrainEntryOffset = 96
            introEyesWiggle = true
            introBrainWiggle = true

            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                introEyesEntryOffset = 0
                introBrainEntryOffset = 0
            }
        }
    }

    private var researchPage: some View {
        ZStack(alignment: .topLeading) {
            backgroundColor

            Image("Onboarding2Image27")
                .resizable()
                .interpolation(.high)
                .frame(width: 297, height: 297)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .offset(x: researchLaptopWiggle ? 3 : -3)
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: researchLaptopWiggle)
                .figmaFrame(x: 41, y: 99, width: 297, height: 297)

            Image("Onboarding2Image20")
                .resizable()
                .interpolation(.high)
                .frame(width: 80, height: 80)
                .opacity(0.9)
                .offset(x: researchScribbleWiggle ? -2.4 : 2.4)
                .animation(.easeInOut(duration: 1.65).repeatForever(autoreverses: true), value: researchScribbleWiggle)
                .figmaFrame(x: 239, y: 59, width: 80, height: 80)

            headlineText(
                L10n.onboardingResearchHeadline,
                size: 60,
                lines: 4,
                alignment: .leading
            )
            .figmaFrame(x: 41, y: 377, width: 342, height: 260, alignment: .leading)

            Text(L10n.onboardingResearchBody)
                .font(OnboardingFonts.supporting(size: 21, weight: 500))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .onboardingTextEntrance(textEntranceVisible)
                .figmaFrame(x: 42, y: 619, width: 341, height: 80, alignment: .leading)

            primaryButton(title: L10n.onboardingNext) {
                moveToNextPage()
            }
            .figmaFrame(x: 93, y: 725, width: 207, height: 52)
        }
        .onAppear {
            researchLaptopWiggle = true
            researchScribbleWiggle = true
        }
    }

    private var brandPage: some View {
        ZStack(alignment: .topLeading) {
            backgroundColor

            headlineText(
                L10n.onboardingBrandHeadline,
                size: 60,
                lines: 3,
                alignment: .center
            )
            .figmaFrame(x: 26, y: 127, width: 341, height: 195)

            gradientOutlinedWord(
                "Bingodays",
                font: OnboardingFonts.uiArchivoBlack(size: 60),
                topColor: "E8BD95",
                bottomColor: "D3A375",
                outlineWidth: 6,
                alignment: .left
            )
                .shadow(color: Color(hex: "B48B65").opacity(0.2), radius: 10, x: 0, y: 4)
                .shadow(color: .white.opacity(0.25), radius: 4, x: -4, y: -4)
                .figmaFrame(x: 28, y: 331, width: 341, height: 65)

            gradientOutlinedWord(
                "Bingodays",
                font: OnboardingFonts.uiArchivoBlack(size: 60),
                topColor: "308CE8",
                bottomColor: "9CC8F4",
                outlineWidth: 6,
                alignment: .left
            )
                .shadow(color: Color(hex: "B48B65").opacity(0.2), radius: 10, x: 0, y: 4)
                .shadow(color: .white.opacity(0.25), radius: 4, x: -4, y: -4)
                .figmaFrame(x: 28, y: 415, width: 341, height: 65)

            gradientOutlinedWord(
                "Bingodays",
                font: OnboardingFonts.uiArchivoBlack(size: 60),
                topColor: "3DC4BB",
                bottomColor: "BAF1DA",
                outlineWidth: 6,
                alignment: .left
            )
                .shadow(color: Color(hex: "B48B65").opacity(0.2), radius: 10, x: 0, y: 4)
                .shadow(color: .white.opacity(0.25), radius: 4, x: -4, y: -4)
                .figmaFrame(x: 28, y: 499, width: 341, height: 65)

            gradientOutlinedWord(
                "Bingodays",
                font: OnboardingFonts.uiArchivoBlack(size: 60),
                topColor: "FFA17C",
                bottomColor: "FEC9B4",
                outlineWidth: 6,
                alignment: .left
            )
                .shadow(color: Color(hex: "B48B65").opacity(0.2), radius: 10, x: 0, y: 4)
                .shadow(color: .white.opacity(0.25), radius: 4, x: -4, y: -4)
                .figmaFrame(x: 28, y: 583, width: 341, height: 65)

            primaryButton(title: L10n.onboardingNext) {
                moveToNextPage()
            }
            .figmaFrame(x: 93, y: 725, width: 207, height: 52)
        }
    }

    private var gridPage: some View {
        ZStack(alignment: .topLeading) {
            backgroundColor

            Group {
                Image("Onboarding4Frame111")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 338, height: 338)
                    .figmaFrame(x: -72, y: 73, width: 338, height: 338)

                emoji("🍚", size: 38.842)
                    .figmaFrame(x: 73, y: 107, width: 39.781, height: 51.716)
                emoji("🏃", size: 35.15)
                    .figmaFrame(x: 190, y: 111, width: 36, height: 46.8)
                emoji("🛀", size: 38.842)
                    .figmaFrame(x: 77, y: 213, width: 39.781, height: 51.716)
                emoji("🏊", size: 42.961)
                    .figmaFrame(x: 182, y: 210, width: 44, height: 57.2)
                emoji("💻", size: 32.912)
                    .figmaFrame(x: 80, y: 328, width: 33.708, height: 43.82)
                emoji("🧘", size: 38.842)
                    .figmaFrame(x: 182, y: 324, width: 39.781, height: 51.716)

                Image("Onboarding4Icon1")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 90.377, height: 90.377)
                    .rotationEffect(.degrees(13.72))
                    .figmaFrame(x: 26.737, y: 452.82, width: 90.377, height: 90.377)

                RoundedRectangle(cornerRadius: 47, style: .continuous)
                    .fill(Color(hex: "D6B08A"))
                    .figmaFrame(x: 203, y: 154, width: 152, height: 59)

                Text(L10n.onboardingStressFree)
                    .font(OnboardingFonts.schoolbell(size: 24))
                    .foregroundStyle(.white)
                    .onboardingTextEntrance(textEntranceVisible)
                    .figmaFrame(x: 221, y: 167, width: 113, height: 33)

                HStack(spacing: 0) {
                    eyeball()
                    eyeball()
                }
                .figmaFrame(x: 293, y: 136, width: 38, height: 31)

                Text(L10n.onboardingSimplified)
                    .font(OnboardingFonts.schoolbell(size: 24))
                    .foregroundStyle(secondaryTextColor)
                    .onboardingTextEntrance(textEntranceVisible)
                    .figmaFrame(x: 279, y: 265, width: 92.5, height: 36, alignment: .trailing)

                UnderlineHighlight()
                    .stroke(Color(hex: "FFA3DC"), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .figmaFrame(x: 280, y: 295.5, width: 91.5, height: 5.5)

                headlineText(
                    L10n.onboardingGridHeadline,
                    size: 60,
                    lines: 4,
                    alignment: .trailing
                )
                .figmaFrame(x: 33, y: 427, width: 324, height: 260, alignment: .topTrailing)

                primaryButton(title: L10n.onboardingNext) {
                    moveToNextPage()
                }
                .figmaFrame(x: 93, y: 725, width: 207, height: 52)
            }
            .offset(y: 30)
        }
    }

    private var pacePage: some View {
        ZStack(alignment: .topLeading) {
            backgroundColor

            headlineText(
                L10n.onboardingPaceHeadline,
                size: 60,
                lines: 4,
                alignment: .leading
            )
            .figmaFrame(x: 36, y: 125, width: 324, height: 260, alignment: .leading)

            Image("Onboarding5Rectangle22")
                .resizable()
                .interpolation(.high)
                .frame(width: 324, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                .figmaFrame(x: 28, y: 403, width: 324, height: 280)

            outlinedWord(
                L10n.onboardingBestMode,
                font: OnboardingFonts.uiSchoolbell(size: 24),
                fillColor: UIColor(Color(hex: "828282")),
                outlineWidth: 2,
                alignment: .right
            )
                .figmaFrame(x: 200, y: 385, width: 140, height: 40, alignment: .trailing)

            UnderlineHighlight()
                .stroke(Color(hex: "FFA3DC"), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .figmaFrame(x: 34, y: 537.5, width: 91.5, height: 5.5)

            outlinedWord(
                L10n.onboardingPersonalized,
                font: OnboardingFonts.uiSchoolbell(size: 24),
                fillColor: UIColor(Color(hex: "828282")),
                outlineWidth: 2,
                alignment: .left
            )
                .figmaFrame(x: 19, y: 666, width: 180, height: 40, alignment: .leading)

            primaryButton(title: L10n.onboardingNext) {
                moveToNextPage()
            }
            .figmaFrame(x: 93, y: 725, width: 207, height: 52)
        }
    }

    private var rewardsPage: some View {
        ZStack(alignment: .topLeading) {
            backgroundColor

            Image("Onboarding6Image32")
                .resizable()
                .interpolation(.high)
                .frame(width: 170.217, height: 170.217)
                .figmaFrame(x: -187, y: 276.199, width: 170.217, height: 170.217)

            Image("Onboarding6WinkBear")
                .resizable()
                .interpolation(.high)
                .frame(width: 178.352, height: 157)
                .offset(x: rewardsFacesWiggle ? -2.8 : 2.8)
                .animation(.easeInOut(duration: 1.85).repeatForever(autoreverses: true), value: rewardsFacesWiggle)
                .figmaFrame(x: -77, y: 111, width: 178.352, height: 157)

            Image("Onboarding6Image31")
                .resizable()
                .interpolation(.high)
                .frame(width: 170.816, height: 170.816)
                .offset(x: rewardsFacesWiggle ? 2.4 : -2.4)
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: rewardsFacesWiggle)
                .figmaFrame(x: 116.209, y: 107, width: 170.816, height: 170.816)

            Image("Onboarding6Image33")
                .resizable()
                .interpolation(.high)
                .frame(width: 172, height: 172)
                .offset(x: rewardsFacesWiggle ? -2.2 : 2.2)
                .animation(.easeInOut(duration: 2.15).repeatForever(autoreverses: true), value: rewardsFacesWiggle)
                .figmaFrame(x: 282, y: 106, width: 172, height: 172)

            Image("Onboarding6Image35")
                .resizable()
                .interpolation(.high)
                .frame(width: 169, height: 171)
                .offset(x: rewardsFacesWiggle ? 2.6 : -2.6)
                .animation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true), value: rewardsFacesWiggle)
                .figmaFrame(x: 13, y: 291, width: 169, height: 171)

            Image("Onboarding6Image30")
                .resizable()
                .interpolation(.high)
                .frame(width: 171.416, height: 171.416)
                .offset(x: rewardsFacesWiggle ? -2.5 : 2.5)
                .animation(.easeInOut(duration: 2.05).repeatForever(autoreverses: true), value: rewardsFacesWiggle)
                .figmaFrame(x: 196, y: 291, width: 171.416, height: 171.416)

            headlineText(
                L10n.onboardingRewardsHeadline,
                size: 55,
                lines: 2,
                alignment: .center
            )
            .figmaFrame(x: 20, y: 508, width: 353, height: 132, alignment: .center)

            Text(L10n.onboardingRewardsSubtitle)
                .font(OnboardingFonts.supporting(size: 16, weight: 500))
                .foregroundStyle(secondaryTextColor)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
                .onboardingTextEntrance(textEntranceVisible)
                .figmaFrame(x: 20, y: 643, width: 353, height: 44)

            primaryButton(title: L10n.onboardingLetsBingo) {
                withAnimation(.easeInOut(duration: 0.22)) {
                    onFinish()
                }
            }
            .figmaFrame(x: 93, y: 725, width: 207, height: 52)
        }
        .onAppear {
            rewardsFacesWiggle = true
        }
    }

    private var onboardingStatusBar: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("9:41")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)

            Spacer()

            Image(systemName: "cellularbars")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black)

            Image(systemName: "wifi")
                .font(.system(size: 13, weight: .semibold))
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

    private var onboardingStepsBar: some View {
        HStack(spacing: 8) {
            ForEach(Array(Page.allCases.enumerated()), id: \.offset) { index, step in
                Button {
                    jumpToPage(step)
                } label: {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(onboardingStepColor.opacity(stepOpacity(for: index)))
                        .frame(height: 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(onboardingStepColor.opacity(0.5), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 353, height: 36)
        .figmaFrame(x: 20, y: 30, width: 353, height: 36)
    }

    private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(OnboardingFonts.button(size: 20, weight: 600))
                .foregroundStyle(.white)
                .onboardingTextEntrance(textEntranceVisible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(buttonColor)
        )
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
        .onboardingTextEntrance(textEntranceVisible)
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
        .onboardingTextEntrance(textEntranceVisible)
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
        .onboardingTextEntrance(textEntranceVisible)
    }

    private func headlineText(_ text: String, size: CGFloat, lines: Int, alignment: TextAlignment) -> some View {
        Text(text)
            .font(OnboardingFonts.headline(size: size))
            .foregroundStyle(primaryTextColor)
            .multilineTextAlignment(alignment)
            .lineLimit(lines)
            .minimumScaleFactor(0.62)
            .allowsTightening(true)
            .onboardingTextEntrance(textEntranceVisible)
    }

    private func emoji(_ value: String, size: CGFloat) -> some View {
        Text(value)
            .font(.system(size: size))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func eyeball() -> some View {
        ZStack {
            Ellipse()
                .fill(.white)
                .overlay(
                    Ellipse()
                        .stroke(.black, lineWidth: 2)
                )

            Circle()
                .fill(.black)
                .frame(width: 11, height: 10)
                .offset(x: -3.2)
        }
        .frame(width: 19, height: 31)
    }

    private func progressBar(fill: Color) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(fill)
            .frame(width: 70, height: 6)
    }

    private func moveToNextPage() {
        guard let currentIndex = Page.allCases.firstIndex(of: page) else { return }
        let nextIndex = min(currentIndex + 1, Page.allCases.count - 1)

        withAnimation(.easeInOut(duration: 0.22)) {
            page = Page.allCases[nextIndex]
        }
        triggerTextEntranceAnimation()
    }

    private func jumpToPage(_ targetPage: Page) {
        withAnimation(.easeInOut(duration: 0.22)) {
            page = targetPage
        }
        triggerTextEntranceAnimation()
    }

    private func stepOpacity(for index: Int) -> Double {
        let currentIndex = page.rawValue
        if index == currentIndex { return 1.0 }
        if index < currentIndex { return 0.82 }
        return 0.28
    }

    private func triggerTextEntranceAnimation() {
        textEntranceVisible = false
        DispatchQueue.main.async {
            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.4)) {
                textEntranceVisible = true
            }
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
        case "6", "rewards":
            return .rewards
        default:
            return .intro
        }
        #else
        return .intro
        #endif
    }
}

private struct OnboardingTextEntranceModifier: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 14)
            .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.4), value: isVisible)
    }
}

private extension View {
    func onboardingTextEntrance(_ isVisible: Bool) -> some View {
        modifier(OnboardingTextEntranceModifier(isVisible: isVisible))
    }
}


enum OnboardingFonts {
    private static var usesLocalizedCJKFonts: Bool {
        switch AppLanguage.current {
        case .simplifiedChinese, .traditionalChinese, .japanese:
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
        if usesLocalizedCJKFonts {
            let uiFont = localizedUIFont(size: size * 0.9, weight: .bold)
            return Font(uiFont as CTFont)
        }

        return archivoBlack(size: size)
    }

    static func supporting(size: CGFloat, weight: CGFloat) -> Font {
        if usesLocalizedCJKFonts {
            let uiFont = localizedUIFont(size: size, weight: uiWeight(from: weight))
            return Font(uiFont as CTFont)
        }

        return outfit(size: size, weight: weight)
    }

    static func button(size: CGFloat, weight: CGFloat) -> Font {
        if usesLocalizedCJKFonts {
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
        case .english:
            return UIFont.systemFont(ofSize: size, weight: uiWeight)
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

private struct DoodleArrowView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 90.0002
        let sy = rect.height / 49.3606

        path.move(to: CGPoint(x: 0.500136 * sx, y: 48.8605 * sy))
        path.addCurve(
            to: CGPoint(x: 38.5375 * sx, y: 28.7828 * sy),
            control1: CGPoint(x: 10.2768 * sx, y: 45.5142 * sy),
            control2: CGPoint(x: 31.5716 * sx, y: 36.8139 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 15.1651 * sx, y: 15.5498 * sy),
            control1: CGPoint(x: 47.2448 * sx, y: 18.744 * sy),
            control2: CGPoint(x: 22.9559 * sx, y: 9.61777 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 60.0767 * sx, y: 37.909 * sy),
            control1: CGPoint(x: 7.37436 * sx, y: 21.4818 * sy),
            control2: CGPoint(x: 31.205 * sx, y: 42.9284 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 85.2822 * sx, y: 1.86045 * sy),
            control1: CGPoint(x: 83.1741 * sx, y: 33.8934 * sy),
            control2: CGPoint(x: 86.5043 * sx, y: 12.2035 * sy)
        )

        path.move(to: CGPoint(x: 79.5001 * sx, y: 7.86045 * sy))
        path.addLine(to: CGPoint(x: 84.7382 * sx, y: 0.860451 * sy))
        path.addLine(to: CGPoint(x: 89.5001 * sx, y: 7.86045 * sy))

        return path
    }
}

private struct UnderlineHighlight: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 93.5005
        let sy = rect.height / 7.50045

        path.move(to: CGPoint(x: 1.00018 * sx, y: 6.50027 * sy))
        path.addCurve(
            to: CGPoint(x: 92.5002 * sx, y: 1.00027 * sy),
            control1: CGPoint(x: 4.00018 * sx, y: 4.8336 * sy),
            control2: CGPoint(x: 84.5002 * sx, y: 3.66693 * sy)
        )

        return path
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
