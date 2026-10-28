import XCTest

final class MacDesktopBoardSnapshotTests: XCTestCase {
    func testTimelineChangesOnlyWhenScheduledBoundaryIsReached() {
        var snapshot = makeSnapshot(boardID: UUID())
        let resetDate = snapshot.updatedAt.addingTimeInterval(3600)
        var resetCells = snapshot.cells
        resetCells[0] = .init(text: "读书", completed: false, inBingo: false)
        snapshot.futureStates = [.init(date: resetDate, cells: resetCells)]
        XCTAssertTrue(snapshot.cells(at: resetDate.addingTimeInterval(-1))[0].completed)
        XCTAssertFalse(snapshot.cells(at: resetDate)[0].completed)
        XCTAssertTrue(snapshot.cells[0].completed)
    }

    func testWidgetLinkIdentifiesBoardAndRejectsUnrelatedRoutes() {
        let id = UUID()
        let snapshot = makeSnapshot(boardID: id)
        XCTAssertEqual(MacDesktopBoardSnapshot.boardID(from: snapshot.destination), id)
        XCTAssertNil(MacDesktopBoardSnapshot.boardID(from: URL(string: "https://example.com/board/\(id)")!))
        XCTAssertNil(MacDesktopBoardSnapshot.boardID(from: URL(string: "bingodays-mac://settings/\(id)")!))
    }
    func testSnapshotRoundTripPreservesTaskCompletionAndSkin() throws {
        let snapshot = makeSnapshot(boardID: UUID())
        let restored = try JSONDecoder().decode(MacDesktopBoardSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored, snapshot)
        XCTAssertTrue(restored.cells[0].completed)
        XCTAssertEqual(restored.backgroundImage, "BackgroundSkin_bg_01")
    }
    func testWidgetRejectsIncompleteGridInsteadOfIndexingOutsideCells() throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("BingodaysMacWidgetTest-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let url = MacDesktopBoardSnapshot.fileURL(in: container)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bad = MacDesktopBoardSnapshot(boardID: nil, gridSize: 5, cells: [], accent: MacDesktopBoardSnapshot.empty.accent, surface: MacDesktopBoardSnapshot.empty.surface, outline: MacDesktopBoardSnapshot.empty.outline, backgroundImage: nil, updatedAt: .now)
        try JSONEncoder().encode(bad).write(to: url)
        XCTAssertNil(MacDesktopBoardSnapshot.load(from: container))
        let valid = makeSnapshot(boardID: UUID())
        try JSONEncoder().encode(valid).write(to: url, options: .atomic)
        XCTAssertEqual(MacDesktopBoardSnapshot.load(from: container), valid)
    }
    private func makeSnapshot(boardID: UUID) -> MacDesktopBoardSnapshot {
        var cells = MacDesktopBoardSnapshot.empty.cells
        cells[0] = .init(text: "读书", completed: true, inBingo: false)
        return MacDesktopBoardSnapshot(boardID: boardID, gridSize: 3, cells: cells, accent: MacDesktopBoardSnapshot.empty.accent, surface: MacDesktopBoardSnapshot.empty.surface, outline: MacDesktopBoardSnapshot.empty.outline, backgroundImage: "BackgroundSkin_bg_01", updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
}
