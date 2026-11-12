import Combine
import Foundation

@MainActor
final class BoardSharePresentationStore: ObservableObject {
    enum Page: Equatable {
        case menu
        case selectBoard
        case shareResult(BoardSharePublishResult)
        case importCode
        case importPreview(BoardShareLookup)
    }

    @Published private(set) var page: Page = .menu
    @Published var codeDraft = ""
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?

    private let serviceFactory: () -> any BoardShareServicing
    private var service: (any BoardShareServicing)?
    private var operationTask: Task<Void, Never>?
    private var operationID = UUID()

    init(
        serviceFactory: @escaping () -> any BoardShareServicing = BoardShareServiceFactory.makeDefaultService
    ) {
        self.serviceFactory = serviceFactory
    }

    deinit {
        operationTask?.cancel()
    }

    func showMenu() {
        cancelPendingOperation()
        errorMessage = nil
        page = .menu
    }

    func showShareBoardPicker() {
        cancelPendingOperation()
        errorMessage = nil
        page = .selectBoard
    }

    func showImportCodeEntry() {
        cancelPendingOperation()
        errorMessage = nil
        codeDraft = ""
        page = .importCode
    }

    func normalizeCodeDraft() {
        codeDraft = String(BoardShareCode.normalized(codeDraft).prefix(BoardShareCode.length))
    }

    @discardableResult
    func publish(_ board: BingoBoardStore.NamedBoard) -> Task<Void, Never>? {
        cancelPendingOperation()
        guard BoardSharePayload.isShareable(board.board) else {
            AnalyticsService.logBoardSharePublishResult(
                result: "not_shareable",
                payload: nil
            )
            errorMessage = L10n.tr(
                "Add a task before sharing this board.",
                zhHans: "添加任务后才能分享这个棋盘",
                zhHant: "新增任務後才能分享這個棋盤"
            )
            return nil
        }

        let id = beginOperation()
        let service = resolvedService()
        operationTask = Task { [weak self, service] in
            do {
                let result = try await service.publish(board: board, now: .now)
                guard let self, self.operationID == id, !Task.isCancelled else { return }
                AnalyticsService.logBoardSharePublishResult(result: "success", payload: result.payload)
                self.page = .shareResult(result)
                self.finishOperation(id)
            } catch {
                guard let self, self.operationID == id, !Task.isCancelled else { return }
                AnalyticsService.logBoardSharePublishResult(result: AnalyticsService.boardShareErrorResult(error), payload: nil)
                self.errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? L10n.tr("Could not share this board. Please try again.", zhHans: "分享失败，请重试", zhHant: "分享失敗，請重試")
                self.finishOperation(id)
            }
        }
        return operationTask
    }

    @discardableResult
    func lookupCode() -> Task<Void, Never>? {
        cancelPendingOperation()
        normalizeCodeDraft()
        guard BoardShareCode.isValid(codeDraft) else {
            AnalyticsService.logBoardImportLookupResult(result: "invalid_code")
            errorMessage = BoardShareError.invalidCode.errorDescription
            return nil
        }

        let id = beginOperation()
        let service = resolvedService()
        let code = codeDraft
        operationTask = Task { [weak self, service] in
            do {
                let lookup = try await service.lookup(code: code, now: .now)
                guard let self, self.operationID == id, !Task.isCancelled else { return }
                AnalyticsService.logBoardImportLookupResult(result: "success", payload: lookup.payload)
                self.codeDraft = lookup.code
                self.page = .importPreview(lookup)
                self.finishOperation(id)
            } catch {
                guard let self, self.operationID == id, !Task.isCancelled else { return }
                AnalyticsService.logBoardImportLookupResult(result: AnalyticsService.boardShareErrorResult(error))
                self.errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? L10n.tr("Could not find this board. Please try again.", zhHans: "查找棋盘失败，请重试", zhHant: "查找棋盤失敗，請重試")
                self.finishOperation(id)
            }
        }
        return operationTask
    }

    func cancelPendingOperation() {
        operationID = UUID()
        operationTask?.cancel()
        operationTask = nil
        isWorking = false
    }

    private func beginOperation() -> UUID {
        cancelPendingOperation()
        isWorking = true
        errorMessage = nil
        return operationID
    }

    private func finishOperation(_ id: UUID) {
        guard operationID == id else { return }
        isWorking = false
        operationTask = nil
    }

    func savePendingPremiumImport(_ lookup: BoardShareLookup) {
        BoardSharePendingImportStore.save(code: lookup.code, payload: lookup.payload)
    }

    func restorePendingPremiumImport() -> Bool {
        guard let pending = BoardSharePendingImportStore.load() else { return false }
        cancelPendingOperation()
        codeDraft = pending.code
        errorMessage = nil
        page = .importPreview(BoardShareLookup(code: pending.code, payload: pending.payload))
        return true
    }

    func clearPendingPremiumImport() {
        BoardSharePendingImportStore.clear()
    }

    private func resolvedService() -> any BoardShareServicing {
        if let service {
            return service
        }

        let service = serviceFactory()
        self.service = service
        return service
    }
}
