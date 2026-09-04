import SwiftUI

enum HomeMainTab: String, CaseIterable, Identifiable {
    case home
    case points
    case me

    var id: String { rawValue }

    var accessibilityTitle: String {
        switch self {
        case .home:
            return L10n.tr("Home", zhHans: "首页", zhHant: "首頁", ja: "ホーム")
        case .points:
            return L10n.tr("Points", zhHans: "积分", zhHant: "積分", ja: "ポイント")
        case .me:
            return L10n.tr("Me", zhHans: "我的", zhHant: "我的", ja: "マイページ")
        }
    }

    var iconName: String {
        switch self {
        case .home:
            return "HomeTabHome"
        case .points:
            return "HomeTabRedeem"
        case .me:
            return "HomeTabMe"
        }
    }

    var selectedIconName: String {
        switch self {
        case .home:
            return "HomeTabHomeSelected"
        case .points:
            return "HomeTabRedeemSelected"
        case .me:
            return "HomeTabMeSelected"
        }
    }
}

struct HomeMainTabBarView: View {
    @Binding var selectedTab: HomeMainTab
    let isPadLayout: Bool
    @State private var bouncingTab: HomeMainTab?

    var body: some View {
        tabButtons
            .frame(width: scaled(292, pad: 360), height: scaled(56, pad: 66))
            .appLiquidGlass(in: Capsule(style: .continuous), interactive: false)
            .contentShape(Capsule(style: .continuous))
    }

    private var tabButtons: some View {
        HStack(spacing: scaled(42, pad: 58)) {
            ForEach(HomeMainTab.allCases) { tab in
                Button {
                    guard selectedTab != tab else {
                        triggerTabBounce(for: tab)
                        return
                    }
                    selectedTab = tab
                    triggerTabBounce(for: tab)
                } label: {
                    Image(selectedTab == tab ? tab.selectedIconName : tab.iconName)
                        .resizable()
                        .interpolation(.high)
                        .renderingMode(.original)
                        .scaledToFit()
                        .opacity(selectedTab == tab ? 1 : 0.7)
                        .frame(
                            width: selectedTab == tab ? scaled(40, pad: 46) : scaled(30, pad: 36),
                            height: selectedTab == tab ? scaled(40, pad: 46) : scaled(30, pad: 36)
                        )
                        .scaleEffect(bouncingTab == tab ? 1.08 : 1)
                        .offset(y: bouncingTab == tab ? scaled(-3, pad: -4) : 0)
                        .animation(.interpolatingSpring(stiffness: 360, damping: 13), value: bouncingTab)
                        .frame(width: scaled(52, pad: 62), height: scaled(44, pad: 52))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.accessibilityTitle)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
    }

    private func triggerTabBounce(for tab: HomeMainTab) {
        withAnimation(.interpolatingSpring(stiffness: 360, damping: 13)) {
            bouncingTab = tab
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard bouncingTab == tab else { return }
            withAnimation(.interpolatingSpring(stiffness: 260, damping: 15)) {
                bouncingTab = nil
            }
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}

struct BoardSwitcherControlsView: View {
    let boards: [BingoBoardStore.NamedBoard]
    let selectedBoardID: UUID?
    let contentWidth: CGFloat
    let isPadLayout: Bool
    let shouldShowBoardEditHint: Bool
    let shouldReserveBoardEditHintSpace: Bool
    let onSelectBoard: (UUID) -> Void
    let onBoardLongPress: (UUID) -> Void
    let onCreateBoard: () -> Void
    let onDismissBoardEditHint: () -> Void
    @State private var hasReservedBoardEditHintSpace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldShowBoardEditHint || shouldReserveBoardEditHintSpace || hasReservedBoardEditHintSpace {
                ZStack(alignment: .topLeading) {
                    if shouldShowBoardEditHint {
                        BoardEditHintBubbleView(
                            isPadLayout: isPadLayout,
                            onDismiss: onDismissBoardEditHint
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomLeading)))
                    }
                }
                .frame(height: isPadLayout ? 56 : 51, alignment: .topLeading)
                .allowsHitTesting(shouldShowBoardEditHint)
            }

            HStack(spacing: 10) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(boards) { board in
                                let isSelected = board.id == selectedBoardID

                                Button {
                                    onSelectBoard(board.id)
                                } label: {
                                    Text(board.name)
                                        .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .foregroundColor(isSelected ? NeumorphicColors.accent : NeumorphicColors.text)
                                        .padding(.horizontal, 14)
                                        .frame(height: isPadLayout ? 38 : 36)
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .stroke(
                                                    isSelected ? NeumorphicColors.accent : NeumorphicColors.accent.opacity(0.22),
                                                    lineWidth: 1
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                                .id(board.id)
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: 0.5)
                                        .onEnded { _ in
                                            onBoardLongPress(board.id)
                                        }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 1)
                    }
                    .onAppear {
                        positionSelectedBoard(using: proxy, animated: false)
                    }
                    .onChange(of: selectedBoardID) { _, _ in
                        positionSelectedBoard(using: proxy, animated: true)
                    }
                }
                .frame(height: isPadLayout ? 42 : 40)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onCreateBoard) {
                    Text(L10n.tr("+ add board", zhHans: "+ 添加棋盘", zhHant: "+ 新增棋盤"))
                        .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .frame(height: isPadLayout ? 38 : 36)
                        .background(
                            RoundedRectangle(cornerRadius: isPadLayout ? 19 : 18, style: .continuous)
                                .fill(Color.white.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(width: contentWidth, alignment: .leading)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: shouldShowBoardEditHint)
        .onAppear {
            if shouldShowBoardEditHint || shouldReserveBoardEditHintSpace {
                hasReservedBoardEditHintSpace = true
            }
        }
        .onChange(of: shouldShowBoardEditHint) { _, newValue in
            if newValue {
                hasReservedBoardEditHintSpace = true
            }
        }
        .onChange(of: shouldReserveBoardEditHintSpace) { _, newValue in
            if newValue {
                hasReservedBoardEditHintSpace = true
            }
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }

    private func positionSelectedBoard(using proxy: ScrollViewProxy, animated: Bool) {
        guard let selectedBoardID,
              let selectedIndex = boards.firstIndex(where: { $0.id == selectedBoardID }) else {
            return
        }
        let anchor: UnitPoint
        if selectedIndex == boards.startIndex {
            anchor = .leading
        } else if selectedIndex == boards.index(before: boards.endIndex) {
            anchor = .trailing
        } else {
            anchor = .center
        }

        DispatchQueue.main.async {
            if animated {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    proxy.scrollTo(selectedBoardID, anchor: anchor)
                }
            } else {
                proxy.scrollTo(selectedBoardID, anchor: anchor)
            }
        }
    }
}

private struct BoardEditHintBubbleView: View {
    let isPadLayout: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: isPadLayout ? 7 : 6) {
                Image(systemName: "hand.tap")
                    .font(.appSystem(size: isPadLayout ? 14 : 12, weight: .medium))
                    .foregroundColor(Color(hex: "9D9D9D"))
                    .frame(width: isPadLayout ? 18 : 16)

                Text(L10n.boardEditHintMessage)
                    .font(.appSystem(size: isPadLayout ? 12 : 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "2B2B2B"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                Button(action: onDismiss) {
                    Text(L10n.boardEditHintAcknowledge)
                        .font(.appSystem(size: isPadLayout ? 11 : 10, weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.accent)
                        .padding(.horizontal, 3)
                        .frame(height: isPadLayout ? 23 : 21)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, isPadLayout ? 15 : 14)
            .padding(.trailing, isPadLayout ? 8 : 7)
            .frame(height: isPadLayout ? 38 : 34)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.96))
            )

            Triangle()
                .fill(Color.white.opacity(0.96))
                .frame(width: isPadLayout ? 17 : 15, height: isPadLayout ? 11 : 10)
                .offset(x: isPadLayout ? 19 : 18, y: isPadLayout ? 9 : 8)
        }
        .padding(.bottom, isPadLayout ? 12 : 11)
        .offset(y: 8)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct BoardActionsOverlayView: View {
    let canDelete: Bool
    let contentWidth: CGFloat
    let bottomInset: CGFloat
    let isPadLayout: Bool
    let onDismiss: () -> Void
    let onBoardRules: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var homeBottomBackgroundColor: Color { Color(hex: "FAF9F3") }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 12) {
                actionButton(
                    title: L10n.tr("Board Rules", zhHans: "面板规则", zhHant: "面板規則"),
                    color: NeumorphicColors.text,
                    action: onBoardRules
                )

                actionButton(
                    title: L10n.tr("Rename Board", zhHans: "重命名面板", zhHant: "重新命名面板", ja: "ボード名を変更"),
                    color: NeumorphicColors.text,
                    action: onEdit
                )

                if canDelete {
                    actionButton(
                        title: L10n.tr("Delete Board", zhHans: "删除面板", zhHant: "刪除面板", ja: "ボードを削除"),
                        color: Color.red.opacity(0.84),
                        action: onDelete
                    )
                }
            }
            .frame(width: min(contentWidth, isPadLayout ? 460 : 353))
            .padding(.top, 14)
            .padding(.bottom, max(bottomInset, 14) + 12)
            .frame(maxWidth: .infinity)
            .background(
                homeBottomBackgroundColor
                    .ignoresSafeArea(edges: .bottom)
                    .onTapGesture(perform: onDismiss)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func actionButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: scaled(16, pad: 18), weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(homeBottomBackgroundColor)
                )
        }
        .buttonStyle(.plain)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }
}

struct BoardBottomControlsView: View {
    let countdownText: String?
    let isPadLayout: Bool
    let isEditActionsExpanded: Bool
    let surfaceShadowColor: Color
    let themeColor: Color
    let onCountdown: () -> Void
    let onEditActionsToggle: () -> Void
    let onDismissEditActions: () -> Void
    let onBoardRules: () -> Void
    let onShuffle: () -> Void
    let onClearBoard: () -> Void
    let onGridSize: () -> Void
    let onQuickEdit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BoardMoreActionsTriggerView(
                isExpanded: isEditActionsExpanded,
                isPadLayout: isPadLayout,
                themeColor: themeColor,
                onTap: onEditActionsToggle
            )

            Spacer(minLength: 0)

            if let countdownText {
                BoardCountdownTriggerView(
                    text: countdownText,
                    isPadLayout: isPadLayout,
                    surfaceShadowColor: surfaceShadowColor,
                    onTap: onCountdown
                )
                .offset(y: isPadLayout ? 4 : 3)
            } else {
                Color.clear
                    .frame(width: isPadLayout ? 170 : 140, height: isPadLayout ? 38 : 32)
            }

            Spacer(minLength: 0)

            BoardQuickEditTriggerView(
                isPadLayout: isPadLayout,
                onTap: onQuickEdit
            )
        }
        .frame(height: isPadLayout ? 44 : 38, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            if isEditActionsExpanded {
                BoardMoreActionsSidePanel(
                    isPadLayout: isPadLayout,
                    onDismiss: onDismissEditActions,
                    onBoardRules: onBoardRules,
                    onShuffle: onShuffle,
                    onClearBoard: onClearBoard,
                    onGridSize: onGridSize
                )
                .offset(x: moreActionsPanelOffsetX, y: moreActionsPanelOffsetY)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
                .zIndex(2)
            }
        }
    }

    private var moreActionsPanelOffsetX: CGFloat {
        isPadLayout ? 63 : 53
    }

    private var moreActionsPanelOffsetY: CGFloat {
        let triggerSize: CGFloat = isPadLayout ? 44 : 38
        let rowHeight: CGFloat = isPadLayout ? 54 : 52
        let verticalPadding: CGFloat = isPadLayout ? 6 : 5
        let panelHeight = rowHeight * 4 + verticalPadding * 2

        return triggerSize - panelHeight
    }
}

struct BoardMoreActionsTriggerView: View {
    let isExpanded: Bool
    let isPadLayout: Bool
    let themeColor: Color
    let onTap: () -> Void

    var body: some View {
        let buttonSize: CGFloat = isPadLayout ? 44 : 38

        Button(action: onTap) {
            Image("HomeMore")
                .resizable()
                .interpolation(.high)
                .renderingMode(.template)
                .foregroundColor(themeColor)
                .scaledToFit()
                .frame(width: isPadLayout ? 25 : 21, height: isPadLayout ? 25 : 21)
                .frame(width: buttonSize, height: buttonSize)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.64))
                }
                .appLiquidGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: buttonSize, height: buttonSize, alignment: .bottomTrailing)
        .accessibilityLabel(L10n.tr("More board actions", zhHans: "更多棋盘操作", zhHant: "更多棋盤操作", ja: "その他のボード操作"))
        .accessibilityAddTraits(isExpanded ? .isSelected : [])
    }
}

struct BoardQuickEditTriggerView: View {
    let isPadLayout: Bool
    let onTap: () -> Void

    var body: some View {
        let buttonSize: CGFloat = isPadLayout ? 44 : 38

        Button(action: onTap) {
            Image(systemName: "square.and.pencil")
                .font(.appSystem(size: isPadLayout ? 20 : 18, weight: .bold))
                .foregroundColor(NeumorphicColors.accent)
                .frame(width: buttonSize, height: buttonSize)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.64))
                }
                .appLiquidGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: buttonSize, height: buttonSize, alignment: .bottomTrailing)
        .accessibilityLabel(L10n.quickEdit)
    }
}

struct BoardMoreActionsSidePanel: View {
    let isPadLayout: Bool
    let onDismiss: () -> Void
    let onBoardRules: () -> Void
    let onShuffle: () -> Void
    let onClearBoard: () -> Void
    let onGridSize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionButton(L10n.tr("Board Rules", zhHans: "面板规则", zhHant: "面板規則"), action: onBoardRules)
            actionButton(L10n.tr("Shuffle", zhHans: "随机排序"), action: onShuffle)
            actionButton(L10n.clearBoard, action: onClearBoard)
            actionButton(L10n.tr("Grid Size", zhHans: "格子大小"), action: onGridSize)
        }
        .padding(.vertical, scaled(5, pad: 6))
        .frame(width: scaled(160, pad: 184), alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: scaled(8, pad: 10), style: .continuous)
                .fill(Color.white.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: scaled(8, pad: 10), style: .continuous)
                        .stroke(Color(hex: "E9E4DA"), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.045), radius: 8, x: 0, y: 4)
        )
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            onDismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                action()
            }
        } label: {
            Text(title)
                .font(.appSystem(size: scaled(16, pad: 18), weight: .regular, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, scaled(12, pad: 14))
                .padding(.vertical, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct BoardCountdownTriggerView: View {
    let text: String
    let isPadLayout: Bool
    let surfaceShadowColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(text)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(NeumorphicColors.text)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.appSystem(size: scaled(11, pad: 12), weight: .semibold))
                    .foregroundColor(NeumorphicColors.accent)
            }
            .padding(.horizontal, isPadLayout ? 20 : 16)
            .frame(height: isPadLayout ? 38 : 32)
            .frame(minWidth: isPadLayout ? 152 : 124)
            .background(
                themedFunctionSurface(
                    cornerRadius: isPadLayout ? 19 : 16,
                    shadowRadius: isPadLayout ? 12 : 10,
                    offset: isPadLayout ? 6 : 5
                )
            )
        }
        .buttonStyle(.plain)
    }

    private func themedFunctionSurface(cornerRadius: CGFloat, shadowRadius: CGFloat, offset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.5))
            .shadow(color: Color.white, radius: shadowRadius + 3, x: -offset - 1, y: -offset - 1)
            .shadow(color: surfaceShadowColor.opacity(0.2), radius: shadowRadius + 3, x: offset + 1, y: offset + 1)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}
