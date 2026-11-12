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

struct OnboardingFlowView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var page = 0

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-OnboardingPage"), index + 1 < arguments.count,
           let requestedPage = Int(arguments[index + 1]) {
            _page = State(initialValue: min(max(requestedPage, 0), 4))
        }
        #endif
    }
    @State private var pressing = false
    @State private var activated = false
    @State private var completed: Set<Int> = []
    @State private var demoCursor: Int? = nil
    private let cream = Color(hex: "FCF7F1")
    private let ink = Color(hex: "40270F")
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
    private var labels: [String] { [
        tr("Drink water", "喝杯水", "水を飲む", "물 마시기", "Wasser trinken"),
        tr("Focus", "专注一下", "集中する", "집중하기", "Konzentrieren"),
        tr("Get some sun", "晒晒太阳", "日光を浴びる", "햇볕 쬐기", "Sonne tanken"),
        tr("Stretch", "伸个懒腰", "ストレッチ", "스트레칭", "Dehnen"),
        tr("Eat well", "好好吃饭", "食事を楽しむ", "식사하기", "Gut essen"),
        tr("Tidy desk", "整理桌面", "机を片づける", "책상 정리", "Tisch aufräumen"),
        tr("Go outside", "出门走走", "外を歩く", "산책하기", "Rausgehen"),
        tr("Take a break", "休息一下", "ひと休み", "쉬어가기", "Pause machen"),
        tr("Sleep early", "早点睡觉", "早く寝る", "일찍 자기", "Früh schlafen")
    ] }
    private let mascots = ["sticker_cozy_10", "sticker_cozy_12", "sticker_cozy_07", "sticker_cozy_02", "sticker_cozy_09_hidden", "sticker_cozy_11", "sticker_cozy_02", "sticker_cozy_07", "sticker_cozy_13"]
    private var bingo: Bool {
        let lines = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]
        return lines.contains { line in line.allSatisfy { completed.contains($0) } }
    }
    private var title: String {
        switch page {
        case 1: tr("Turn everyday life into Bingo", "把日常生活，变成 Bingo 游戏", "毎日をビンゴにしよう", "일상을 빙고로 만들어 보세요", "Mach deinen Alltag zum Bingo")
        case 2: tr("Go at your own pace", "按自己的节奏，慢慢来就好", "自分のペースで進もう", "나만의 속도로 천천히", "Geh in deinem Tempo voran")
        case 3: bingo
            ? tr("Bingo! Every small win counts", "Bingo！小小完成，也值得庆祝", "ビンゴ！小さな達成も大切に", "빙고! 작은 성취도 소중해요", "Bingo! Jeder kleine Erfolg zählt")
            : tr("One tile is one step forward", "点亮一格，就是向前一步", "一マスずつ、前へ", "한 칸씩 앞으로", "Ein Feld nach dem anderen")
        default: tr("Start each day with Juanjuan", "和卷卷一起，开启你的每一天", "ジュアンジュアンと一日を始めよう", "주안주안과 하루를 시작해요", "Starte jeden Tag mit Juanjuan")
        }
    }
    private var subtitle: String {
        switch page {
        case 1: tr("Add water, a walk, and little things you want to do to your board.\nEven an ordinary day can feel playful.", "把喝水、散步和想做的小事放进棋盘。\n平凡的一天，也能玩出一点期待。", "水を飲む、散歩する。小さな予定をボードに並べよう。\n何気ない一日も楽しくなります。", "물 마시기와 산책 같은 작은 일을 보드에 담아 보세요.\n평범한 하루도 즐거워져요.", "Trage Wassertrinken, Spazierengehen und kleine Vorhaben ein.\nSo macht auch ein gewöhnlicher Tag Spaß.")
        case 2: tr("You don't have to do it all at once or compare yourself with others.\nA small step and a pause both belong to your rhythm.", "不必一口气做完，也不用和别人比较。\n做一小步，停一会儿，都有自己的节奏。", "一度に全部やらなくても、誰かと比べなくても大丈夫。\n小さな一歩も休憩も、あなたのペースで。", "한 번에 다 하거나 남과 비교할 필요 없어요.\n작은 한 걸음과 쉼 모두 나만의 리듬이에요.", "Du musst nicht alles auf einmal schaffen oder dich vergleichen.\nKleine Schritte und Pausen gehören zu deinem Rhythmus.")
        case 3: tr("Tap a tile to complete a task. Finish a line to get Bingo!\nGive it a try and celebrate small wins.", "点击格子完成待办，连成一列就能收获 Bingo。\n试着点一点，让小小成就被看见。", "マスをタップしてタスクを完了。列がそろえばビンゴ！\n小さな達成を楽しもう。", "칸을 눌러 할 일을 완료하세요. 한 줄을 채우면 빙고!\n작은 성취를 축하해요.", "Tippe auf ein Feld, um eine Aufgabe zu erledigen. Eine Reihe ergibt Bingo!\nFeiere deine kleinen Erfolge.")
        default: tr("Start with one small thing you'd like to do.\nYour life, your pace, your Bingo.", "从一件想做的小事开始。\n你的生活，你的节奏，你的 Bingo。", "やってみたい小さなことから始めよう。\nあなたの暮らし、あなたのペース、あなたのビンゴ。", "하고 싶은 작은 일 하나부터 시작해요.\n나의 일상, 나의 속도, 나의 빙고.", "Beginne mit einer kleinen Sache, die du tun möchtest.\nDein Leben, dein Tempo, dein Bingo.")
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                cream.ignoresSafeArea()
                if page == 0 {
                    activation(size: geometry.size)
                } else {
                    introduction(size: geometry.size)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(ink)
        }
        .preferredColorScheme(.light)
        .task(id: page) {
            guard page == 3 else { return }
            completed = []
            for index in [0, 3, 6] {
                do {
                    try await Task.sleep(for: .milliseconds(900))
                    demoCursor = index
                    try await Task.sleep(for: .milliseconds(350))
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                        _ = completed.insert(index)
                    }
                } catch { return }
            }
            demoCursor = nil
        }
        .task(id: activated) {
            guard activated else { return }
            do { try await Task.sleep(for: .milliseconds(850)) } catch { return }
            advance()
        }
    }

    private func activation(size: CGSize) -> some View {
        ZStack {
            ForEach(0..<4) { index in
                Circle()
                    .fill(index.isMultiple(of: 2) ? Color(hex: "FAF0E5") : Color.white)
                    .frame(width: CGFloat(4 - index) * 210, height: CGFloat(4 - index) * 210)
                    .scaleEffect(reduceMotion ? 1 : pressing || activated ? 1 : 0.2)
                    .opacity(pressing || activated ? 1 : 0)
            }
            VStack(spacing: 48) {
                Image(pressing || activated ? "OnboardingEnterPressed" : "OnboardingEnterNormal")
                    .resizable().scaledToFit()
                    .frame(width: 200, height: 200)
                .scaleEffect(pressing || activated ? 0.96 : 1)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.8, maximumDistance: 45) {
                    guard !activated else { return }
                    AppHaptics.completion()
                    activated = true
                } onPressingChanged: { value in
                    guard !activated else { return }
                    withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) { pressing = value }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tr("Press and hold to wake Juanjuan and enter Bingodays", "长按唤醒卷卷，进入 Bingodays", "長押ししてジュアンジュアンを起こし、Bingodaysを始める", "길게 눌러 주안주안을 깨우고 Bingodays 시작하기", "Gedrückt halten, um Juanjuan zu wecken und Bingodays zu starten"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { activated = true }
                Text(activated
                    ? tr("Starting Bingodays…", "Bingodays 启动中…", "Bingodaysを起動中…", "Bingodays 시작 중…", "Bingodays startet …")
                    : pressing
                        ? tr("Hold a little longer…", "再按住一会儿…", "もう少し長押しして…", "조금만 더 누르세요…", "Noch etwas länger halten …")
                        : tr("Press and hold to start with Juanjuan…", "长按，和卷卷一起出发…", "長押ししてジュアンジュアンと出発…", "길게 눌러 주안주안과 함께 시작해요…", "Gedrückt halten und mit Juanjuan starten …"))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .contentTransition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func introduction(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { previous() } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel(tr("Previous page", "上一页", "前のページ", "이전 페이지", "Vorherige Seite"))
                .opacity(page == 1 ? 0 : 1)
                .disabled(page == 1)
                Spacer()
                Text(page < 3
                    ? tr("Meet Bingodays", "认识 Bingodays", "Bingodaysを知ろう", "Bingodays 알아보기", "Bingodays kennenlernen")
                    : tr("Your first Bingo", "你的第一场 Bingo", "初めてのビンゴ", "첫 번째 빙고", "Dein erstes Bingo"))
                    .font(.footnote).foregroundStyle(ink.opacity(0.6))
                Spacer()
                Text("\(page) / 4").font(.caption.monospacedDigit()).frame(width: 44)
            }
            .padding(.horizontal, 12)
            ScrollView {
                VStack(spacing: 28) {
                    illustration
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? 440 : min(440, max(350, size.height * 0.55)))
                        .background(Color(hex: "C5E3FA"), in: RoundedRectangle(cornerRadius: 24))
                        .clipped()
                        .accessibilityElement(children: page == 3 ? .contain : .ignore)
                    VStack(spacing: 12) {
                        Text(title).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                        Text(subtitle).font(.subheadline).foregroundStyle(ink.opacity(0.6)).lineSpacing(4)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: 20) {
                HStack(spacing: 6) {
                    ForEach(1...4, id: \.self) { step in
                        Capsule().fill(step == page ? ink : ink.opacity(0.15)).frame(width: step == page ? 20 : 6, height: 6)
                    }
                }
                .accessibilityLabel(tr("Page \(page) of 4", "第 \(page) 页，共 4 页", "\(page) / 4 ページ", "\(page)/4 페이지", "Seite \(page) von 4"))
                Button(page == 4
                    ? tr("Start my Bingo", "开启我的 Bingo", "ビンゴを始める", "내 빙고 시작하기", "Mein Bingo starten")
                    : tr("Continue", "继续", "続ける", "계속", "Weiter")) {
                    AppHaptics.control()
                    if page == 4 { onFinish() } else { advance() }
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: 260, minHeight: 54)
                .background(ink, in: Capsule())
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder private var illustration: some View {
        if page == 2 {
            VStack(spacing: 16) {
                Image("sticker_cozy_07").resizable().scaledToFit().frame(maxWidth: 240, maxHeight: 240)
                Text(tr("It's okay to slow down today", "今天，也可以慢一点", "今日はゆっくりでも大丈夫", "오늘은 천천히 가도 괜찮아요", "Heute darfst du es langsam angehen lassen")).font(.headline).foregroundStyle(ink.opacity(0.7))
                HStack(spacing: 8) {
                    ForEach([
                        tr("One small step", "一小步", "小さな一歩", "작은 한 걸음", "Ein kleiner Schritt"),
                        tr("Take a break", "休息一下", "ひと休み", "잠깐 쉬기", "Pause machen"),
                        tr("Keep going", "再出发", "また進もう", "다시 시작", "Weitergehen")
                    ], id: \.self) { item in
                        Text(item).font(.caption).padding(.horizontal, 12).padding(.vertical, 8).background(.white.opacity(0.7), in: Capsule())
                    }
                }
            }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if page == 4 {
            VStack(spacing: 16) {
                Text("BINGO!").font(.system(size: 40, weight: .black, design: .rounded)).rotationEffect(.degrees(-6))
                Image("sticker_cozy_03").resizable().scaledToFit().frame(maxWidth: 210, maxHeight: 230)
                Text(tr("Every small win counts.", "让每一个小小完成，都算数。", "小さな達成も、一つずつ大切に。", "작은 성취도 모두 소중해요.", "Jeder kleine Erfolg zählt.")).font(.subheadline.weight(.medium))
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(0..<9) { index in
                        let completionLabel = completed.contains(index)
                            ? tr("completed", "已完成", "完了", "완료", "erledigt")
                            : tr("tap to complete", "点击完成", "タップして完了", "눌러서 완료", "zum Erledigen tippen")
                        Button {
                            guard page == 3 else { return }
                            AppHaptics.completion()
                            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) { _ = completed.insert(index) }
                        } label: {
                            VStack(spacing: 2) {
                                Image(mascots[index]).resizable().scaledToFit().frame(height: 60)
                                Text(labels[index]).font(.caption2.weight(.medium)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity).frame(height: 94)
                            .background(completed.contains(index) && page == 3 ? Color(hex: "DCF1D9") : cream, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(alignment: .topTrailing) {
                                if completed.contains(index) && page == 3 {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: "56B97D")).padding(5)
                                }
                            }
                            .overlay {
                                if demoCursor == index && page == 3 && !bingo {
                                    Image(systemName: "hand.tap.fill").font(.system(size: 32)).foregroundStyle(ink).offset(x: 16, y: 24)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(page == 3)
                        .accessibilityLabel("\(labels[index]), \(completionLabel)")
                    }
                }.padding(22)
                if page == 3 && bingo {
                    Text("BINGO!").font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(ink).padding(.horizontal, 24).padding(.vertical, 12)
                        .background(.white, in: Capsule()).rotationEffect(.degrees(-8))
                        .shadow(color: ink.opacity(0.1), radius: 12, y: 6)
                        .transition(.scale(scale: reduceMotion ? 1 : 0.8).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .accessibilityLabel(tr("Bingo! You completed a line", "Bingo！完成一列了", "ビンゴ！一列そろいました", "빙고! 한 줄을 완성했어요", "Bingo! Du hast eine Reihe geschafft"))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func advance() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { page = min(page + 1, 4) }
    }

    private func previous() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { page = max(1, page - 1) }
    }
}

private struct OnboardingTextEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduceMotion || isVisible ? 0 : 14)
            .animation(
                reduceMotion ? .easeInOut(duration: 0.16) : .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.4),
                value: isVisible
            )
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

private extension View {
    func onboardingTextEntrance(_ isVisible: Bool) -> some View {
        modifier(OnboardingTextEntranceModifier(isVisible: isVisible))
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
