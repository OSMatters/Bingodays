import SwiftUI

struct SidebarMenuRow: View {
    let icon: String
    let title: String
    let isPadLayout: Bool
    var trailingIcon: String = "chevron.right"
    var trailingRotation: Double = 0

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                .foregroundColor(NeumorphicColors.accent)
                .frame(width: isPadLayout ? 44 : 40, height: isPadLayout ? 44 : 40)
                .neumorphicConvex(radius: isPadLayout ? 22 : 20)

            Text(title)
                .font(.appSystem(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            Spacer()

            Image(systemName: trailingIcon)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold))
                .foregroundColor(NeumorphicColors.text.opacity(0.42))
                .rotationEffect(.degrees(trailingRotation))
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct SidebarToggleRowView: View {
    let title: String
    @Binding var isOn: Bool
    let isPadLayout: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.78))

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(SidebarGlassToggleStyle())
        }
        .sidebarListRow()
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct SidebarDisclosureRow: View {
    let title: String
    let isExpanded: Bool
    let isPadLayout: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 14) {
                Text(title)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundColor(NeumorphicColors.accent)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .buttonStyle(.plain)
        .sidebarListRow()
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct SidebarWidgetGuideTextRow: View {
    let isPadLayout: Bool

    var body: some View {
        Text(L10n.homeWidgetInstructions)
            .font(.appSystem(size: scaled(12.5, pad: 14.5), weight: .medium, design: .rounded))
            .foregroundColor(NeumorphicColors.text.opacity(0.6))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .listRowInsets(EdgeInsets(top: 2, leading: 22, bottom: 12, trailing: 22))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct SidebarStreakHeroView: View {
    let streakDays: Int
    let themeColor: Color
    let isPadLayout: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(streakDays)")
                    .font(.appSystem(size: scaled(40, pad: 52), weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                themeColor.opacity(0.72),
                                themeColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, 10)

                Text(L10n.dayStreak)
                    .font(.appSystem(size: scaled(16, pad: 19), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
            }

            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(themeColor.opacity(0.24))
                    .frame(width: 64, height: 64)
                    .blur(radius: 8)

                Image(systemName: "flame.fill")
                    .font(.appSystem(size: scaled(44, pad: 54), weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                themeColor.opacity(0.42),
                                themeColor.opacity(0.76),
                                themeColor
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: themeColor.opacity(0.34), radius: 10, x: 0, y: 6)
            }
            .frame(width: isPadLayout ? 90 : 78, height: isPadLayout ? 90 : 78)
        }
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 18, leading: 22, bottom: 10, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

struct SidebarStreakGoalsView: View {
    let streakDays: Int
    let goals: [Int]
    let themeColor: Color
    let isPadLayout: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.streakGoals)
                .font(.appSystem(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            HStack(alignment: .center, spacing: 8) {
                ForEach(Array(goals.enumerated()), id: \.offset) { index, goal in
                    streakGoalNode(goal: goal, previousGoal: index == 0 ? 0 : goals[index - 1])

                    if index < goals.count - 1 {
                        streakConnector(from: goal, to: goals[index + 1])
                            .frame(maxWidth: .infinity)
                            .frame(height: 10)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(NeumorphicColors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(themeColor.opacity(0.5), lineWidth: 1)
                )
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 22, bottom: 14, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func streakConnector(from startGoal: Int, to endGoal: Int) -> some View {
        let fillProgress = streakConnectorProgress(from: startGoal, to: endGoal)

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(NeumorphicColors.darkShadow.opacity(0.22))
                .frame(height: 8)

            GeometryReader { geo in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                themeColor.opacity(0.45),
                                themeColor
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)
                    .frame(width: geo.size.width * fillProgress)
            }
        }
    }

    private func streakGoalNode(goal: Int, previousGoal: Int) -> some View {
        let isAchieved = streakDays >= goal
        let isCurrent = !isAchieved && streakDays >= previousGoal

        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isAchieved
                    ? themeColor.opacity(0.18)
                    : NeumorphicColors.background.opacity(isCurrent ? 0.96 : 0.92)
                )
                .frame(width: 44, height: 48)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isAchieved ? themeColor.opacity(0.72) : themeColor.opacity(isCurrent ? 0.2 : 0.12))
                        .frame(width: 34, height: 10)
                        .padding(.top, 4)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isAchieved
                                ? themeColor.opacity(0.9)
                                : themeColor.opacity(isCurrent ? 0.62 : 0.42),
                            lineWidth: 1.2
                        )
                }
                .overlay(alignment: .top) {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color.white.opacity(0.75))
                            .frame(width: 4, height: 4)
                        Circle()
                            .fill(Color.white.opacity(0.75))
                            .frame(width: 4, height: 4)
                    }
                    .padding(.top, 7)
                }
                .overlay {
                    Rectangle()
                        .fill(themeColor.opacity(isCurrent ? 0.22 : 0.14))
                        .frame(width: 28, height: 1)
                        .offset(y: -6)
                }

            Text("\(goal)")
                .font(.appSystem(size: scaled(16, pad: 18), weight: .bold, design: .rounded))
                .foregroundColor(isAchieved ? themeColor : NeumorphicColors.text.opacity(isCurrent ? 0.86 : 0.78))
                .padding(.top, 10)
        }
        .frame(width: 44, height: 48)
    }

    private func streakConnectorProgress(from startGoal: Int, to endGoal: Int) -> CGFloat {
        if streakDays >= endGoal {
            return 1
        }
        if streakDays <= startGoal {
            return 0
        }

        let progress = CGFloat(streakDays - startGoal) / CGFloat(max(endGoal - startGoal, 1))
        return min(max(progress, 0), 1)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

private extension View {
    func sidebarListRow() -> some View {
        listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
