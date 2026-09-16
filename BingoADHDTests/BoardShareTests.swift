import XCTest
@testable import Bingodays

final class BoardShareTests: XCTestCase {
    @MainActor
    func testPresentationStoreDoesNotCreateCloudKitServiceAtAppStartup() {
        let store = BoardSharePresentationStore()

        store.showMenu()

        XCTAssertEqual(store.page, .menu)
        XCTAssertFalse(store.isWorking)
    }

    func testGeneratedShareCodeHasTenDigitsAndPassesCheckDigit() {
        let code = BoardShareCode.generate()

        XCTAssertEqual(code.count, 10)
        XCTAssertTrue(BoardShareCode.isValid(code))
        XCTAssertTrue(BoardShareCode.isValid(BoardShareCode.display(code)))
    }

    func testShareCodeRejectsChangedCheckDigit() {
        let validCode = BoardShareCode.generate()
        let changedDigit = validCode.last == "9" ? "8" : "9"
        let invalidCode = String(validCode.dropLast()) + changedDigit

        XCTAssertFalse(BoardShareCode.isValid(invalidCode))
    }

    func testImportedTemplateCreatesFreshIncompleteCellsWithoutTaskRuntimeState() throws {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let payload = BoardSharePayload(
            boardName: "Morning plan",
            gridSize: 2,
            sourceLanguage: "en",
            cells: [
                .init(row: 0, column: 0, text: "Drink water"),
                .init(row: 1, column: 1, text: "Read")
            ],
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(30 * 24 * 60 * 60)
        )

        let board = try payload.makeNewLocalBoard()

        XCTAssertEqual(board.gridSize, 2)
        XCTAssertEqual(board.cells[0][0].text, "Drink water")
        XCTAssertEqual(board.cells[1][1].text, "Read")
        XCTAssertFalse(board.cells[0][0].isCompleted)
        XCTAssertFalse(board.cells[0][0].isForced)
        XCTAssertNil(board.cells[0][0].recurrenceRule)
        XCTAssertNil(board.cells[0][0].startVisibleAt)
        XCTAssertNil(board.cells[0][0].endVisibleAt)
        XCTAssertFalse(board.cells[0][0].startReminderEnabled)
        XCTAssertNil(board.cells[0][0].countdownEndsAt)
        XCTAssertEqual(board.cells[0][0].completionStreakCount, 0)
        XCTAssertTrue(board.completedLines.isEmpty)
        XCTAssertEqual(board.fullBoardCells?.count, BoardSharePayload.maximumGridSize)
    }

    func testBoardShareImportIsSeparatePremiumFeature() {
        XCTAssertEqual(
            AnalyticsEventContract.premiumFeature(forSource: "board_share_import"),
            .boardShareImport
        )
        XCTAssertEqual(
            AnalyticsEventContract.premiumFeature(forSource: "board_share_import_grid_5x5"),
            .boardShareImport
        )
    }

    func testBoardShareAnalyticsPayloadDoesNotIncludeUserContent() {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let payload = BoardSharePayload(
            boardName: "Private plan",
            gridSize: 2,
            sourceLanguage: "en",
            cells: [
                .init(row: 0, column: 0, text: "Private task"),
                .init(row: 1, column: 1, text: "Another task")
            ],
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(30 * 24 * 60 * 60)
        )

        let parameters = AnalyticsEventContract.boardSharePayloadParameters(payload)

        XCTAssertEqual(parameters["grid_size"] as? Int, 2)
        XCTAssertEqual(parameters["cell_count"] as? Int, 2)
        XCTAssertNil(parameters["board_name"])
        XCTAssertNil(parameters["code"])
        XCTAssertNil(parameters["cells"])
        XCTAssertNil(parameters["task_text"])
    }

    func testPayloadRejectsDuplicateCoordinatesAndExpiredTemplate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let duplicateCells = BoardSharePayload(
            boardName: "Plan",
            gridSize: 2,
            sourceLanguage: nil,
            cells: [
                .init(row: 0, column: 0, text: "A"),
                .init(row: 0, column: 0, text: "B")
            ],
            createdAt: now,
            expiresAt: now.addingTimeInterval(3600)
        )
        let expired = BoardSharePayload(
            boardName: "Plan",
            gridSize: 2,
            sourceLanguage: nil,
            cells: [],
            createdAt: now.addingTimeInterval(-7200),
            expiresAt: now.addingTimeInterval(-3600)
        )

        XCTAssertThrowsError(try duplicateCells.validate(now: now))
        XCTAssertThrowsError(try expired.validate(now: now)) { error in
            XCTAssertEqual(error as? BoardShareError, .expired)
        }
    }
}
