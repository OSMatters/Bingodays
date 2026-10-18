import SwiftUI

enum FirstStepGuideOverlay: String, Identifiable {
    case intro
    case milestoneOne
    case milestoneTwo
    case milestoneThree

    var id: String { rawValue }
}

struct FirstStepGuideOverlayView: View {
    let overlay: FirstStepGuideOverlay
    let isPadLayout: Bool
    let presentation: FirstStepGuideStore.OverlayPresentation
    let onStart: () -> Void
    let onDismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesReflowedType: Bool {
        dynamicTypeSize == .xLarge ||
            dynamicTypeSize == .xxLarge ||
            dynamicTypeSize == .xxxLarge ||
            dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .blur(radius: 10)

                    Color.black.opacity(0.6)
                }
                .ignoresSafeArea()

                Group {
                    if usesReflowedType {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 22) {
                                overlayContent
                            }
                            .padding(.horizontal, isPadLayout ? 38 : 28)
                            .padding(.vertical, 16)
                            .frame(maxWidth: 560)
                        }
                        .frame(maxHeight: max(
                            220,
                            proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom - 32
                        ))
                    } else {
                        VStack(spacing: 22) {
                            overlayContent
                        }
                        .padding(.horizontal, isPadLayout ? 38 : 28)
                        .frame(maxWidth: 560)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        switch overlay {
        case .intro:
            introContent
        case .milestoneOne, .milestoneTwo:
            if let milestone = presentation.milestone(for: overlay) {
                milestoneContent(milestone)
            }
        case .milestoneThree:
            if let milestone = presentation.milestone(for: overlay) {
                milestoneThreeContent(milestone)
            }
        }
    }

    private var introContent: some View {
        VStack(spacing: 20) {
            Text(presentation.introTitle)
                .appDynamicFont(size: scaled(23, pad: 31), weight: .heavy, design: .rounded)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Image("StarterGuideArrow")
                .resizable()
                .scaledToFit()
                .frame(width: isPadLayout ? 72 : 56)
                .padding(.top, -4)
                .padding(.bottom, -2)

            introBoardPreview

            Text(presentation.introDescription)
                .appDynamicFont(size: scaled(19, pad: 23), weight: .semibold, design: .rounded)
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                guideButton(title: "OK", action: onStart, height: isPadLayout ? 58 : 52)
                Spacer()
            }
            .padding(.top, 12)
        }
    }

    private var introBoardPreview: some View {
        Group {
            if usesReflowedType {
                reflowedIntroBoardPreview
            } else {
                compactIntroBoardPreview
            }
        }
        .frame(maxWidth: 480)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(boardPreviewAccessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    private var compactIntroBoardPreview: some View {
        let cardCorner: CGFloat = isPadLayout ? 34 : 28
        let cellCorner: CGFloat = isPadLayout ? 16 : 14
        let spacing: CGFloat = isPadLayout ? 14 : 10

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                .fill(NeumorphicColors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                        .stroke(Color.white.opacity(0.36), lineWidth: 1)
                )
                .shadow(color: Color.white.opacity(0.3), radius: 10, x: -4, y: -4)
                .shadow(color: Color.black.opacity(0.22), radius: 14, x: 5, y: 8)

            VStack(spacing: spacing) {
                ForEach(presentation.previewRows.indices, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(presentation.previewRows[row]) { cell in
                            previewCell(cell, cornerRadius: cellCorner, accessibilityLayout: false)
                        }
                    }
                }
            }
            .padding(isPadLayout ? 20 : 16)

            Image("StarterGuideClick")
                .resizable()
                .scaledToFit()
                .frame(width: isPadLayout ? 77 : 65)
                .offset(x: isPadLayout ? 44 : 38, y: isPadLayout ? 92 : 80)
        }
        .frame(maxWidth: 480)
        .aspectRatio(1, contentMode: .fit)
    }

    private var reflowedIntroBoardPreview: some View {
        VStack(spacing: 8) {
            ForEach(presentation.previewRows.indices, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(presentation.previewRows[row]) { cell in
                        previewCell(cell, cornerRadius: 14, accessibilityLayout: true)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(NeumorphicColors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.36), lineWidth: 1)
                )
                .shadow(color: Color.white.opacity(0.3), radius: 10, x: -4, y: -4)
                .shadow(color: Color.black.opacity(0.22), radius: 14, x: 5, y: 8)
        )
    }

    @ViewBuilder
    private func previewCell(
        _ cell: FirstStepGuideStore.OverlayPresentation.PreviewCell,
        cornerRadius: CGFloat,
        accessibilityLayout: Bool
    ) -> some View {
        if accessibilityLayout {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(NeumorphicColors.background)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(hex: "E2DAD0"), lineWidth: 1)
                if !cell.text.isEmpty {
                    Text(cell.text)
                        .appDynamicFont(size: scaled(16, pad: 18), weight: .bold, design: .rounded)
                        .foregroundStyle(NeumorphicColors.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(NeumorphicColors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color(hex: "E2DAD0"), lineWidth: 1)
                )
                .overlay {
                    if !cell.text.isEmpty {
                        Text(cell.text)
                            .font(.appSystem(size: scaled(16, pad: 18), weight: .bold, design: .rounded))
                            .foregroundStyle(NeumorphicColors.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
        }
    }

    private var boardPreviewAccessibilityLabel: String {
        let exampleTasks = presentation.previewRows
            .flatMap { $0 }
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: L10n.tr(", ", zhHans: "、", zhHant: "、", ja: "、"))

        return L10n.tr(
            "Example 3 by 3 Bingo board. Example tasks: \(exampleTasks)",
            zhHans: "3×3宾果棋盘示例。示例任务：\(exampleTasks)",
            zhHant: "3×3賓果棋盤範例。示例任務：\(exampleTasks)",
            ja: "3×3のBingoボードの例。タスク例：\(exampleTasks)"
        )
    }

    private func milestoneContent(_ milestone: FirstStepGuideStore.OverlayPresentation.Milestone) -> some View {
        VStack(spacing: 20) {
            Image(milestone.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: isPadLayout ? 240 : 188)

            Text(milestone.message)
                .appDynamicFont(size: scaled(21, pad: 29), weight: .heavy, design: .rounded)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)

            guideButton(title: "OK", action: onDismiss, height: isPadLayout ? 60 : 52)
                .padding(.top, 12)
        }
        .frame(maxWidth: 520)
    }

    private func milestoneThreeContent(_ milestone: FirstStepGuideStore.OverlayPresentation.Milestone) -> some View {
        VStack(spacing: 20) {
            Image(milestone.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: isPadLayout ? 210 : 150)

            Group {
                if usesReflowedType {
                    VStack(spacing: 10) {
                        ForEach(presentation.seedTasks, id: \.self) { task in
                            seedTaskCard(task, isAccessibilityLayout: true)
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        ForEach(presentation.seedTasks, id: \.self) { task in
                            seedTaskCard(task, isAccessibilityLayout: false)
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: "3F270F").opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(hex: "CFA46F").opacity(0.7), lineWidth: 1)
                    )
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkles")
                    .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                    .foregroundStyle(Color(hex: "F5C164"))
                    .offset(x: 10, y: -10)
            }
            .overlay(alignment: .bottomLeading) {
                Image(systemName: "sparkles")
                    .font(.appSystem(size: scaled(16, pad: 18), weight: .bold))
                    .foregroundStyle(Color(hex: "F5C164"))
                    .offset(x: -10, y: 10)
            }

            Text(milestone.message)
                .appDynamicFont(size: scaled(21, pad: 29), weight: .heavy, design: .rounded)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            guideButton(title: "OK", action: onDismiss, height: isPadLayout ? 60 : 52)
                .padding(.top, 10)
        }
        .frame(maxWidth: 520)
    }

    private func guideButton(title: String, action: @escaping () -> Void, height: CGFloat) -> some View {
        Button(action: action) {
            Text(title)
                .appDynamicFont(size: scaled(14, pad: 18), weight: .bold, design: .rounded)
                .foregroundStyle(.white)
                .frame(width: isPadLayout ? 300 : 220)
                .padding(.vertical, usesReflowedType ? 10 : 0)
                .frame(minHeight: height)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(Color.white.opacity(0.75), lineWidth: 1.5)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(width: isPadLayout ? 300 : 220)
        .frame(minHeight: height)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func seedTaskCard(_ task: String, isAccessibilityLayout: Bool) -> some View {
        VStack(spacing: 12) {
            Group {
                if isAccessibilityLayout {
                    Text(task)
                        .appDynamicFont(size: scaled(15, pad: 17), weight: .bold, design: .rounded)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(task)
                        .appDynamicFont(size: scaled(15, pad: 17), weight: .bold, design: .rounded)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)

            Image(systemName: "checkmark.circle.fill")
                .font(.appSystem(size: scaled(22, pad: 24), weight: .bold))
                .foregroundStyle(.white.opacity(0.96))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .frame(minHeight: isAccessibilityLayout ? 64 : (isPadLayout ? 128 : 106))
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "D3A375"))
        )
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }
}
