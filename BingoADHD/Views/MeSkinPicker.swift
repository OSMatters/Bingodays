import SwiftUI

struct MeSkinPicker: View {
    let selection: MeSkin
    @Binding var isExpanded: Bool
    let onSelect: (MeSkin) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focusedTheme: MeSkin?

    var body: some View {
        Button {
            AppHaptics.control()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
            if isExpanded { focusedTheme = selection }
        } label: {
            HStack(spacing: 12) {
                icon(for: selection)
                    .frame(width: 27, height: 27)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(selection.controlTextColor.opacity(0.6))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .frame(width: 76, height: 30)
            .appLiquidGlass(
                in: Capsule(),
                fallbackWhiteOpacity: 0.18,
                fallbackShowsBorder: false,
                usesClearGlass: true
            )
            .environment(\.colorScheme, selection.isDarkBackground ? .dark : .light)
            .frame(width: 76, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr("Choose Me theme", zhHans: "选择我的页面主题", zhHant: "選擇我的頁面主題", ja: "マイページのテーマを選択", ko: "내 페이지 테마 선택"))
        .accessibilityValue(selection.title)
        .accessibilityIdentifier("me.themePicker")
        .overlay(alignment: .topLeading) {
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(MeSkin.allCases) { skin in
                        Button {
                            onSelect(skin)
                        } label: {
                            HStack(spacing: 6) {
                                icon(for: skin)
                                    .frame(width: 30, height: 30)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(selection.controlTextColor)
                                    .opacity(selection == skin ? 1 : 0)
                            }
                            .frame(width: 76, height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(skin.title)
                        .accessibilityAddTraits(selection == skin ? .isSelected : [])
                        .accessibilityIdentifier("me.theme.\(skin.rawValue)")
                        .accessibilityFocused($focusedTheme, equals: skin)
                    }
                }
                .padding(.vertical, 5)
                .appLiquidGlass(
                    in: RoundedRectangle(cornerRadius: 24),
                    interactive: false,
                    fallbackWhiteOpacity: 0.18,
                    fallbackShowsBorder: false,
                    usesClearGlass: true
                )
                .environment(\.colorScheme, selection.isDarkBackground ? .dark : .light)
                .offset(y: 44)
                .transition(.opacity)
            }
        }
        .accessibilityAction(.escape) { isExpanded = false }
    }

    private func icon(for skin: MeSkin) -> some View {
        Image(skin.pickerImageName)
            .resizable()
            .interpolation(.high)
            .renderingMode(.original)
            .scaledToFit()
            .accessibilityHidden(true)
    }
}
