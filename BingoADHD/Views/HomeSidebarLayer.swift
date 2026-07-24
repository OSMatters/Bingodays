import SwiftUI

struct HomeSidebarLayer: View {
    let canvasWidth: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let streakDays: Int
    let streakGoals: [Int]
    let themeColor: Color
    let isPadLayout: Bool
    let appShortVersion: String

    @Binding var isPresented: Bool
    @Binding var isSettingsExpanded: Bool
    @Binding var isWidgetGuideExpanded: Bool
    @Binding var isThemePickerExpanded: Bool
    @Binding var isHapticsEnabled: Bool
    @Binding var isSoundEffectsEnabled: Bool
    @Binding var themeRawValue: String

    let onOpenDiary: () -> Void
    let onOpenContact: () -> Void
    let onEncourageUs: () -> Void
    let onPresentPremiumPaywall: () -> Void

    private var sidebarWidth: CGFloat {
        isPadLayout ? min(canvasWidth * 0.42, 420) : min(canvasWidth * 0.8, 332)
    }

    private var hiddenOffset: CGFloat {
        -(isPadLayout ? min(canvasWidth * 0.42, 420) : min(canvasWidth * 0.8, 320))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if isPresented {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            isPresented = false
                        }
                    }
            }

            HomeSidebarView(
                width: sidebarWidth,
                topInset: topInset,
                bottomInset: bottomInset,
                streakDays: streakDays,
                streakGoals: streakGoals,
                themeColor: themeColor,
                isPadLayout: isPadLayout,
                appShortVersion: appShortVersion,
                isPresented: $isPresented,
                isSettingsExpanded: $isSettingsExpanded,
                isWidgetGuideExpanded: $isWidgetGuideExpanded,
                isThemePickerExpanded: $isThemePickerExpanded,
                isHapticsEnabled: $isHapticsEnabled,
                isSoundEffectsEnabled: $isSoundEffectsEnabled,
                themeRawValue: $themeRawValue,
                onOpenDiary: onOpenDiary,
                onOpenContact: onOpenContact,
                onEncourageUs: onEncourageUs,
                onPresentPremiumPaywall: onPresentPremiumPaywall
            )
            .offset(x: isPresented ? 0 : hiddenOffset)
            .allowsHitTesting(isPresented)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .allowsHitTesting(isPresented)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isPresented)
    }
}
