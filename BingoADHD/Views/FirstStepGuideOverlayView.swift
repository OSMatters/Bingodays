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

    var body: some View {
        ZStack {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .blur(radius: 10)

                Color.black.opacity(0.6)
            }
            .ignoresSafeArea()

            VStack(spacing: 22) {
                overlayContent
            }
            .padding(.horizontal, isPadLayout ? 38 : 28)
            .frame(maxWidth: 560)
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
                .font(.appSystem(size: scaled(23, pad: 31), weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Image("StarterGuideArrow")
                .resizable()
                .scaledToFit()
                .frame(width: isPadLayout ? 72 : 56)
                .padding(.top, -4)
                .padding(.bottom, -2)

            introBoardPreview

            Text(presentation.introDescription)
                .font(.appSystem(size: scaled(19, pad: 23), weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            HStack {
                Spacer()
                guideButton(title: "OK", action: onStart, height: isPadLayout ? 58 : 52)
                Spacer()
            }
            .padding(.top, 12)
        }
    }

    private var introBoardPreview: some View {
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
                            RoundedRectangle(cornerRadius: cellCorner, style: .continuous)
                                .fill(NeumorphicColors.background)
                                .overlay(
                                    RoundedRectangle(cornerRadius: cellCorner, style: .continuous)
                                        .stroke(Color(hex: "E2DAD0"), lineWidth: 1)
                                )
                                .overlay {
                                    if !cell.text.isEmpty {
                                        Text(cell.text)
                                            .font(.appSystem(size: scaled(16, pad: 18), weight: .bold, design: .rounded))
                                            .foregroundColor(NeumorphicColors.text)
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

    private func milestoneContent(_ milestone: FirstStepGuideStore.OverlayPresentation.Milestone) -> some View {
        VStack(spacing: 20) {
            Image(milestone.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: isPadLayout ? 240 : 188)

            Text(milestone.message)
                .font(.appSystem(size: scaled(21, pad: 29), weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
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

            HStack(spacing: 10) {
                ForEach(presentation.seedTasks, id: \.self) { task in
                    VStack(spacing: 12) {
                        Text(task)
                            .font(.appSystem(size: scaled(15, pad: 17), weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.appSystem(size: scaled(22, pad: 24), weight: .bold))
                            .foregroundColor(.white.opacity(0.96))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: isPadLayout ? 128 : 106)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: "D3A375"))
                    )
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
                    .foregroundColor(Color(hex: "F5C164"))
                    .offset(x: 10, y: -10)
            }
            .overlay(alignment: .bottomLeading) {
                Image(systemName: "sparkles")
                    .font(.appSystem(size: scaled(16, pad: 18), weight: .bold))
                    .foregroundColor(Color(hex: "F5C164"))
                    .offset(x: -10, y: 10)
            }

            Text(milestone.message)
                .font(.appSystem(size: scaled(21, pad: 29), weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            guideButton(title: "OK", action: onDismiss, height: isPadLayout ? 60 : 52)
                .padding(.top, 10)
        }
        .frame(maxWidth: 520)
    }

    private func guideButton(title: String, action: @escaping () -> Void, height: CGFloat) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: scaled(14, pad: 18), weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: isPadLayout ? 300 : 220)
                .frame(height: height)
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
        .frame(width: isPadLayout ? 300 : 220, height: height)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }
}
