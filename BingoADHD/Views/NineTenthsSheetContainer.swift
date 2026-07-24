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

private struct PadBottomHalfSheetLayer<SheetContent: View>: View {
    let isPresented: Bool
    let backgroundColor: Color
    let contentMaxWidth: CGFloat
    let maximumHeight: CGFloat?
    let heightFraction: CGFloat
    let onDismiss: () -> Void
    let sheetContent: SheetContent

    @GestureState private var dragOffset: CGFloat = 0

    init(
        isPresented: Bool,
        backgroundColor: Color,
        contentMaxWidth: CGFloat,
        maximumHeight: CGFloat?,
        heightFraction: CGFloat = 0.5,
        onDismiss: @escaping () -> Void,
        @ViewBuilder sheetContent: () -> SheetContent
    ) {
        self.isPresented = isPresented
        self.backgroundColor = backgroundColor
        self.contentMaxWidth = contentMaxWidth
        self.maximumHeight = maximumHeight
        self.heightFraction = heightFraction
        self.onDismiss = onDismiss
        self.sheetContent = sheetContent()
    }

    var body: some View {
        GeometryReader { geo in
            let resolvedHeightFraction = min(max(heightFraction, 0), 1)
            let proposedHeight = geo.size.height * resolvedHeightFraction

            ZStack(alignment: .bottom) {
                if isPresented {
                    Color.black.opacity(0.18)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onDismiss)
                        .transition(.opacity)

                    VStack(spacing: 0) {
                        Capsule(style: .continuous)
                            .fill(NeumorphicColors.text.opacity(0.22))
                            .frame(width: 54, height: 6)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .contentShape(Rectangle())
                            .gesture(dismissDragGesture)

                        sheetContent
                            .frame(maxWidth: min(contentMaxWidth, geo.size.width), maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(
                        height: min(proposedHeight, maximumHeight ?? proposedHeight),
                        alignment: .top
                    )
                    .background(backgroundColor)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 28,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 28,
                            style: .continuous
                        )
                    )
                    .overlay(alignment: .top) {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 28,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 28,
                            style: .continuous
                        )
                        .stroke(NeumorphicColors.lightShadow.opacity(0.38), lineWidth: 1)
                    }
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.18), radius: 18, x: 0, y: -3)
                    .offset(y: dragOffset)
                    .transition(.move(edge: .bottom))
                    .accessibilityAddTraits(.isModal)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(isPresented)
        .animation(.easeInOut(duration: 0.22), value: isPresented)
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($dragOffset) { value, state, _ in
                state = max(value.translation.height, 0)
            }
            .onEnded { value in
                if value.translation.height > 80 || value.predictedEndTranslation.height > 150 {
                    onDismiss()
                }
            }
    }
}

private struct AdaptivePadBottomHalfSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let usePadPresentation: Bool
    let backgroundColor: Color
    let contentMaxWidth: CGFloat
    let maximumPadHeight: CGFloat?
    let padHeightFraction: CGFloat
    let onDismiss: () -> Void
    let sheetContent: () -> SheetContent

    @ViewBuilder
    func body(content: Content) -> some View {
        if usePadPresentation {
            content
                .overlay {
                    PadBottomHalfSheetLayer(
                        isPresented: isPresented,
                        backgroundColor: backgroundColor,
                        contentMaxWidth: contentMaxWidth,
                        maximumHeight: maximumPadHeight,
                        heightFraction: padHeightFraction,
                        onDismiss: {
                            isPresented = false
                        },
                        sheetContent: sheetContent
                    )
                }
                .onChange(of: isPresented) { wasPresented, isNowPresented in
                    if wasPresented && !isNowPresented {
                        onDismiss()
                    }
                }
        } else {
            content
                .sheet(isPresented: $isPresented, onDismiss: onDismiss, content: sheetContent)
        }
    }
}

private struct AdaptivePadBottomHalfSheetItemModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    let usePadPresentation: Bool
    let backgroundColor: Color
    let contentMaxWidth: CGFloat
    let maximumPadHeight: CGFloat?
    let padHeightFraction: CGFloat
    let onDismiss: () -> Void
    let sheetContent: (Item) -> SheetContent

    @ViewBuilder
    func body(content: Content) -> some View {
        if usePadPresentation {
            content
                .fullScreenCover(item: $item, onDismiss: onDismiss) { presentedItem in
                    PadBottomHalfSheetLayer(
                        isPresented: true,
                        backgroundColor: backgroundColor,
                        contentMaxWidth: contentMaxWidth,
                        maximumHeight: maximumPadHeight,
                        heightFraction: padHeightFraction,
                        onDismiss: {
                            item = nil
                        }
                    ) {
                        sheetContent(presentedItem)
                    }
                    .presentationBackground(.clear)
                }
        } else {
            content
                .sheet(item: $item, onDismiss: onDismiss, content: sheetContent)
        }
    }
}

extension View {
    func adaptivePadBottomHalfSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        usePadPresentation: Bool,
        backgroundColor: Color,
        contentMaxWidth: CGFloat = 820,
        maximumPadHeight: CGFloat? = nil,
        padHeightFraction: CGFloat = 0.5,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(
            AdaptivePadBottomHalfSheetModifier(
                isPresented: isPresented,
                usePadPresentation: usePadPresentation,
                backgroundColor: backgroundColor,
                contentMaxWidth: contentMaxWidth,
                maximumPadHeight: maximumPadHeight,
                padHeightFraction: padHeightFraction,
                onDismiss: onDismiss,
                sheetContent: content
            )
        )
    }

    func adaptivePadBottomHalfSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        usePadPresentation: Bool,
        backgroundColor: Color,
        contentMaxWidth: CGFloat = 820,
        maximumPadHeight: CGFloat? = nil,
        padHeightFraction: CGFloat = 0.5,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        modifier(
            AdaptivePadBottomHalfSheetItemModifier(
                item: item,
                usePadPresentation: usePadPresentation,
                backgroundColor: backgroundColor,
                contentMaxWidth: contentMaxWidth,
                maximumPadHeight: maximumPadHeight,
                padHeightFraction: padHeightFraction,
                onDismiss: onDismiss,
                sheetContent: content
            )
        )
    }
}
