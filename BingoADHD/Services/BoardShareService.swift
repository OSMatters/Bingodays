import CloudKit
import Foundation

/// The public, versioned representation of a shared board.  It deliberately
/// contains template text only; it is not a serialization of `SavedBoard`.
struct BoardSharePayload: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let minimumGridSize = 2
    static let maximumGridSize = 5
    static let maximumCellCount = 25
    static let maximumCellTextLength = 20
    static let maximumBoardNameLength = 20
    static let maximumPayloadBytes = 24 * 1_024

    struct Cell: Codable, Equatable, Sendable {
        let row: Int
        let column: Int
        let text: String

        init(row: Int, column: Int, text: String) {
            self.row = row
            self.column = column
            self.text = text
        }
    }

    let schemaVersion: Int
    let boardName: String
    let gridSize: Int
    let sourceLanguage: String?
    let cells: [Cell]
    let createdAt: Date
    let expiresAt: Date

    init(
        schemaVersion: Int = BoardSharePayload.schemaVersion,
        boardName: String,
        gridSize: Int,
        sourceLanguage: String?,
        cells: [Cell],
        createdAt: Date,
        expiresAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.boardName = boardName
        self.gridSize = gridSize
        self.sourceLanguage = sourceLanguage
        self.cells = cells
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    init(
        board: BingoBoardStore.NamedBoard,
        sourceLanguage: String? = AppLanguage.current.rawValue,
        createdAt: Date = .now,
        expiresAt: Date? = nil
    ) throws {
        let size = board.board.gridSize
        let visibleCells = board.board.cells
        let templateCells = (0..<size).flatMap { row in
            (0..<size).map { column in
                Cell(
                    row: row,
                    column: column,
                    text: visibleCells[safe: row]?[safe: column]?.text ?? ""
                )
            }
        }
        self.init(
            boardName: board.name,
            gridSize: size,
            sourceLanguage: sourceLanguage,
            cells: templateCells,
            createdAt: createdAt,
            expiresAt: expiresAt ?? createdAt.addingTimeInterval(30 * 24 * 60 * 60)
        )
        try validate(now: createdAt)
    }

    func validate(now: Date = .now) throws {
        guard schemaVersion == Self.schemaVersion else {
            throw BoardShareError.unsupportedSchema
        }
        guard (Self.minimumGridSize...Self.maximumGridSize).contains(gridSize) else {
            throw BoardShareError.invalidPayload
        }
        let trimmedName = boardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= Self.maximumBoardNameLength else {
            throw BoardShareError.invalidPayload
        }
        guard cells.count <= Self.maximumCellCount,
              expiresAt > createdAt,
              expiresAt > now else {
            throw expiresAt <= now ? BoardShareError.expired : BoardShareError.invalidPayload
        }
        guard cells.contains(where: {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw BoardShareError.invalidPayload
        }

        var coordinates = Set<CellCoordinate>()
        for cell in cells {
            guard (0..<gridSize).contains(cell.row),
                  (0..<gridSize).contains(cell.column),
                  cell.text.count <= Self.maximumCellTextLength,
                  coordinates.insert(CellCoordinate(row: cell.row, column: cell.column)).inserted else {
                throw BoardShareError.invalidPayload
            }
        }

        guard let payloadData = try? JSONEncoder().encode(self),
              payloadData.count <= Self.maximumPayloadBytes else {
            throw BoardShareError.invalidPayload
        }
    }

    func makeNewLocalBoard() throws -> SavedBoard {
        try validate()

        var fullBoardCells = BoardEngine.createEmptyGrid(size: Self.maximumGridSize)
        for cell in cells {
            fullBoardCells[cell.row][cell.column] = BingoCell(text: cell.text)
        }
        let visibleCells = (0..<gridSize).map { row in
            Array(fullBoardCells[row].prefix(gridSize))
        }
        return SavedBoard(
            gridSize: gridSize,
            cells: visibleCells,
            completedLines: [],
            fullBoardCells: fullBoardCells
        )
    }

    static func isShareable(_ board: SavedBoard) -> Bool {
        board.cells.joined().contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private struct CellCoordinate: Hashable {
        let row: Int
        let column: Int
    }
}

enum BoardShareCode {
    static let length = 10

    static func generate() -> String {
        let randomDigits = (0..<9).map { index in
            let lowerBound = index == 0 ? 1 : 0
            return Int.random(in: lowerBound...9)
        }
        let body = randomDigits.map(String.init).joined()
        return body + String(checkDigit(for: body))
    }

    static func normalized(_ rawValue: String) -> String {
        rawValue.filter(\.isNumber)
    }

    static func isValid(_ rawValue: String) -> Bool {
        let code = normalized(rawValue)
        guard code.count == length,
              code.allSatisfy(\.isNumber) else {
            return false
        }
        let body = String(code.dropLast())
        guard let finalDigit = code.last?.wholeNumberValue else { return false }
        return checkDigit(for: body) == finalDigit
    }

    static func display(_ rawValue: String) -> String {
        let code = normalized(rawValue)
        guard code.count == length else { return code }
        let digits = Array(code)
        return [
            String(digits[0..<3]),
            String(digits[3..<6]),
            String(digits[6..<9]),
            String(digits[9..<10])
        ].joined(separator: " ")
    }

    private static func checkDigit(for body: String) -> Int {
        let sum = body.reversed().enumerated().reduce(0) { partial, element in
            guard let digit = element.element.wholeNumberValue else { return partial }
            let doubled = element.offset.isMultiple(of: 2) ? digit * 2 : digit
            return partial + (doubled > 9 ? doubled - 9 : doubled)
        }
        return (10 - (sum % 10)) % 10
    }
}

enum BoardShareError: LocalizedError, Equatable {
    case invalidCode
    case notFound
    case expired
    case unsupportedSchema
    case invalidPayload
    case accountUnavailable
    case networkUnavailable
    case unavailable
    case collisionLimitReached

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            return L10n.tr("Check the 10-digit code and try again.", zhHans: "请检查10位分享码后重试", zhHant: "請檢查10位分享碼後重試")
        case .notFound:
            return L10n.tr("No board was found for this code.", zhHans: "没有找到这个分享码对应的棋盘", zhHant: "沒有找到這個分享碼對應的棋盤")
        case .expired:
            return L10n.tr("This share code has expired.", zhHans: "该分享码已过期", zhHant: "該分享碼已過期")
        case .unsupportedSchema:
            return L10n.tr("Update Bingodays to import this board.", zhHans: "请更新 Bingodays 后再导入该棋盘", zhHant: "請更新 Bingodays 後再匯入該棋盤")
        case .invalidPayload:
            return L10n.tr("This shared board is invalid.", zhHans: "该分享棋盘数据无效", zhHant: "該分享棋盤資料無效")
        case .accountUnavailable:
            return L10n.tr("Sign in to iCloud in Settings to share a board.", zhHans: "请先在系统设置中登录 iCloud 后再分享", zhHant: "請先在系統設定中登入 iCloud 後再分享")
        case .networkUnavailable:
            return L10n.tr("Check your network connection and try again.", zhHans: "请检查网络后重试", zhHant: "請檢查網路後重試")
        case .unavailable:
            return L10n.tr("Cloud sharing is temporarily unavailable.", zhHans: "CloudKit 分享暂时不可用", zhHant: "CloudKit 分享暫時不可用")
        case .collisionLimitReached:
            return L10n.tr("Could not create a unique code. Please try again.", zhHans: "暂时无法生成唯一分享码，请重试", zhHant: "暫時無法產生唯一分享碼，請重試")
        }
    }
}

struct BoardShareLookup: Equatable, Sendable {
    let code: String
    let payload: BoardSharePayload
}

struct BoardSharePublishResult: Equatable, Sendable {
    let code: String
    let payload: BoardSharePayload
}

protocol BoardShareServicing: Sendable {
    func publish(
        board: BingoBoardStore.NamedBoard,
        now: Date
    ) async throws -> BoardSharePublishResult

    func lookup(
        code: String,
        now: Date
    ) async throws -> BoardShareLookup
}

enum BoardShareServiceFactory {
    static func makeDefaultService() -> any BoardShareServicing {
#if targetEnvironment(simulator)
        // Simulator test hosts do not carry the app's CloudKit entitlement. Creating
        // CKContainer there traps before Swift can surface an ordinary error.
        return BoardShareUnavailableService()
#else
        return BoardShareService(
            container: CKContainer(identifier: NativeICloudConfiguration.containerIdentifier)
        )
#endif
    }
}

private struct BoardShareUnavailableService: BoardShareServicing {
    func publish(
        board _: BingoBoardStore.NamedBoard,
        now _: Date
    ) async throws -> BoardSharePublishResult {
        throw BoardShareError.unavailable
    }

    func lookup(code _: String, now _: Date) async throws -> BoardShareLookup {
        throw BoardShareError.unavailable
    }
}

final class BoardShareService: BoardShareServicing {
    static let recordType = "BoardShare"

    private let container: CKContainer
    private let database: CKDatabase

    init(container: CKContainer) {
        self.container = container
        database = container.publicCloudDatabase
    }

    func publish(board: BingoBoardStore.NamedBoard, now: Date = .now) async throws -> BoardSharePublishResult {
        try await ensureAccountAvailable()
        let payload = try BoardSharePayload(
            board: board,
            createdAt: now,
            expiresAt: now.addingTimeInterval(30 * 24 * 60 * 60)
        )
        let encodedPayload = try encodedData(for: payload)

        for _ in 0..<6 {
            let code = BoardShareCode.generate()
            let record = CKRecord(
                recordType: Self.recordType,
                recordID: CKRecord.ID(recordName: code)
            )
            record["schemaVersion"] = payload.schemaVersion as NSNumber
            record["payloadData"] = encodedPayload as CKRecordValue
            record["createdAt"] = payload.createdAt as NSDate
            record["expiresAt"] = payload.expiresAt as NSDate

            do {
                _ = try await database.save(record)
                return BoardSharePublishResult(code: code, payload: payload)
            } catch {
                if isRecordCollision(error) {
                    continue
                }
                throw mapCloudError(error)
            }
        }

        throw BoardShareError.collisionLimitReached
    }

    func lookup(code rawCode: String, now: Date = .now) async throws -> BoardShareLookup {
        let code = BoardShareCode.normalized(rawCode)
        guard BoardShareCode.isValid(code) else {
            throw BoardShareError.invalidCode
        }

        do {
            let record = try await database.record(for: CKRecord.ID(recordName: code))
            guard record.recordType == Self.recordType,
                  let payloadData = record["payloadData"] as? Data else {
                throw BoardShareError.invalidPayload
            }
            let payload = try JSONDecoder().decode(BoardSharePayload.self, from: payloadData)
            try payload.validate(now: now)
            return BoardShareLookup(code: code, payload: payload)
        } catch let error as BoardShareError {
            throw error
        } catch {
            throw mapCloudError(error)
        }
    }

    private func ensureAccountAvailable() async throws {
        let status: CKAccountStatus = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<CKAccountStatus, Error>) in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
        guard status == .available else {
            throw BoardShareError.accountUnavailable
        }
    }

    private func encodedData(for payload: BoardSharePayload) throws -> Data {
        let data = try JSONEncoder().encode(payload)
        guard data.count <= BoardSharePayload.maximumPayloadBytes else {
            throw BoardShareError.invalidPayload
        }
        return data
    }

    private func isRecordCollision(_ error: Error) -> Bool {
        guard let cloudError = error as? CKError else { return false }
        return cloudError.code == .serverRecordChanged || cloudError.code == .batchRequestFailed
    }

    private func mapCloudError(_ error: Error) -> BoardShareError {
        guard let cloudError = error as? CKError else { return .unavailable }
        switch cloudError.code {
        case .unknownItem:
            return .notFound
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            return .networkUnavailable
        case .notAuthenticated, .permissionFailure:
            return .accountUnavailable
        default:
            return .unavailable
        }
    }
}

struct BoardSharePendingImport: Codable, Equatable {
    let code: String
    let payload: BoardSharePayload
    let savedAt: Date
}

enum BoardSharePendingImportStore {
    private static let key = "board_share_pending_import_v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }

    static func load() -> BoardSharePendingImport? {
        guard let data = defaults.data(forKey: key),
              let pending = try? JSONDecoder().decode(BoardSharePendingImport.self, from: data),
              (try? pending.payload.validate()) != nil else {
            return nil
        }
        return pending
    }

    static func save(code: String, payload: BoardSharePayload) {
        guard let data = try? JSONEncoder().encode(
            BoardSharePendingImport(code: code, payload: payload, savedAt: .now)
        ) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
