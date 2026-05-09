import Foundation

@MainActor
final class TemplateImportFlowStore: ObservableObject {
    @Published var previewTemplate: BoardTemplatePayload?
    @Published var isPreviewPresented = false
    @Published var pageOpenSource = "unknown"

    func resolveTemplate(from rawText: String) -> BoardTemplatePayload? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let directURL = URL(string: trimmed),
           let template = BoardTemplatePayload.decode(from: directURL) {
            return template
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let matches = detector.matches(
            in: rawText,
            options: [],
            range: NSRange(location: 0, length: rawText.utf16.count)
        )

        for match in matches {
            guard let url = match.url else { continue }
            if let template = BoardTemplatePayload.decode(from: url) {
                return template
            }
        }
        return nil
    }

    func presentPreview(
        template: BoardTemplatePayload,
        source: String,
        createsNewBoard: Bool
    ) {
        pageOpenSource = source
        AnalyticsService.logTemplateImportPageOpen(
            source: source,
            gridSize: template.gridSize,
            createsNewBoard: createsNewBoard
        )
        previewTemplate = template
        isPreviewPresented = true
    }

    func dismissPreview() {
        isPreviewPresented = false
        previewTemplate = nil
    }

    func clearPreviewIfNotPresented() {
        if !isPreviewPresented {
            previewTemplate = nil
        }
    }

    func logImportSuccess(template: BoardTemplatePayload, createsNewBoard: Bool) {
        AnalyticsService.logTemplateImportSuccess(
            source: pageOpenSource,
            gridSize: template.gridSize,
            createsNewBoard: createsNewBoard
        )
    }
}
