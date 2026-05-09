import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins
import Photos

struct BoardTemplateShareComposerView: View {
    let template: BoardTemplatePayload

    @Environment(\.dismiss) private var dismiss
    @State private var titleDraft: String
    @State private var actionMessage: String?
    @State private var actionMessageToken = UUID()

    init(template: BoardTemplatePayload) {
        self.template = template
        _titleDraft = State(initialValue: template.normalizedTitle)
    }

    private var composedTemplate: BoardTemplatePayload {
        var updated = template
        updated.title = String(titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        return updated
    }

    private var qrCodeImage: UIImage? {
        let urlString = composedTemplate.qrCodeURL.absoluteString
        return BoardTemplateQRCodeGenerator.makeImage(from: urlString, size: 360)
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(348.0, max(geo.size.width - 42.0, 300))
            let cardScale = cardWidth / 348.0

            ZStack {
                Image("BlackBG")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.appSystem(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text(L10n.templateShareSheetTitle)
                            .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        Color.clear
                            .frame(width: 32, height: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, max(8, geo.safeAreaInsets.top))
                    .padding(.bottom, 8)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            ZStack(alignment: .topTrailing) {
                                TemplateShareFigmaCardView(
                                    template: composedTemplate,
                                    qrCodeImage: qrCodeImage,
                                    cardWidth: cardWidth,
                                    isTitleEditable: true,
                                    editableTitle: $titleDraft
                                )

                                Image("TemplateShareBear")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 132 * cardScale, height: 122 * cardScale)
                                    .offset(x: -4, y: -52 * cardScale)
                            }
                            .frame(width: cardWidth + 24, height: cardWidth + 235 * cardScale)
                            .padding(.horizontal, 12)

                            TemplateShareFigmaActionButton(
                                title: L10n.templateShareSaveImage,
                                systemName: "square.and.arrow.down",
                                action: {
                                    saveShareImageToPhotoLibrary()
                                }
                            )
                            .padding(.horizontal, 24)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, max(16, geo.safeAreaInsets.bottom + 10))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let actionMessage {
                    Text(actionMessage)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.45))
                        )
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 16) + 28)
                        .id(actionMessageToken)
                }
            }
            .onChange(of: titleDraft) { _, newValue in
                if newValue.count > 20 {
                    titleDraft = String(newValue.prefix(20))
                }
            }
        }
    }

    @MainActor
    private func saveShareImageToPhotoLibrary() {
        let preparedTemplate = composedTemplate
        guard let image = renderedShareImage(for: preparedTemplate) else {
            showActionMessage(L10n.templateShareImageSaveFailed)
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    showActionMessage(L10n.templateShareImageSaveDenied)
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { saved, _ in
                Task { @MainActor in
                    showActionMessage(saved ? L10n.templateShareImageSaved : L10n.templateShareImageSaveFailed)
                }
            }
        }
    }

    @MainActor
    private func renderedShareImage(for template: BoardTemplatePayload) -> UIImage? {
        BoardTemplateShareRenderer.renderCard(for: template)
    }

    @MainActor
    private func showActionMessage(_ message: String) {
        let token = UUID()
        actionMessage = message
        actionMessageToken = token
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                guard actionMessageToken == token else { return }
                actionMessage = nil
            }
        }
    }
}

private struct TemplateShareFigmaActionButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.appSystem(size: 17, weight: .semibold))
                Text(title)
                    .font(.appSystem(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "C39060"), Color(hex: "D3A375")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TemplateShareFigmaBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                watermarkColumn(in: geo.size, xOffset: -52)
                watermarkColumn(in: geo.size, xOffset: geo.size.width - 52)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func watermarkColumn(in size: CGSize, xOffset: CGFloat) -> some View {
        ForEach(0..<5, id: \.self) { index in
            Text("BINGODAYS")
                .font(.custom("Outfit", size: 62))
                .fontWeight(.heavy)
                .foregroundColor(.white.opacity(max(0.04, 0.22 - (Double(index) * 0.04))))
                .rotationEffect(.degrees(10.25))
                .offset(
                    x: xOffset,
                    y: -70 + CGFloat(index) * 52
                )
        }
    }
}

private struct TemplateShareFigmaCardView: View {
    let template: BoardTemplatePayload
    let qrCodeImage: UIImage?
    let cardWidth: CGFloat
    let isTitleEditable: Bool
    @Binding var editableTitle: String

    @FocusState private var isTitleFieldFocused: Bool
    @State private var isEditingTitle = false

    private var titleText: String {
        let source = isTitleEditable ? editableTitle : template.normalizedTitle
        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? L10n.templateShareNamePlaceholder : String(normalized.prefix(20))
    }

    private var scale: CGFloat {
        cardWidth / 348.0
    }

    private var cardHeight: CGFloat {
        cardWidth * (828.0 / 562.0)
    }

    var body: some View {
        let gridFrameWidth = cardWidth - (50 * scale)

        VStack(alignment: .leading, spacing: 14 * scale) {
            if isTitleEditable && isEditingTitle {
                TextField(L10n.templateShareNamePlaceholder, text: $editableTitle)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .font(.appSystem(size: 24 * scale, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "3F270F"))
                    .focused($isTitleFieldFocused)
                    .padding(.leading, 20 * scale)
                    .onSubmit {
                        isEditingTitle = false
                    }
            } else {
                Text(titleText)
                    .font(.appSystem(size: 24 * scale, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "3F270F"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.leading, 20 * scale)
                    .onTapGesture(count: 2) {
                        guard isTitleEditable else { return }
                        isEditingTitle = true
                        DispatchQueue.main.async {
                            isTitleFieldFocused = true
                        }
                    }
            }

            BoardTemplateGridPreview(
                template: template,
                tileBackground: Color(hex: "E7D5C4"),
                textColor: Color(hex: "3F270F"),
                isPreview: true,
                previewTextSize: 18 * scale
            )
            .frame(width: gridFrameWidth)
            .aspectRatio(1, contentMode: .fit)
            .offset(x: 10 * scale, y: 15 * scale)

            HStack(alignment: .top, spacing: 12 * scale) {
                Group {
                    if let qrCodeImage {
                        Image(uiImage: qrCodeImage)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                            .fill(Color(hex: "E7D5C4"))
                    }
                }
                .frame(width: 82 * scale, height: 82 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous))

                Text(L10n.templateShareFooterSubtitle)
                    .font(.appSystem(size: 14 * scale, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "8A5F34"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6 * scale)
                    .offset(y: 1 * scale)
            }
            .frame(width: gridFrameWidth, alignment: .leading)
            .offset(x: 10 * scale, y: 20 * scale)
        }
        .padding(.top, 18 * scale)
        .padding(.horizontal, 14 * scale)
        .padding(.bottom, 16 * scale)
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .background(
            Image("ShareTemplateCardBG")
                .resizable()
                .renderingMode(.original)
                .frame(width: cardWidth, height: cardHeight)
        )
        .onChange(of: isTitleFieldFocused) { _, focused in
            if !focused {
                isEditingTitle = false
            }
        }
        .onChange(of: editableTitle) { _, newValue in
            if newValue.count > 20 {
                editableTitle = String(newValue.prefix(20))
            }
        }
    }
}

struct BoardTemplateImportPreviewView: View {
    let template: BoardTemplatePayload
    let createsNewBoard: Bool
    let onImport: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                BoardTemplateShareCardView(
                    template: template,
                    qrCodeImage: nil,
                    isPreview: true,
                    showsFooterCopy: false
                )

                if !createsNewBoard {
                    Text(L10n.templateImportFreePlanHint)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.58))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NeumorphicColors.background)
            .navigationTitle(L10n.templateImportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { onClose() }
                        .foregroundColor(NeumorphicColors.text.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.templateImportAction) {
                        onImport()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }
            }
        }
    }
}

struct BoardTemplateShareCardView: View {
    let template: BoardTemplatePayload
    let qrCodeImage: UIImage?
    let isPreview: Bool
    let isTitleEditable: Bool
    let showsFooterCopy: Bool
    @Binding var editableTitle: String

    @FocusState private var isTitleFieldFocused: Bool
    @State private var isEditingTitle = false

    private var cardBackground: Color { Color(hex: "F5EDE4") }
    private var tileBackground: Color { Color(hex: "FFF9F2") }
    private var previewWidth: CGFloat { isPreview ? 340 : 1080 }
    private var previewPadding: CGFloat { isPreview ? 18 : 56 }
    private var titleText: String {
        let source = isTitleEditable ? editableTitle : template.normalizedTitle
        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? L10n.templateShareNamePlaceholder : String(normalized.prefix(20))
    }

    init(
        template: BoardTemplatePayload,
        qrCodeImage: UIImage?,
        isPreview: Bool,
        isTitleEditable: Bool = false,
        showsFooterCopy: Bool = true,
        editableTitle: Binding<String> = .constant("")
    ) {
        self.template = template
        self.qrCodeImage = qrCodeImage
        self.isPreview = isPreview
        self.isTitleEditable = isTitleEditable
        self.showsFooterCopy = showsFooterCopy
        _editableTitle = editableTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isPreview ? 16 : 36) {
            VStack(alignment: .leading, spacing: isPreview ? 8 : 18) {
                if isTitleEditable && isEditingTitle {
                    TextField(L10n.templateShareNamePlaceholder, text: $editableTitle)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .font(.appSystem(size: isPreview ? 24 : 70, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "3B2411"))
                        .focused($isTitleFieldFocused)
                        .onSubmit {
                            isEditingTitle = false
                        }
                } else {
                    Text(titleText)
                        .font(.appSystem(size: isPreview ? 24 : 70, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "3B2411"))
                        .lineLimit(2)
                        .onTapGesture(count: 2) {
                            guard isTitleEditable else { return }
                            isEditingTitle = true
                            DispatchQueue.main.async {
                                isTitleFieldFocused = true
                            }
                        }
                }
            }

            BoardTemplateGridPreview(
                template: template,
                tileBackground: tileBackground,
                textColor: Color(hex: "4A3423"),
                isPreview: isPreview
            )

            if qrCodeImage != nil || showsFooterCopy {
                HStack(alignment: .center, spacing: isPreview ? 14 : 28) {
                    if let qrCodeImage {
                        Image(uiImage: qrCodeImage)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: isPreview ? 88 : 220, height: isPreview ? 88 : 220)
                            .clipShape(RoundedRectangle(cornerRadius: isPreview ? 18 : 28, style: .continuous))
                    }

                    if showsFooterCopy {
                        VStack(alignment: .leading, spacing: isPreview ? 6 : 12) {
                            Text(L10n.templateShareFooterTitle)
                                .font(.appSystem(size: isPreview ? 16 : 34, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "3B2411"))

                            Text(L10n.templateShareFooterSubtitle)
                                .font(.appSystem(size: isPreview ? 12 : 24, weight: .medium, design: .rounded))
                                .foregroundColor(Color(hex: "7D6149"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(previewPadding)
        .frame(width: previewWidth)
        .background(
            RoundedRectangle(cornerRadius: isPreview ? 28 : 64, style: .continuous)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: isPreview ? 28 : 64, style: .continuous)
                        .stroke(Color.white.opacity(0.6), lineWidth: isPreview ? 1 : 3)
                )
                .shadow(color: Color(hex: "C7AA8B").opacity(0.28), radius: isPreview ? 18 : 36, x: 0, y: isPreview ? 10 : 20)
        )
        .onChange(of: isTitleFieldFocused) { _, focused in
            if !focused {
                isEditingTitle = false
            }
        }
        .onChange(of: editableTitle) { _, newValue in
            if newValue.count > 20 {
                editableTitle = String(newValue.prefix(20))
            }
        }
    }
}

struct BoardTemplateGridPreview: View {
    let template: BoardTemplatePayload
    let tileBackground: Color
    let textColor: Color
    let isPreview: Bool
    var previewTextSize: CGFloat = 12

    private var gridSpacing: CGFloat {
        switch template.gridSize {
        case ...3: return 15
        case 4: return 10
        default: return 8
        }
    }

    private var paddedTiles: [BoardTemplateTile] {
        let requiredTiles = template.gridSize * template.gridSize
        return Array(template.tiles.prefix(requiredTiles)) + Array(
            repeating: BoardTemplateTile(text: ""),
            count: max(requiredTiles - template.tiles.count, 0)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let columnsCount = max(template.gridSize, 1)
            let totalSpacing = gridSpacing * CGFloat(columnsCount - 1)
            let cellSize = max((proxy.size.width - totalSpacing) / CGFloat(columnsCount), 0)
            let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: gridSpacing), count: columnsCount)

            LazyVGrid(columns: columns, spacing: gridSpacing) {
                ForEach(Array(paddedTiles.enumerated()), id: \.offset) { _, tile in
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(tileBackground)
                            .shadow(color: Color.white.opacity(0.52), radius: isPreview ? 5 : 12, x: -2, y: -2)
                            .shadow(color: Color(hex: "D9C5B4").opacity(0.42), radius: isPreview ? 6 : 14, x: 3, y: 3)

                        Text(tile.trimmedText.isEmpty ? " " : tile.trimmedText)
                            .font(.appSystem(size: isPreview ? previewTextSize : 28, weight: .semibold, design: .rounded))
                            .foregroundColor(textColor)
                            .multilineTextAlignment(.center)
                            .lineLimit(isPreview ? 3 : 4)
                            .padding(isPreview ? 8 : 18)
                    }
                    .frame(width: cellSize, height: cellSize, alignment: .center)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

enum BoardTemplateShareRenderer {
    @MainActor
    static func renderCard(for template: BoardTemplatePayload) -> UIImage? {
        let canvasSize = CGSize(width: 1440, height: 2560)
        let qrCodeImage = BoardTemplateQRCodeGenerator.makeImage(
            from: template.qrCodeURL.absoluteString,
            size: 1400
        )

        let content = TemplateShareExportPosterView(
            template: template,
            qrCodeImage: qrCodeImage,
            canvasSize: canvasSize
        )
        .frame(width: canvasSize.width, height: canvasSize.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: canvasSize.width, height: canvasSize.height)
        guard let rendered = renderer.uiImage else { return nil }
        return compositedShareLogo(on: rendered)
    }

    @MainActor
    private static func compositedShareLogo(on image: UIImage) -> UIImage {
        guard let logo = UIImage(named: "ShareLogo"), image.size.width > 0, image.size.height > 0 else {
            return image
        }

        let canvas = image.size
        let targetWidth = canvas.width * 0.24
        let targetHeight = targetWidth * (logo.size.height / max(logo.size.width, 1))
        let logoX = (canvas.width - targetWidth) * 0.5
        let logoY = canvas.height - targetHeight - 88
        let logoRect = CGRect(x: logoX, y: max(logoY, 0), width: targetWidth, height: targetHeight)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: canvas))
            logo.draw(in: logoRect)
        }
    }
}

private struct TemplateShareExportPosterView: View {
    let template: BoardTemplatePayload
    let qrCodeImage: UIImage?
    let canvasSize: CGSize

    private var cardWidth: CGFloat {
        canvasSize.width - 120
    }

    var body: some View {
        ZStack {
            Image("BlackBG")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 88)

                ZStack(alignment: .topTrailing) {
                    TemplateShareFigmaCardView(
                        template: template,
                        qrCodeImage: qrCodeImage,
                        cardWidth: cardWidth,
                        isTitleEditable: false,
                        editableTitle: .constant("")
                    )

                    Image("TemplateShareBear")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 132 * (cardWidth / 348.0), height: 122 * (cardWidth / 348.0))
                        .offset(x: -4, y: -52 * (cardWidth / 348.0))
                }
                .frame(width: cardWidth + 24, height: cardWidth + 235 * (cardWidth / 348.0))

                Spacer(minLength: 0)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}

enum BoardTemplateQRCodeGenerator {
    static func makeImage(from string: String, size: CGFloat) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.correctionLevel = "L"

        guard let outputImage = filter.outputImage else { return nil }

        let falseColorFilter = CIFilter.falseColor()
        falseColorFilter.inputImage = outputImage
        falseColorFilter.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        falseColorFilter.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        guard let coloredImage = falseColorFilter.outputImage else { return nil }

        let quietZone = max(size * 0.14, 18)
        let qrSideLength = max(size - (quietZone * 2), size * 0.7)
        let scaleX = qrSideLength / coloredImage.extent.width
        let scaleY = qrSideLength / coloredImage.extent.height
        let transformed = coloredImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: rendererFormat)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: size, height: size)))
            context.cgContext.interpolationQuality = .none
            context.cgContext.setShouldAntialias(false)

            let drawRect = CGRect(
                x: quietZone,
                y: quietZone,
                width: qrSideLength,
                height: qrSideLength
            )
            context.cgContext.draw(cgImage, in: drawRect.integral)
        }
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}
