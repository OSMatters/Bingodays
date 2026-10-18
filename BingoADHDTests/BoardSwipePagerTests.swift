import XCTest
@testable import Bingodays

final class BoardSwipePagerTests: XCTestCase {
    func testSettledPagerOnlyBuildsCurrentBoardAndImmediateNeighbors() {
        for count in [1, 2, 3, 20, 100] {
            for active in 0..<count {
                let range = BoardSwipePageWindow.range(boardCount: count, activeIndex: active, settledIndex: active)
                XCTAssertTrue(range.contains(active))
                XCTAssertLessThanOrEqual(range.count, 3)
                XCTAssertEqual(Array(range).filter { $0 != active }, [active - 1, active + 1].filter { (0..<count).contains($0) })
            }
        }
    }

    func testEmptyAndMissingSelectionHaveSafeWindows() {
        XCTAssertEqual(BoardSwipePageWindow.range(boardCount: 0, activeIndex: nil, settledIndex: nil), 0..<0)
        XCTAssertEqual(BoardSwipePageWindow.range(boardCount: 20, activeIndex: nil, settledIndex: nil), 0..<2)
        XCTAssertEqual(BoardSwipePageWindow.range(boardCount: 20, activeIndex: 19, settledIndex: nil), 18..<20)
    }

    func testAdjacentTransitionKeepsBothEndpointsAndTheirNeighbors() {
        XCTAssertEqual(BoardSwipePageWindow.range(boardCount: 20, activeIndex: 10, settledIndex: 9), 8..<12)
        XCTAssertEqual(BoardSwipePageWindow.range(boardCount: 20, activeIndex: 9, settledIndex: 10), 8..<12)
    }

    func testDistantJumpKeepsEveryCrossedPageUntilCompletion() {
        let transition = BoardSwipePageWindow.range(boardCount: 20, activeIndex: 15, settledIndex: 3)
        XCTAssertTrue((3...15).allSatisfy(transition.contains))
        XCTAssertEqual(transition, 2..<17)
        XCTAssertEqual(BoardSwipePageWindow.range(boardCount: 20, activeIndex: 15, settledIndex: 15), 14..<17)
    }

    func testRapidRetargetKeepsPagesFromPreviousAnimation() {
        let previous = BoardSwipePageWindow.range(boardCount: 20, activeIndex: 15, settledIndex: 3)
        let reversed = BoardSwipePageWindow.range(boardCount: 20, activeIndex: 1, settledIndex: 3, retainedRange: previous)
        XCTAssertTrue(previous.allSatisfy(reversed.contains))
        XCTAssertTrue(reversed.contains(1))
        XCTAssertEqual(reversed, 0..<17)
    }

    func testDeletionClampsRetainedWindowToNewBoardCount() {
        XCTAssertEqual(BoardSwipePageWindow.range(boardCount: 3, activeIndex: 2, settledIndex: 19, retainedRange: 15..<20), 1..<3)
    }

    func testLongDragIncludesBothPartiallyVisiblePages() {
        let range = BoardSwipePageWindow.range(boardCount: 20, activeIndex: 10, settledIndex: 10, visibleIndex: 13)
        XCTAssertTrue(range.contains(13))
        XCTAssertTrue(range.contains(14))
        XCTAssertEqual(range, 9..<15)
        XCTAssertEqual(BoardSwipePageWindow.range(boardCount: 20, activeIndex: 0, settledIndex: 0, visibleIndex: -1), 0..<2)
    }

    @MainActor
    func testPreviewEqualityInvalidatesForSnapshotTimeAndSize() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let cells = BoardEngine.createEmptyGrid(size: 3)
        let board = SavedBoard(gridSize: 3, cells: cells, completedLines: [])
        let preview = BoardSwipePreviewView(savedBoard: board, currentTime: date, sideLength: 360)
        XCTAssertEqual(preview, BoardSwipePreviewView(savedBoard: board, currentTime: date, sideLength: 360))
        XCTAssertNotEqual(preview, BoardSwipePreviewView(savedBoard: board, currentTime: date.addingTimeInterval(1), sideLength: 360))
        XCTAssertNotEqual(preview, BoardSwipePreviewView(savedBoard: board, currentTime: date, sideLength: 500))
        var editedCells = cells
        editedCells[0][0] = BingoCell(text: "Edited task", isCompleted: true)
        let edited = SavedBoard(gridSize: 3, cells: editedCells, completedLines: [])
        XCTAssertNotEqual(preview, BoardSwipePreviewView(savedBoard: edited, currentTime: date, sideLength: 360))
        let resized = SavedBoard(gridSize: 2, cells: cells, completedLines: [])
        XCTAssertNotEqual(preview, BoardSwipePreviewView(savedBoard: resized, currentTime: date, sideLength: 360))
        let fullBoardChanged = SavedBoard(gridSize: 3, cells: cells, completedLines: [], fullBoardCells: editedCells)
        XCTAssertNotEqual(preview, BoardSwipePreviewView(savedBoard: fullBoardChanged, currentTime: date, sideLength: 360))
    }

    @MainActor
    func testProjectionWorkloadComparisonForTwentyBoards() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var cells = BoardEngine.createEmptyGrid(size: 5)
        for row in cells.indices {
            for column in cells[row].indices {
                cells[row][column] = BingoCell(text: "Task \(row)-\(column)", isCompleted: row == 0)
            }
        }
        let boards = (0..<20).map { _ in SavedBoard(gridSize: 5, cells: cells, completedLines: []) }
        let active = 10
        let allPreviews = boards.indices.filter { $0 != active }
        let visiblePreviews = BoardSwipePageWindow.range(boardCount: boards.count, activeIndex: active, settledIndex: active).filter { $0 != active }
        // Compare identical projection work under the old and new page selection.
        // This is a CPU workload comparison, not a frame-rate or SwiftUI body-count measurement.
        func elapsed(for indices: [Int]) -> TimeInterval {
            let start = Date.now
            for tick in 0..<100 {
                for index in indices {
                    _ = BoardSwipePreviewView(savedBoard: boards[index], currentTime: date.addingTimeInterval(Double(tick)), sideLength: 360).body
                }
            }
            return Date.now.timeIntervalSince(start)
        }
        let before = elapsed(for: allPreviews)
        let after = elapsed(for: visiblePreviews)
        XCTAssertEqual(allPreviews.count, 19)
        XCTAssertEqual(visiblePreviews.count, 2)
        print("PREVIEW_WORKLOAD boards=20 ticks=100 old_projections=1900 new_projections=200 old_seconds=\(before) new_seconds=\(after)")
    }
}
