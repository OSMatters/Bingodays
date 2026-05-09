import SwiftUI

struct NineTenthsSheetContainer<Content: View>: View {
    let contentMaxWidth: CGFloat
    let content: Content

    init(contentMaxWidth: CGFloat = 920, @ViewBuilder content: () -> Content) {
        self.contentMaxWidth = contentMaxWidth
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Capsule(style: .continuous)
                        .fill(NeumorphicColors.text.opacity(0.22))
                        .frame(width: 54, height: 6)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    content
                        .frame(maxWidth: min(contentMaxWidth, geo.size.width - 32), maxHeight: .infinity)
                }
                .frame(
                    width: min(max(geo.size.width - 24, 0), contentMaxWidth + 32),
                    height: geo.size.height * 0.9,
                    alignment: .top
                )
                .background(NeumorphicColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(NeumorphicColors.lightShadow.opacity(0.42), lineWidth: 1)
                )
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.18), radius: 16, x: 0, y: -2)
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}
